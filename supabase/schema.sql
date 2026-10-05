-- Run once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run.
-- Every signed-in user shares the same data (one firm, one ledger). Anonymous access is blocked.

create table if not exists clients  (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
create table if not exists pricing  (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
create table if not exists invoices (id text primary key, data jsonb not null, updated_at timestamptz not null default now());
create table if not exists meta     (id text primary key, data jsonb not null);

alter table clients  enable row level security;
alter table pricing  enable row level security;
alter table invoices enable row level security;
alter table meta     enable row level security;

create policy "auth full access" on clients  for all to authenticated using (true) with check (true);
create policy "auth full access" on pricing  for all to authenticated using (true) with check (true);
create policy "auth full access" on invoices for all to authenticated using (true) with check (true);
create policy "auth full access" on meta     for all to authenticated using (true) with check (true);

-- Private bucket for payment screenshots / PDFs
insert into storage.buckets (id, name, public) values ('proofs', 'proofs', false)
on conflict (id) do nothing;

create policy "auth read proofs"   on storage.objects for select to authenticated using (bucket_id = 'proofs');
create policy "auth insert proofs" on storage.objects for insert to authenticated with check (bucket_id = 'proofs');
create policy "auth update proofs" on storage.objects for update to authenticated using (bucket_id = 'proofs');
create policy "auth delete proofs" on storage.objects for delete to authenticated using (bucket_id = 'proofs');
