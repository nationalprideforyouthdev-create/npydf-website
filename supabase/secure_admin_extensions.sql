-- NPYDF secure HRM and Finance extension
-- Run AFTER supabase/schema.sql in the Supabase SQL Editor.
-- Confidential HRM and financial data is protected by PostgreSQL RLS.

create table if not exists public.staff_records (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null,
  employee_id text unique,
  nrc text,
  phone text,
  position text,
  project text,
  salary_amount numeric(12,2),
  bank_or_mobile_money text,
  employment_status text not null default 'active'
    check (employment_status in ('active','volunteer','on_leave','exited')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.staff_contracts (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_records(id) on delete cascade,
  contract_type text not null,
  start_date date,
  end_date date,
  salary_amount numeric(12,2),
  duties text,
  status text not null default 'draft'
    check (status in ('draft','active','expired','terminated')),
  created_at timestamptz not null default now()
);

create table if not exists public.payslips (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_records(id) on delete cascade,
  pay_period text not null,
  basic_pay numeric(12,2) not null default 0,
  overtime numeric(12,2) not null default 0,
  allowances numeric(12,2) not null default 0,
  deductions numeric(12,2) not null default 0,
  net_pay numeric(12,2) generated always as
    (basic_pay + overtime + allowances - deductions) stored,
  paid_via text,
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','paid')),
  created_at timestamptz not null default now(),
  unique(staff_id, pay_period)
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_records(id) on delete cascade,
  leave_type text not null,
  start_date date not null,
  end_date date not null,
  cover_person text,
  reason text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.finance_entries (
  id uuid primary key default gen_random_uuid(),
  entry_type text not null check (entry_type in ('income','expense')),
  entry_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  receipt_number text,
  project text,
  description text not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.gallery_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text not null,
  status text not null default 'draft'
    check (status in ('draft','published','archived')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.document_register (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null,
  storage_path text not null,
  confidentiality text not null default 'internal'
    check (confidentiality in ('public','internal','confidential')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.staff_records enable row level security;
alter table public.staff_contracts enable row level security;
alter table public.payslips enable row level security;
alter table public.leave_requests enable row level security;
alter table public.finance_entries enable row level security;
alter table public.gallery_items enable row level security;
alter table public.document_register enable row level security;

-- Remove policies with these names first so this migration can be safely rerun.
drop policy if exists "ED manages staff records" on public.staff_records;
drop policy if exists "staff reads own staff record" on public.staff_records;
drop policy if exists "ED manages contracts" on public.staff_contracts;
drop policy if exists "ED manages payslips" on public.payslips;
drop policy if exists "staff reads own payslips" on public.payslips;
drop policy if exists "staff submits own leave" on public.leave_requests;
drop policy if exists "staff reads own leave" on public.leave_requests;
drop policy if exists "ED manages leave" on public.leave_requests;
drop policy if exists "ED and treasurer manage finance" on public.finance_entries;
drop policy if exists "public reads published gallery" on public.gallery_items;
drop policy if exists "staff manages gallery" on public.gallery_items;
drop policy if exists "ED and secretary manage document register" on public.document_register;

-- HRM: only the ED can read or change the full personnel register and contracts.
-- An authenticated staff member can read only their own basic-linked staff record.
create policy "ED manages staff records" on public.staff_records
  for all using (public.has_any_role(array['executive_director']))
  with check (public.has_any_role(array['executive_director']));
create policy "staff reads own staff record" on public.staff_records
  for select using (auth_user_id = auth.uid() and public.is_staff());

create policy "ED manages contracts" on public.staff_contracts
  for all using (public.has_any_role(array['executive_director']))
  with check (public.has_any_role(array['executive_director']));

create policy "ED manages payslips" on public.payslips
  for all using (public.has_any_role(array['executive_director']))
  with check (public.has_any_role(array['executive_director']));
create policy "staff reads own payslips" on public.payslips
  for select using (
    public.is_staff() and exists (
      select 1 from public.staff_records s
      where s.id = payslips.staff_id and s.auth_user_id = auth.uid()
    )
  );

-- Staff may submit and view only their own leave requests; only ED approves/rejects.
create policy "staff submits own leave" on public.leave_requests
  for insert with check (
    public.is_staff() and status = 'pending' and exists (
      select 1 from public.staff_records s
      where s.id = leave_requests.staff_id and s.auth_user_id = auth.uid()
    )
  );
create policy "staff reads own leave" on public.leave_requests
  for select using (
    public.is_staff() and exists (
      select 1 from public.staff_records s
      where s.id = leave_requests.staff_id and s.auth_user_id = auth.uid()
    )
  );
create policy "ED manages leave" on public.leave_requests
  for all using (public.has_any_role(array['executive_director']))
  with check (public.has_any_role(array['executive_director']));

-- Financial ledger: ED and Treasurer only.
create policy "ED and treasurer manage finance" on public.finance_entries
  for all using (public.has_any_role(array['executive_director','treasurer']))
  with check (public.has_any_role(array['executive_director','treasurer']));

-- Public visitors can see published gallery items; authorised staff manage records.
create policy "public reads published gallery" on public.gallery_items
  for select using (status = 'published' or public.is_staff());
create policy "staff manages gallery" on public.gallery_items
  for all using (public.has_any_role(array['executive_director','secretary']))
  with check (public.has_any_role(array['executive_director','secretary']));

-- Internal document metadata is visible only to ED and Secretary.
create policy "ED and secretary manage document register" on public.document_register
  for all using (public.has_any_role(array['executive_director','secretary']))
  with check (public.has_any_role(array['executive_director','secretary']));

create index if not exists staff_records_auth_user_idx on public.staff_records(auth_user_id);
create index if not exists payslips_staff_period_idx on public.payslips(staff_id, pay_period desc);
create index if not exists leave_requests_status_date_idx on public.leave_requests(status, start_date);
create index if not exists finance_entries_date_idx on public.finance_entries(entry_date desc);
