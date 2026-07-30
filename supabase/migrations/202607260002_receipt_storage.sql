-- Private receipt storage, attachment finalization, and integrity-notification outbox.
-- The outbox is processed by a trusted server/Edge Function, never by the iPhone client.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'receipts',
  'receipts',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists receipt_objects_insert_owner on storage.objects;
drop policy if exists receipt_objects_select_owner on storage.objects;
drop policy if exists receipt_objects_update_owner on storage.objects;
drop policy if exists receipt_objects_delete_owner on storage.objects;

-- Finalized receipt objects are immutable to app clients. Replacement, orphan
-- cleanup, and deletion are trusted service operations so a client cannot alter
-- bytes after the manifest checksum is recorded.

create policy receipt_objects_insert_owner
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'receipts'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy receipt_objects_select_owner
on storage.objects
for select
to authenticated
using (
  bucket_id = 'receipts'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create table public.attachment_integrity_events (
  id uuid primary key default gen_random_uuid(),
  attachment_id uuid not null references public.attachment_manifests(id) on delete cascade,
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  issue_kind text not null check (issue_kind in ('missing', 'corrupt')),
  detail text,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  resolved_at timestamptz
);

create unique index attachment_integrity_open_issue_idx
on public.attachment_integrity_events (attachment_id, issue_kind)
where resolved_at is null;

alter table public.attachment_integrity_events enable row level security;
revoke all on public.attachment_integrity_events from anon, authenticated;
-- No client table policy is intentional. A trusted notification worker reads this
-- outbox with the service role and marks notified_at after sending one email.

create or replace function public.finalize_attachment(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_attachment_id uuid,
  p_object_key text,
  p_original_file_name text,
  p_mime_type text,
  p_byte_size bigint,
  p_sha256_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  expected_prefix text;
  created public.attachment_manifests;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not public.owns_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.ledger_transactions t
    where t.id = p_transaction_id
      and t.ledger_id = p_ledger_id
      and t.deleted_at is null
  ) then
    raise exception 'transaction_not_found' using errcode = 'P0002';
  end if;

  expected_prefix := auth.uid()::text || '/' || p_ledger_id::text || '/' || p_transaction_id::text || '/';
  if left(p_object_key, length(expected_prefix)) <> expected_prefix then
    raise exception 'invalid_attachment_path' using errcode = '42501';
  end if;

  if p_mime_type not in ('image/jpeg', 'image/png', 'image/heic', 'image/heif') then
    raise exception 'unsupported_attachment_type' using errcode = '22023';
  end if;

  if p_byte_size <= 0 or p_byte_size > 10485760 then
    raise exception 'invalid_attachment_size' using errcode = '22023';
  end if;

  if p_sha256_hex !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_attachment_checksum' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'receipts'
      and o.name = p_object_key
      and (storage.foldername(o.name))[1] = auth.uid()::text
  ) then
    raise exception 'receipt_object_not_found' using errcode = 'P0002';
  end if;

  insert into public.attachment_manifests (
    id,
    ledger_id,
    transaction_id,
    object_key,
    original_file_name,
    mime_type,
    byte_size,
    sha256_hex,
    status
  ) values (
    p_attachment_id,
    p_ledger_id,
    p_transaction_id,
    p_object_key,
    left(coalesce(nullif(trim(p_original_file_name), ''), 'receipt.jpg'), 255),
    p_mime_type,
    p_byte_size,
    p_sha256_hex,
    'active'
  )
  on conflict (id) do update
  set object_key = excluded.object_key,
      original_file_name = excluded.original_file_name,
      mime_type = excluded.mime_type,
      byte_size = excluded.byte_size,
      sha256_hex = excluded.sha256_hex,
      status = 'active',
      integrity_incident_id = null,
      notified_at = null
  where public.attachment_manifests.ledger_id = p_ledger_id
    and public.attachment_manifests.transaction_id = p_transaction_id
  returning * into created;

  if created.id is null then
    raise exception 'attachment_conflict' using errcode = '23505';
  end if;

  return to_jsonb(created);
end;
$$;

create or replace function public.report_attachment_integrity_issue(
  p_attachment_id uuid,
  p_issue_kind text,
  p_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.attachment_manifests;
  incident_id uuid;
begin
  if p_issue_kind not in ('missing', 'corrupt') then
    raise exception 'invalid_issue_kind' using errcode = '22023';
  end if;

  select a.* into target
  from public.attachment_manifests a
  where a.id = p_attachment_id
    and public.owns_ledger(a.ledger_id)
  for update;

  if target.id is null then
    raise exception 'attachment_not_found_or_forbidden' using errcode = '42501';
  end if;

  insert into public.attachment_integrity_events (
    attachment_id,
    ledger_id,
    owner_user_id,
    issue_kind,
    detail
  )
  select
    target.id,
    target.ledger_id,
    l.owner_user_id,
    p_issue_kind,
    left(p_detail, 1000)
  from public.ledgers l
  where l.id = target.ledger_id
  on conflict (attachment_id, issue_kind) where resolved_at is null
  do update set detail = coalesce(excluded.detail, public.attachment_integrity_events.detail)
  returning id into incident_id;

  update public.attachment_manifests
  set status = p_issue_kind::public.attachment_status,
      integrity_incident_id = incident_id
  where id = target.id;

  return incident_id;
end;
$$;

revoke all on function public.finalize_attachment(uuid, uuid, uuid, text, text, text, bigint, text) from public;
revoke all on function public.report_attachment_integrity_issue(uuid, text, text) from public;

grant execute on function public.finalize_attachment(uuid, uuid, uuid, text, text, text, bigint, text) to authenticated;
grant execute on function public.report_attachment_integrity_issue(uuid, text, text) to authenticated;
