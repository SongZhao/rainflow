-- Financial accounts are user-owned ledger structure. Income/expense/equity
-- accounts remain bookkeeping structure and are created with the ledger.

create or replace function public.create_financial_account(
  p_ledger_id uuid,
  p_name text,
  p_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  created public.accounts;
  normalized_name text;
  normalized_type public.account_type;
  next_display_order integer;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not (
    exists (
      select 1
      from public.ledger_memberships membership
      where membership.ledger_id = p_ledger_id
        and membership.user_id = auth.uid()
        and membership.role in ('owner', 'admin')
    )
    or exists (
      select 1
      from public.ledgers ledger
      where ledger.id = p_ledger_id
        and ledger.owner_user_id = auth.uid()
    )
  ) then
    raise exception 'ledger_admin_required' using errcode = '42501';
  end if;

  normalized_name := left(trim(coalesce(p_name, '')), 120);
  if normalized_name = '' then
    raise exception 'account_name_required' using errcode = '22023';
  end if;

  if p_type not in ('asset', 'liability') then
    raise exception 'invalid_financial_account_type' using errcode = '22023';
  end if;
  normalized_type := p_type::public.account_type;

  if exists (
    select 1
    from public.accounts existing
    where existing.ledger_id = p_ledger_id
      and existing.archived_at is null
      and lower(existing.name) = lower(normalized_name)
  ) then
    raise exception 'account_name_already_exists' using errcode = '23505';
  end if;

  select coalesce(max(account.display_order), 0) + 10
  into next_display_order
  from public.accounts account
  where account.ledger_id = p_ledger_id
    and account.archived_at is null
    and account.type in ('asset', 'liability');

  insert into public.accounts (ledger_id, name, type, display_order)
  values (p_ledger_id, normalized_name, normalized_type, next_display_order)
  returning * into created;

  return to_jsonb(created);
end;
$$;

revoke execute on function public.create_financial_account(uuid, text, text) from public, anon;
grant execute on function public.create_financial_account(uuid, text, text) to authenticated;

-- New ledgers start with categories and the hidden opening-balance account only.
-- Existing ledgers are intentionally untouched: no placeholder account is deleted.
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
  values (
    auth.uid(),
    left(coalesce(nullif(trim(ledger_name), ''), 'Personal'), 120),
    ledger_currency,
    normalized_kind
  )
  returning * into created;

  insert into public.ledger_memberships (ledger_id, user_id, role)
  values (created.id, auth.uid(), 'owner');

  insert into public.accounts (ledger_id, name, type, display_order) values
    (created.id, 'Salary', 'income', 50),
    (created.id, 'Other Income', 'income', 60),
    (created.id, 'Opening Balances', 'equity', 200);

  perform public.ensure_default_expense_categories(created.id);

  return to_jsonb(created);
end;
$$;

revoke execute on function public.create_ledger_with_type(text, text, text) from public, anon;
grant execute on function public.create_ledger_with_type(text, text, text) to authenticated;

revoke execute on function public.create_ledger(text, text) from public, anon;
grant execute on function public.create_ledger(text, text) to authenticated;
