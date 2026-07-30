-- Ledger membership, shared-ledger invitations, and multi-ledger access.

do $$ begin
  create type public.ledger_type as enum ('personal', 'shared');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ledger_role as enum ('owner', 'admin', 'member');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.ledger_invite_status as enum ('pending', 'accepted', 'revoked');
exception when duplicate_object then null;
end $$;

alter table public.ledgers
add column if not exists ledger_type public.ledger_type not null default 'personal';

create table if not exists public.ledger_memberships (
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.ledger_role not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (ledger_id, user_id)
);

create table if not exists public.ledger_invites (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  invited_email text not null check (invited_email = lower(trim(invited_email)) and invited_email like '%@%'),
  role public.ledger_role not null check (role in ('admin', 'member')),
  invited_by uuid not null references auth.users(id) on delete cascade,
  status public.ledger_invite_status not null default 'pending',
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ledger_memberships_user_idx
on public.ledger_memberships (user_id, ledger_id);

create unique index if not exists ledger_invites_pending_email_idx
on public.ledger_invites (ledger_id, invited_email)
where status = 'pending';

insert into public.ledger_memberships (ledger_id, user_id, role)
select l.id, l.owner_user_id, 'owner'::public.ledger_role
from public.ledgers l
on conflict (ledger_id, user_id) do update
set role = 'owner',
    updated_at = now();

drop trigger if exists ledger_memberships_touch_updated_at on public.ledger_memberships;
create trigger ledger_memberships_touch_updated_at before update on public.ledger_memberships
for each row execute function public.touch_updated_at();

drop trigger if exists ledger_invites_touch_updated_at on public.ledger_invites;
create trigger ledger_invites_touch_updated_at before update on public.ledger_invites
for each row execute function public.touch_updated_at();

create or replace function public.can_access_ledger(target_ledger_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ledger_memberships m
    where m.ledger_id = target_ledger_id
      and m.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.ledgers l
    where l.id = target_ledger_id
      and l.owner_user_id = auth.uid()
  );
$$;

create or replace function public.can_admin_ledger(target_ledger_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ledger_memberships m
    where m.ledger_id = target_ledger_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'admin')
  )
  or exists (
    select 1
    from public.ledgers l
    where l.id = target_ledger_id
      and l.owner_user_id = auth.uid()
  );
$$;

create or replace function public.owns_ledger(target_ledger_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_ledger(target_ledger_id);
$$;

create or replace function public.validate_posting_payload(
  target_ledger_id uuid,
  posting_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  posting_count integer;
  total numeric;
  currency_count integer;
  invalid_account_count integer;
  ledger_currency text;
begin
  select currency_code into ledger_currency
  from public.ledgers
  where id = target_ledger_id
    and public.can_access_ledger(target_ledger_id)
  for update;

  if ledger_currency is null then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  if jsonb_typeof(posting_payload) <> 'array' then
    raise exception 'postings_must_be_array' using errcode = '22023';
  end if;

  select count(*), coalesce(sum((item->>'amount_minor_units')::numeric), 0), count(distinct item->>'currency_code')
  into posting_count, total, currency_count
  from jsonb_array_elements(posting_payload) item;

  if posting_count < 2 then
    raise exception 'requires_two_postings' using errcode = '23514';
  end if;

  if total <> 0 then
    raise exception 'unbalanced_transaction' using detail = total::text, errcode = '23514';
  end if;

  if currency_count <> 1 or exists (
    select 1 from jsonb_array_elements(posting_payload) item
    where item->>'currency_code' <> ledger_currency
  ) then
    raise exception 'currency_mismatch' using errcode = '23514';
  end if;

  select count(*) into invalid_account_count
  from jsonb_array_elements(posting_payload) item
  left join public.accounts a
    on a.id = (item->>'account_id')::uuid
   and a.ledger_id = target_ledger_id
   and a.archived_at is null
  where a.id is null;

  if invalid_account_count > 0 then
    raise exception 'invalid_or_archived_account' using errcode = '23503';
  end if;
end;
$$;

drop policy if exists ledgers_select_owner on public.ledgers;
drop policy if exists accounts_select_owner on public.accounts;
drop policy if exists transactions_select_owner on public.ledger_transactions;
drop policy if exists postings_select_owner on public.postings;
drop policy if exists attachments_select_owner on public.attachment_manifests;
drop policy if exists ledgers_select_member on public.ledgers;
drop policy if exists accounts_select_member on public.accounts;
drop policy if exists transactions_select_member on public.ledger_transactions;
drop policy if exists postings_select_member on public.postings;
drop policy if exists attachments_select_member on public.attachment_manifests;

create policy ledgers_select_member on public.ledgers
for select using (public.can_access_ledger(id));
create policy accounts_select_member on public.accounts
for select using (public.can_access_ledger(ledger_id));
create policy transactions_select_member on public.ledger_transactions
for select using (public.can_access_ledger(ledger_id));
create policy postings_select_member on public.postings
for select using (
  exists (
    select 1 from public.ledger_transactions t
    where t.id = transaction_id and public.can_access_ledger(t.ledger_id)
  )
);
create policy attachments_select_member on public.attachment_manifests
for select using (public.can_access_ledger(ledger_id));

alter table public.ledger_memberships enable row level security;
alter table public.ledger_invites enable row level security;

drop policy if exists ledger_memberships_select_member on public.ledger_memberships;
drop policy if exists ledger_invites_select_admin on public.ledger_invites;

create policy ledger_memberships_select_member on public.ledger_memberships
for select using (user_id = auth.uid() or public.can_admin_ledger(ledger_id));

create policy ledger_invites_select_admin on public.ledger_invites
for select using (public.can_admin_ledger(ledger_id));

create or replace function public.create_ledger_with_type(
  ledger_name text,
  ledger_currency text,
  ledger_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  created public.ledgers;
  normalized_kind public.ledger_type;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if ledger_kind not in ('personal', 'shared') then
    raise exception 'invalid_ledger_type' using errcode = '22023';
  end if;
  normalized_kind := ledger_kind::public.ledger_type;

  insert into public.ledgers (owner_user_id, name, currency_code, ledger_type)
  values (auth.uid(), left(coalesce(nullif(trim(ledger_name), ''), 'Personal'), 120), ledger_currency, normalized_kind)
  returning * into created;

  insert into public.ledger_memberships (ledger_id, user_id, role)
  values (created.id, auth.uid(), 'owner');

  insert into public.accounts (ledger_id, name, type, display_order) values
    (created.id, 'Checking', 'asset', 10),
    (created.id, 'Savings', 'asset', 20),
    (created.id, 'Cash', 'asset', 30),
    (created.id, 'Credit Card', 'liability', 40),
    (created.id, 'Salary', 'income', 50),
    (created.id, 'Other Income', 'income', 60),
    (created.id, 'Groceries', 'expense', 70),
    (created.id, 'Dining', 'expense', 80),
    (created.id, 'Transportation', 'expense', 90),
    (created.id, 'Housing', 'expense', 100),
    (created.id, 'Utilities', 'expense', 110),
    (created.id, 'Shopping', 'expense', 120),
    (created.id, 'Healthcare', 'expense', 130),
    (created.id, 'Entertainment', 'expense', 140),
    (created.id, 'Other Expenses', 'expense', 150),
    (created.id, 'Opening Balances', 'equity', 160);

  return to_jsonb(created);
end;
$$;

create or replace function public.create_ledger(
  ledger_name text,
  ledger_currency text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.create_ledger_with_type(ledger_name, ledger_currency, 'personal');
$$;

create or replace function public.invite_ledger_member(
  p_ledger_id uuid,
  p_invited_email text,
  p_role text default 'member'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text;
  normalized_role public.ledger_role;
  created public.ledger_invites;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not public.can_admin_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.ledgers l
    where l.id = p_ledger_id and l.ledger_type = 'shared'
  ) then
    raise exception 'shared_ledger_required' using errcode = '23514';
  end if;

  if p_role not in ('admin', 'member') then
    raise exception 'invalid_ledger_role' using errcode = '22023';
  end if;
  normalized_role := p_role::public.ledger_role;
  normalized_email := lower(trim(p_invited_email));

  if normalized_email = '' or normalized_email not like '%@%' then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  insert into public.ledger_invites (
    ledger_id,
    invited_email,
    role,
    invited_by
  ) values (
    p_ledger_id,
    normalized_email,
    normalized_role,
    auth.uid()
  )
  on conflict (ledger_id, invited_email) where status = 'pending'
  do update set role = excluded.role,
                invited_by = excluded.invited_by,
                updated_at = now()
  returning * into created;

  return to_jsonb(created);
end;
$$;

create or replace function public.accept_current_user_ledger_invites()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_email text;
  accepted_count integer;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  current_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if current_email = '' then
    return jsonb_build_object('accepted', 0);
  end if;

  insert into public.ledger_memberships (ledger_id, user_id, role)
  select i.ledger_id, auth.uid(), i.role
  from public.ledger_invites i
  where i.invited_email = current_email
    and i.status = 'pending'
  on conflict (ledger_id, user_id) do update
  set role = excluded.role,
      updated_at = now();

  update public.ledger_invites i
  set status = 'accepted',
      accepted_by = auth.uid(),
      accepted_at = now()
  where i.invited_email = current_email
    and i.status = 'pending';

  get diagnostics accepted_count = row_count;
  return jsonb_build_object('accepted', accepted_count);
end;
$$;

create or replace function public.can_access_receipt_object(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target_ledger_id uuid;
begin
  target_ledger_id := nullif(split_part(object_name, '/', 2), '')::uuid;
  return public.can_access_ledger(target_ledger_id);
exception when others then
  return false;
end;
$$;

drop policy if exists receipt_objects_select_owner on storage.objects;
drop policy if exists receipt_objects_select_member on storage.objects;
create policy receipt_objects_select_member
on storage.objects
for select
to authenticated
using (
  bucket_id = 'receipts'
  and public.can_access_receipt_object(name)
);

revoke all on public.ledger_memberships, public.ledger_invites from anon, authenticated;
grant select on public.ledger_memberships, public.ledger_invites to authenticated;

revoke all on function public.can_access_ledger(uuid) from public;
revoke all on function public.can_admin_ledger(uuid) from public;
revoke all on function public.can_access_receipt_object(text) from public;
revoke all on function public.create_ledger_with_type(text, text, text) from public;
revoke all on function public.invite_ledger_member(uuid, text, text) from public;
revoke all on function public.accept_current_user_ledger_invites() from public;

grant execute on function public.can_access_ledger(uuid) to authenticated;
grant execute on function public.can_admin_ledger(uuid) to authenticated;
grant execute on function public.can_access_receipt_object(text) to authenticated;
grant execute on function public.create_ledger_with_type(text, text, text) to authenticated;
grant execute on function public.create_ledger(text, text) to authenticated;
grant execute on function public.invite_ledger_member(uuid, text, text) to authenticated;
grant execute on function public.accept_current_user_ledger_invites() to authenticated;

notify pgrst, 'reload schema';
