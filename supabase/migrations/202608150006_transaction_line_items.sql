-- Persist structured receipt line items with the transaction so they remain
-- available after the capture dialog closes.

create table if not exists public.transaction_line_items (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers(id) on delete cascade,
  transaction_id uuid not null references public.ledger_transactions(id) on delete cascade,
  position integer not null check (position >= 0),
  description text not null check (char_length(trim(description)) > 0),
  quantity numeric,
  unit_price_minor_units bigint,
  amount_minor_units bigint,
  created_at timestamptz not null default now(),
  unique (transaction_id, position)
);

create index if not exists transaction_line_items_transaction_idx
on public.transaction_line_items (transaction_id, position);

alter table public.transaction_line_items enable row level security;

drop policy if exists transaction_line_items_select_member on public.transaction_line_items;
create policy transaction_line_items_select_member on public.transaction_line_items
for select using (public.can_access_ledger(ledger_id));

create or replace function public.replace_transaction_line_items(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  item_position integer := 0;
  inserted_count integer := 0;
  item_description text;
  item_quantity numeric;
  item_unit_price bigint;
  item_amount bigint;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not public.can_access_ledger(p_ledger_id) then
    raise exception 'ledger_not_found_or_forbidden' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.ledger_transactions t
    where t.id = p_transaction_id
      and t.ledger_id = p_ledger_id
      and t.deleted_at is null
  ) then
    raise exception 'transaction_not_found_or_forbidden' using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'line_items_must_be_array' using errcode = '22023';
  end if;

  delete from public.transaction_line_items
  where ledger_id = p_ledger_id
    and transaction_id = p_transaction_id;

  for item in select value from jsonb_array_elements(p_items) loop
    exit when item_position >= 50;
    item_description := left(trim(coalesce(item ->> 'description', '')), 240);
    if item_description <> '' then
      item_quantity := case
        when jsonb_typeof(item -> 'quantity') = 'number' then (item ->> 'quantity')::numeric
        else null
      end;
      item_unit_price := case
        when jsonb_typeof(item -> 'unitPriceMinorUnits') = 'number' then (item ->> 'unitPriceMinorUnits')::bigint
        else null
      end;
      item_amount := case
        when jsonb_typeof(item -> 'amountMinorUnits') = 'number' then (item ->> 'amountMinorUnits')::bigint
        else null
      end;

      insert into public.transaction_line_items (
        ledger_id,
        transaction_id,
        position,
        description,
        quantity,
        unit_price_minor_units,
        amount_minor_units
      ) values (
        p_ledger_id,
        p_transaction_id,
        item_position,
        item_description,
        item_quantity,
        item_unit_price,
        item_amount
      );
      inserted_count := inserted_count + 1;
    end if;
    item_position := item_position + 1;
  end loop;

  return inserted_count;
end;
$$;

grant execute on function public.replace_transaction_line_items(uuid, uuid, jsonb) to authenticated;
