-- ============================================================================================
-- Service Billing Tool - database hardening.  Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run.
-- Safe to run again (idempotent). Run AFTER schema.sql.
--
-- What it does
--   1. Allow-list: only e-mails in public.allowed_users can read/write business data
--      (today's Auth users are added automatically; anonymous sign-ins and any future sign-ups are blocked).
--   2. If a user has turned on two-step verification (Security button in the app), data is only
--      available after the code is entered (aal2). Users without it are unaffected.
--   3. Sanity limits on stored rows (id format, JSON object, max size) and a UNIQUE invoice number.
--   4. Audit log: every insert/update/delete of clients, pricing and invoices is recorded, and cannot be edited by users.
--   5. Storage bucket 'proofs': 10 MB limit, only JPEG/PDF, fixed path pattern.
--
-- LOCK-OUT SAFETY: before running, make sure you are signed in to the app with the account you want to keep.
-- After running, check:   select * from public.allowed_users;   -> your e-mail must be listed.
-- To add someone:  insert into public.allowed_users values ('name@example.com');
-- To undo step 1/2 in an emergency:  see the ROLLBACK section at the bottom.
-- ============================================================================================

begin;

-- ---------- 1. allow-list ----------
create table if not exists public.allowed_users (email text primary key);
alter table public.allowed_users enable row level security;      -- no policies: only the function below can read it
revoke all on public.allowed_users from anon, authenticated;
insert into public.allowed_users (email)
  select lower(email) from auth.users where email is not null
  on conflict do nothing;

create or replace function public.is_allowed() returns boolean
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select
    exists (select 1 from public.allowed_users a where a.email = lower(coalesce(auth.jwt() ->> 'email', '')))
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
    and ( coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
          or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified') );
$$;
revoke all on function public.is_allowed() from public, anon;
grant execute on function public.is_allowed() to authenticated;

do $$
declare t text;
begin
  foreach t in array array['clients','pricing','invoices','meta'] loop
    execute format('drop policy if exists "auth full access" on public.%I', t);
    execute format('drop policy if exists "allowed users" on public.%I', t);
    execute format('create policy "allowed users" on public.%I for all to authenticated using ((select public.is_allowed())) with check ((select public.is_allowed()))', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke truncate, references, trigger on public.%I from authenticated', t);
  end loop;
end $$;

-- ---------- 3. sanity limits ----------
alter table public.clients  drop constraint if exists clients_sane;
alter table public.clients  add  constraint clients_sane  check (id ~ '^[A-Za-z0-9_-]{1,80}$' and jsonb_typeof(data) = 'object' and pg_column_size(data) < 200000);
alter table public.pricing  drop constraint if exists pricing_sane;
alter table public.pricing  add  constraint pricing_sane  check (id ~ '^[A-Za-z0-9_-]{1,80}$' and jsonb_typeof(data) = 'object' and pg_column_size(data) < 200000);
alter table public.invoices drop constraint if exists invoices_sane;
alter table public.invoices add  constraint invoices_sane check (id ~ '^[A-Za-z0-9_-]{1,80}$' and jsonb_typeof(data) = 'object' and pg_column_size(data) < 500000);
alter table public.meta     drop constraint if exists meta_sane;
alter table public.meta     add  constraint meta_sane     check (id ~ '^[A-Za-z0-9_-]{1,40}$'  and jsonb_typeof(data) = 'object' and pg_column_size(data) < 3000000);

-- ---------- 4. audit log ----------
create table if not exists public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor uuid, actor_email text,
  tbl text not null, op text not null, row_id text,
  old_data jsonb, new_data jsonb
);
alter table public.audit_log enable row level security;
drop policy if exists "read audit" on public.audit_log;
create policy "read audit" on public.audit_log for select to authenticated using ((select public.is_allowed()));
revoke all on public.audit_log from anon;
revoke insert, update, delete, truncate on public.audit_log from authenticated;
grant select on public.audit_log to authenticated;

create or replace function public.log_change() returns trigger
language plpgsql security definer set search_path = public, auth, pg_temp as $$
begin
  insert into public.audit_log (actor, actor_email, tbl, op, row_id, old_data, new_data)
  values (auth.uid(), auth.jwt() ->> 'email', tg_table_name, tg_op,
          case when tg_op = 'DELETE' then old.id else new.id end,
          case when tg_op in ('UPDATE','DELETE') then old.data end,
          case when tg_op in ('INSERT','UPDATE') then new.data end);
  return null;
end $$;
revoke all on function public.log_change() from public, anon, authenticated;

drop trigger if exists audit_clients  on public.clients;
drop trigger if exists audit_pricing  on public.pricing;
drop trigger if exists audit_invoices on public.invoices;
create trigger audit_clients  after insert or update or delete on public.clients  for each row execute function public.log_change();
create trigger audit_pricing  after insert or update or delete on public.pricing  for each row execute function public.log_change();
create trigger audit_invoices after insert or update or delete on public.invoices for each row execute function public.log_change();

-- ---------- 5. storage bucket 'proofs' ----------
update storage.buckets
   set public = false, file_size_limit = 10485760, allowed_mime_types = array['image/jpeg','application/pdf']
 where id = 'proofs';

drop policy if exists "auth read proofs"   on storage.objects;
drop policy if exists "auth insert proofs" on storage.objects;
drop policy if exists "auth update proofs" on storage.objects;
drop policy if exists "auth delete proofs" on storage.objects;
drop policy if exists "proofs read"   on storage.objects;
drop policy if exists "proofs insert" on storage.objects;
drop policy if exists "proofs update" on storage.objects;
drop policy if exists "proofs delete" on storage.objects;
create policy "proofs read"   on storage.objects for select to authenticated using      (bucket_id = 'proofs' and (select public.is_allowed()));
create policy "proofs insert" on storage.objects for insert to authenticated with check (bucket_id = 'proofs' and (select public.is_allowed()) and name ~ '^[A-Za-z0-9_-]{1,100}/[A-Za-z0-9_-]{1,100}\.(jpg|pdf)$');
create policy "proofs update" on storage.objects for update to authenticated using      (bucket_id = 'proofs' and (select public.is_allowed()))
                                                                              with check (bucket_id = 'proofs' and (select public.is_allowed()) and name ~ '^[A-Za-z0-9_-]{1,100}/[A-Za-z0-9_-]{1,100}\.(jpg|pdf)$');
create policy "proofs delete" on storage.objects for delete to authenticated using      (bucket_id = 'proofs' and (select public.is_allowed()));

commit;

-- ---------- 3b. unique invoice number (separate so a duplicate cannot undo everything above) ----------
do $$
begin
  create unique index if not exists invoices_no_uniq on public.invoices ((data ->> 'no'));
exception when unique_violation then
  raise notice 'Duplicate invoice numbers exist - unique index NOT created. Fix the duplicates, then run this block again.';
end $$;

-- ---------- quick checks (run after) ----------
-- select * from public.allowed_users;                                   -- your e-mail is listed
-- select count(*) from public.invoices;                                 -- your data is still visible when signed in
-- select tbl, op, count(*) from public.audit_log group by 1,2;          -- fills up as you use the app

-- ---------- ROLLBACK (only if you are locked out; run in SQL Editor, which bypasses RLS) ----------
-- insert into public.allowed_users values ('your@email.com') on conflict do nothing;    -- usually all you need
-- or restore the old open policy (not recommended):
--   create policy "auth full access" on public.invoices for all to authenticated using (true) with check (true);   (repeat per table)
