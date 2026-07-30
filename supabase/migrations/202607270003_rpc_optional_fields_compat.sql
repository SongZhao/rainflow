-- Compatibility overloads for clients that omit empty optional text fields.
-- Swift's synthesized Encodable omits nil optionals, so older builds may call
-- these RPCs without p_payee and p_note.

create or replace function public.create_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_idempotency_key uuid,
  p_accounting_date date,
  p_description text,
  p_postings jsonb
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.create_transaction(
    p_ledger_id,
    p_transaction_id,
    p_idempotency_key,
    p_accounting_date,
    p_description,
    null::text,
    null::text,
    p_postings
  );
$$;

create or replace function public.update_transaction(
  p_ledger_id uuid,
  p_transaction_id uuid,
  p_expected_revision integer,
  p_accounting_date date,
  p_description text,
  p_postings jsonb
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.update_transaction(
    p_ledger_id,
    p_transaction_id,
    p_expected_revision,
    p_accounting_date,
    p_description,
    null::text,
    null::text,
    p_postings
  );
$$;

revoke all on function public.create_transaction(uuid, uuid, uuid, date, text, jsonb) from public;
revoke all on function public.update_transaction(uuid, uuid, integer, date, text, jsonb) from public;

grant execute on function public.create_transaction(uuid, uuid, uuid, date, text, jsonb) to authenticated;
grant execute on function public.update_transaction(uuid, uuid, integer, date, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
