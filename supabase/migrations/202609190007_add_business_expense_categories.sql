-- Add business-oriented expense categories to Rainflow defaults.
-- Transportation already existed; this migration preserves it and adds the
-- remaining requested categories. Existing ledgers are backfilled idempotently.

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
    ('Office supplies', 122),
    ('Class material supplies', 124),
    ('Employee benefits', 126),
    ('Business operation', 128),
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

do $$
declare
  target record;
begin
  for target in select id from public.ledgers loop
    perform public.ensure_default_expense_categories(target.id);
  end loop;
end;
$$;
