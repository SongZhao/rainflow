-- Expand Rainflow's default expense categories for new ledgers and backfill
-- missing defaults into existing ledgers. Existing accounts and transactions are
-- left untouched; categories are inserted only when a ledger does not already
-- have an expense account with the same case-insensitive name.

create or replace function public.ensure_default_expense_categories(target_ledger_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.accounts (ledger_id, name, type, display_order)
  select target_ledger_id, defaults.name, 'expense', defaults.display_order
  from (values
    ('Groceries', 70),
    ('Dining', 80),
    ('Transportation', 90),
    ('Gas', 95),
    ('Housing', 100),
    ('Utilities', 110),
    ('Home & Repairs', 115),
    ('Shopping', 120),
    ('Healthcare', 130),
    ('Entertainment', 140),
    ('Travel', 145),
    ('Education', 150),
    ('Personal Care', 155),
    ('Gifts & Donations', 160),
    ('Insurance', 165),
    ('Fees & Taxes', 170),
    ('Other Expenses', 180)
  ) as defaults(name, display_order)
  where not exists (
    select 1
    from public.accounts existing
    where existing.ledger_id = target_ledger_id
      and existing.type = 'expense'
      and lower(existing.name) = lower(defaults.name)
      and existing.archived_at is null
  );
end;
$$;

-- Backfill current ledgers so receipt categorization can use the expanded list
-- immediately after this migration is applied.
do $$
declare
  target record;
begin
  for target in select id from public.ledgers loop
    perform public.ensure_default_expense_categories(target.id);
  end loop;
end;
$$;

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
    (created.id, 'Opening Balances', 'equity', 200);

  perform public.ensure_default_expense_categories(created.id);

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

grant execute on function public.ensure_default_expense_categories(uuid) to authenticated;
