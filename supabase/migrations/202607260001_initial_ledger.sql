-- Rainflow authoritative ledger schema.
-- Apply through the Supabase CLI after reviewing in a development project.

create extension if not exists pgcrypto;

create type public.account_type as enum ('asset', 'liability', 'equity', 'income', 'expense');
create type public.attachment_status as enum ('temporary', 'active', 'missing', 'corrupt', 'deleted');

create table public.ledgers (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  currency_code text not null check (currency_code in ('USD', 'CAD', 'EUR', 'GBP', 'JPY', 'AUD')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_user_id)
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  type public.account_type not null,
  parent_id uuid,
  display_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id, id),
  unique (ledger_id, name),
  constraint accounts_parent_same_ledger_fk
    foreign key (ledger_id, parent_id)
    references public.accounts (ledger_id, id)
    on delete restrict
);

create table public.ledger_transactions (
  id uuid primary key,
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  accounting_date date not null,
  description text not null default '',
  payee text,
  note text,
  source text,
  import_identifier text,
  revision integer not null default 1 check (revision >= 1),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ledger_id, id),
  unique (ledger_id, source, import_identifier)
);

create table public.postings (
  id uuid primary key,
  transaction_id uuid not null references public.ledger_transactions(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  amount_minor_units bigint not null,
  currency_code text not null,
  memo text,
  created_at timestamptz not null default now(),
  unique (transaction_id, id)
);

create table public.attachment_manifests (
  id uuid primary key,
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  transaction_id uuid,
  object_key text not null unique,
  original_file_name text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  sha256_hex text not null check (sha256_hex ~ '^[0-9a-f]{64}$'),
  status public.attachment_status not null default 'temporary',
  integrity_incident_id uuid,
  notified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attachment_transaction_same_ledger_fk
    foreign key (ledger_id, transaction_id)
    references public.ledger_transactions (ledger_id, id)
    on delete cascade
);

create table public.idempotency_keys (
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  key uuid not null,
  command_name text not null,
  aggregate_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (ledger_id, key)
);

create index accounts_ledger_archived_idx on public.accounts (ledger_id, archived_at);
create index ledger_transactions_ledger_date_idx on public.ledger_transactions (ledger_id, accounting_date desc);
create index ledger_transactions_ledger_deleted_idx on public.ledger_transactions (ledger_id, deleted_at);
create index postings_account_idx on public.postings (account_id);
create index postings_transaction_idx on public.postings (transaction_id);
create index attachment_transaction_idx on public.attachment_manifests (transaction_id);
create index attachment_status_idx on public.attachment_manifests (status);

-- Defense in depth: every committed transaction must remain balanced even if a
-- future trusted server path writes outside the public RPC functions.
create or replace function public.assert_transaction_balanced(target_transaction_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  target_ledger_id uuid;
  ledger_currency text;
  posting_count integer;
  posting_sum numeric;
  currency_count integer;
  invalid_account_count integer;
begin
  select t.ledger_id, l.currency_code
  into target_ledger_id, ledger_currency
  from public.ledger_transactions t
  join public.ledgers l on l.id = t.ledger_id
  where t.id = target_transaction_id;

  -- Deleting a transaction cascades its postings; no invariant remains to check.
  if target_ledger_id is null then
    return;
  end if;

  select
    count(*),
    coalesce(sum(p.amount_minor_units::numeric), 0),
    count(distinct p.currency_code),
    count(*) filter (where a.id is null)
  into posting_count, posting_sum, currency_count, invalid_account_count
  from public.postings p
  left join public.accounts a
    on a.id = p.account_id
   and a.ledger_id = target_ledger_id
  where p.transaction_id = target_transaction_id;

  if posting_count < 2 then
    raise exception 'requires_two_postings' using errcode = '23514';
  end if;
  if posting_sum <> 0 then
    raise exception 'unbalanced_transaction' using detail = posting_sum::text, errcode = '23514';
  end if;
  if currency_count <> 1 or exists (
    select 1 from public.postings p
    where p.transaction_id = target_transaction_id
      and p.currency_code <> ledger_currency
  ) then
    raise exception 'currency_mismatch' using errcode = '23514';
  end if;
  if invalid_account_count > 0 then
    raise exception 'posting_account_ledger_mismatch' using errcode = '23503';
  end if;
end;
$$;

create or replace function public.check_transaction_balance_trigger()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.assert_transaction_balanced(old.transaction_id);
  elsif tg_op = 'INSERT' then
    perform public.assert_transaction_balanced(new.transaction_id);
  else
    -- A trusted maintenance path could move a posting between transactions.
    -- Validate both aggregates so the old transaction cannot be left broken.
    perform public.assert_transaction_balanced(old.transaction_id);
    if new.transaction_id is distinct from old.transaction_id then
      perform public.assert_transaction_balanced(new.transaction_id);
    end if;
  end if;
  return null;
end;
$$;

create or replace function public.check_transaction_header_balance_trigger()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.assert_transaction_balanced(new.id);
  return null;
end;
$$;

create constraint trigger postings_balanced_deferred
after insert or update or delete on public.postings
deferrable initially deferred
for each row execute function public.check_transaction_balance_trigger();

create constraint trigger transaction_balanced_deferred
after insert or update on public.ledger_transactions
deferrable initially deferred
for each row execute function public.check_transaction_header_balance_trigger();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger ledgers_touch_updated_at before update on public.ledgers
for each row execute function public.touch_updated_at();
create trigger accounts_touch_updated_at before update on public.accounts
for each row execute function public.touch_updated_at();
create trigger transactions_touch_updated_at before update on public.ledger_transactions
for each row execute function public.touch_updated_at();
create trigger attachments_touch_updated_at before update on public.attachment_manifests
for each row execute function public.touch_updated_at();

create or replace function public.owns_ledger(target_ledger_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ledgers l
    where l.id = target_ledger_id
      and l.owner_user_id = auth.uid()
  );
$$;

alter table public.ledgers enable row level security;
alter table public.accounts enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.postings enable row level security;
alter table public.attachment_manifests enable row level security;
alter table public.idempotency_keys enable row level security;

create policy ledgers_select_owner on public.ledgers
for select using (owner_user_id = auth.uid());
create policy accounts_select_owner on public.accounts
for select using (public.owns_ledger(ledger_id));
create policy transactions_select_owner on public.ledger_transactions
for select using (public.owns_ledger(ledger_id));
create policy postings_select_owner on public.postings
for select using (
  exists (
    select 1 from public.ledger_transactions t
    where t.id = transaction_id and public.owns_ledger(t.ledger_id)
  )
);
create policy attachments_select_owner on public.attachment_manifests
for select using (public.owns_ledger(ledger_id));

-- Clients receive read access through RLS. All writes go through security-definer commands.

create or replace function public.create_ledger(
  ledger_name text,
  ledger_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  created public.ledgers;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  insert into public.ledgers (owner_user_id, name, currency_code)
  values (auth.uid(), ledger_name, ledger_currency)
  returning * into created;

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
  where id = target_ledger_id and owner_user_id = auth.uid()
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

create or replace function public.create_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_idempotency_key uuid,
  p_accounting_date date,
  p_description text,
  p_payee text,
  p_note text,
  p_postings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_result jsonb;
  command_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not public.owns_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  -- Serialize retries carrying the same idempotency key so concurrent network
  -- retries return one result instead of racing into duplicate inserts.
  perform pg_advisory_xact_lock(
    hashtextextended(p_ledger_id::text || ':' || p_idempotency_key::text, 0)
  );

  select i.result into existing_result
  from public.idempotency_keys i
  where i.ledger_id = p_ledger_id and i.key = p_idempotency_key;

  if existing_result is not null then
    return existing_result;
  end if;

  perform public.validate_posting_payload(p_ledger_id, p_postings);

  insert into public.ledger_transactions (
    id, ledger_id, accounting_date, description, payee, note, revision
  ) values (
    p_transaction_id, p_ledger_id, p_accounting_date, coalesce(p_description, ''), p_payee, p_note, 1
  );

  insert into public.postings (id, transaction_id, account_id, amount_minor_units, currency_code, memo)
  select
    (item->>'id')::uuid,
    p_transaction_id,
    (item->>'account_id')::uuid,
    (item->>'amount_minor_units')::bigint,
    item->>'currency_code',
    item->>'memo'
  from jsonb_array_elements(p_postings) item;

  command_result := jsonb_build_object('id', p_transaction_id, 'revision', 1);
  insert into public.idempotency_keys (ledger_id, key, command_name, aggregate_id, result)
  values (p_ledger_id, p_idempotency_key, 'create_transaction', p_transaction_id, command_result);

  return command_result;
end;
$$;

create or replace function public.update_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_expected_revision integer,
  p_accounting_date date,
  p_description text,
  p_payee text,
  p_note text,
  p_postings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_revision integer;
  next_revision integer;
begin
  if not public.owns_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  select t.revision into current_revision
  from public.ledger_transactions t
  where t.id = p_transaction_id and t.ledger_id = p_ledger_id and t.deleted_at is null
  for update;

  if current_revision is null then
    raise exception 'transaction_not_found' using errcode = 'P0002';
  end if;
  if current_revision <> p_expected_revision then
    raise exception 'stale_revision' using detail = current_revision::text, errcode = '40001';
  end if;

  perform public.validate_posting_payload(p_ledger_id, p_postings);
  next_revision := current_revision + 1;

  update public.ledger_transactions t
  set accounting_date = p_accounting_date,
      description = coalesce(p_description, ''),
      payee = p_payee,
      note = p_note,
      revision = next_revision
  where t.id = p_transaction_id;

  delete from public.postings p where p.transaction_id = p_transaction_id;

  insert into public.postings (id, transaction_id, account_id, amount_minor_units, currency_code, memo)
  select
    (item->>'id')::uuid,
    p_transaction_id,
    (item->>'account_id')::uuid,
    (item->>'amount_minor_units')::bigint,
    item->>'currency_code',
    item->>'memo'
  from jsonb_array_elements(p_postings) item;

  return jsonb_build_object('id', p_transaction_id, 'revision', next_revision);
end;
$$;

create or replace function public.soft_delete_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  next_revision integer;
begin
  if not public.owns_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  update public.ledger_transactions t
  set deleted_at = now(), revision = t.revision + 1
  where t.id = p_transaction_id
    and t.ledger_id = p_ledger_id
    and t.revision = p_expected_revision
    and t.deleted_at is null
  returning t.revision into next_revision;

  if next_revision is null then
    raise exception 'stale_revision_or_not_found' using errcode = '40001';
  end if;

  return jsonb_build_object('id', p_transaction_id, 'revision', next_revision, 'deleted', true);
end;
$$;

create or replace function public.restore_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  next_revision integer;
  current_postings jsonb;
begin
  if not public.owns_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  select jsonb_agg(jsonb_build_object(
    'id', p.id,
    'account_id', p.account_id,
    'amount_minor_units', p.amount_minor_units,
    'currency_code', p.currency_code,
    'memo', p.memo
  )) into current_postings
  from public.postings p
  join public.ledger_transactions t on t.id = p.transaction_id
  where t.id = p_transaction_id and t.ledger_id = p_ledger_id;

  perform public.validate_posting_payload(p_ledger_id, current_postings);

  update public.ledger_transactions t
  set deleted_at = null, revision = t.revision + 1
  where t.id = p_transaction_id
    and t.ledger_id = p_ledger_id
    and t.revision = p_expected_revision
    and t.deleted_at is not null
  returning t.revision into next_revision;

  if next_revision is null then
    raise exception 'stale_revision_or_not_found' using errcode = '40001';
  end if;

  return jsonb_build_object('id', p_transaction_id, 'revision', next_revision, 'deleted', false);
end;
$$;

-- Supabase may apply broad default grants to objects in exposed schemas. Keep
-- ledger tables read-only for signed-in clients and force every mutation through
-- the security-definer command functions below.
revoke all on public.ledgers, public.accounts, public.ledger_transactions, public.postings,
  public.attachment_manifests, public.idempotency_keys from anon, authenticated;
grant select on public.ledgers, public.accounts, public.ledger_transactions, public.postings,
  public.attachment_manifests to authenticated;

revoke all on function public.assert_transaction_balanced(uuid) from public;
revoke all on function public.check_transaction_balance_trigger() from public;
revoke all on function public.check_transaction_header_balance_trigger() from public;
revoke all on function public.touch_updated_at() from public;
revoke all on function public.owns_ledger(uuid) from public;
revoke all on function public.validate_posting_payload(uuid, jsonb) from public;
revoke all on function public.create_ledger(text, text) from public;
revoke all on function public.create_transaction(uuid, uuid, uuid, date, text, text, text, jsonb) from public;
revoke all on function public.update_transaction(uuid, uuid, integer, date, text, text, text, jsonb) from public;
revoke all on function public.soft_delete_transaction(uuid, uuid, integer) from public;
revoke all on function public.restore_transaction(uuid, uuid, integer) from public;

-- RLS policies call owns_ledger as the authenticated role, so EXECUTE is
-- required even though the helper itself is SECURITY DEFINER.
grant execute on function public.owns_ledger(uuid) to authenticated;
grant execute on function public.create_ledger(text, text) to authenticated;
grant execute on function public.create_transaction(uuid, uuid, uuid, date, text, text, text, jsonb) to authenticated;
grant execute on function public.update_transaction(uuid, uuid, integer, date, text, text, text, jsonb) to authenticated;
grant execute on function public.soft_delete_transaction(uuid, uuid, integer) to authenticated;
grant execute on function public.restore_transaction(uuid, uuid, integer) to authenticated;
