-- NPYDF operational records: finance, HRM, memberships, leave and form register.
-- Apply after schema.sql in the Supabase SQL Editor. Uses authenticated profiles + RLS.
create extension if not exists pgcrypto;

create or replace function public.can_manage_hrm()
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_any_role(array['executive_director','secretary','treasurer'])
$$;
create or replace function public.can_manage_finance()
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_any_role(array['executive_director','secretary','treasurer'])
$$;

create table if not exists public.staff_records (
 id uuid primary key default gen_random_uuid(),
 full_name text not null unique,
 employee_id text unique,
 nrc text,
 phone text,
 ward text,
 position text,
 project text,
 monthly_salary numeric(12,2) not null default 0 check(monthly_salary>=0),
 payment_method text,
 status text not null default 'Active' check(status in ('Active','On Leave','Inactive')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.employment_contracts (
 id uuid primary key default gen_random_uuid(),
 staff_id uuid not null references public.staff_records(id) on delete cascade,
 contract_ref text unique,
 contract_type text not null,
 start_date date,
 end_date date,
 salary numeric(12,2) not null default 0 check(salary>=0),
 duties text,
 status text not null default 'Pending',
 created_at timestamptz not null default now()
);
create table if not exists public.payslips (
 id uuid primary key default gen_random_uuid(),
 staff_id uuid not null references public.staff_records(id) on delete restrict,
 payroll_month date not null,
 basic numeric(12,2) not null default 0,
 overtime numeric(12,2) not null default 0,
 transport numeric(12,2) not null default 0,
 bonus numeric(12,2) not null default 0,
 napsa numeric(12,2) not null default 0,
 paye numeric(12,2) not null default 0,
 other_deductions numeric(12,2) not null default 0,
 deductions numeric(12,2) not null default 0,
 net_pay numeric(12,2) generated always as (basic+overtime+transport+bonus-deductions) stored,
 paid_via text,
 receipt_no text,
 paid boolean not null default false,
 paid_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 unique(staff_id,payroll_month)
);
create table if not exists public.leave_requests (
 id uuid primary key default gen_random_uuid(),
 staff_id uuid not null references public.staff_records(id) on delete cascade,
 leave_type text not null,
 date_from date not null,
 date_to date not null,
 cover_person text,
 reason text,
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected')),
 reviewed_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(date_to>=date_from)
);
create table if not exists public.finance_entries (
 id uuid primary key default gen_random_uuid(),
 entry_type text not null check(entry_type in ('Income','Expense')),
 amount numeric(12,2) not null check(amount>0),
 entry_date date not null,
 receipt_no text,
 category text not null,
 project text,
 description text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create table if not exists public.membership_applications (
 id uuid primary key default gen_random_uuid(),
 full_name text not null,
 phone text not null,
 nrc text,
 ward text not null,
 project text,
 reason text,
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected')),
 created_at timestamptz not null default now()
);
create table if not exists public.partner_requests (
 id uuid primary key default gen_random_uuid(),
 organisation_name text not null,
 partner_type text not null,
 contact_name text,
 phone text,
 email text,
 details text not null,
 status text not null default 'New',
 created_at timestamptz not null default now()
);
create table if not exists public.donation_pledges (
 id uuid primary key default gen_random_uuid(),
 donor_name text,
 contact text,
 amount numeric(12,2) not null check(amount>0),
 project text,
 status text not null default 'Pledged',
 created_at timestamptz not null default now()
);
create table if not exists public.form_catalog (
 id uuid primary key default gen_random_uuid(),
 form_number integer not null unique check(form_number between 1 and 55),
 group_name text not null,
 form_name text not null,
 active boolean not null default true
);

alter table public.staff_records enable row level security;
alter table public.employment_contracts enable row level security;
alter table public.payslips enable row level security;
alter table public.leave_requests enable row level security;
alter table public.finance_entries enable row level security;
alter table public.membership_applications enable row level security;
alter table public.partner_requests enable row level security;
alter table public.donation_pledges enable row level security;
alter table public.form_catalog enable row level security;

drop policy if exists "HRM authorised staff access" on public.staff_records;
create policy "HRM authorised staff access" on public.staff_records for all using(public.can_manage_hrm()) with check(public.can_manage_hrm());
drop policy if exists "HRM contracts access" on public.employment_contracts;
create policy "HRM contracts access" on public.employment_contracts for all using(public.can_manage_hrm()) with check(public.can_manage_hrm());
drop policy if exists "HRM payslips access" on public.payslips;
create policy "HRM payslips access" on public.payslips for all using(public.can_manage_hrm()) with check(public.can_manage_hrm());
drop policy if exists "HRM leave access" on public.leave_requests;
create policy "HRM leave access" on public.leave_requests for all using(public.can_manage_hrm()) with check(public.can_manage_hrm());
drop policy if exists "Finance authorised access" on public.finance_entries;
create policy "Finance authorised access" on public.finance_entries for all using(public.can_manage_finance()) with check(public.can_manage_finance());

drop policy if exists "Public submits membership" on public.membership_applications;
create policy "Public submits membership" on public.membership_applications for insert with check(length(trim(full_name)) between 2 and 120 and length(trim(phone)) between 5 and 40);
create policy "Staff reviews membership" on public.membership_applications for select using(public.is_staff());
create policy "ED and Secretary review membership" on public.membership_applications for update using(public.has_any_role(array['executive_director','secretary'])) with check(public.has_any_role(array['executive_director','secretary']));

drop policy if exists "Public submits partner requests" on public.partner_requests;
create policy "Public submits partner requests" on public.partner_requests for insert with check(length(trim(organisation_name)) between 2 and 180 and length(trim(details)) between 5 and 5000);
create policy "Staff reads partner requests" on public.partner_requests for select using(public.has_any_role(array['executive_director','secretary']));
create policy "Staff updates partner requests" on public.partner_requests for update using(public.has_any_role(array['executive_director','secretary'])) with check(public.has_any_role(array['executive_director','secretary']));

drop policy if exists "Public submits donation pledges" on public.donation_pledges;
create policy "Public submits donation pledges" on public.donation_pledges for insert with check(amount>0);
create policy "Finance reads pledges" on public.donation_pledges for select using(public.can_manage_finance());
create policy "Finance updates pledges" on public.donation_pledges for update using(public.can_manage_finance()) with check(public.can_manage_finance());

create policy "Staff reads form catalog" on public.form_catalog for select using(public.is_staff());
create policy "ED manages form catalog" on public.form_catalog for all using(public.has_any_role(array['executive_director'])) with check(public.has_any_role(array['executive_director']));

create index if not exists payslips_month_idx on public.payslips(payroll_month desc);
create index if not exists finance_entries_date_idx on public.finance_entries(entry_date desc);
create index if not exists contracts_end_date_idx on public.employment_contracts(end_date);
create index if not exists leave_requests_status_idx on public.leave_requests(status,created_at desc);

insert into public.form_catalog(form_number,group_name,form_name) values
(1,'Pride Pathways','Youth Registration'),(2,'Pride Pathways','Skills Assessment'),(3,'Pride Pathways','Training Attendance'),(4,'Pride Pathways','Training Materials Request'),(5,'Pride Pathways','Mentor Assignment'),(6,'Pride Pathways','Progress Review'),(7,'Pride Pathways','Graduation Record'),
(8,'Pride Lady','School Registration'),(9,'Pride Lady','Girls Talk Attendance'),(10,'Pride Lady','Mentorship Consent'),(11,'Pride Lady','Wellbeing Referral'),(12,'Pride Lady','School Progress'),(13,'Pride Lady','Ambassador Nomination'),(14,'Pride Lady','Programme Review'),
(15,'Pride Farms','Farmer Registration'),(16,'Pride Farms','Land and Crop Assessment'),(17,'Pride Farms','Seed Request'),(18,'Pride Farms','Input Distribution'),(19,'Pride Farms','Field Visit'),(20,'Pride Farms','Harvest Record'),(21,'Pride Farms','Sales Record'),(22,'Pride Farms','Poultry Record'),
(23,'Innovation Hub','Participant Registration'),(24,'Innovation Hub','Digital Skills Assessment'),(25,'Innovation Hub','Computer Use Register'),(26,'Innovation Hub','Phone Repair Intake'),(27,'Innovation Hub','Equipment Request'),(28,'Innovation Hub','Training Attendance'),(29,'Innovation Hub','Skills Completion'),
(30,'Pride Works','Community Clean-Up Plan'),(31,'Pride Works','Volunteer Register'),(32,'Pride Works','Clean-Up Attendance'),(33,'Pride Works','Waste Collection Record'),(34,'Pride Works','Tree Planting Register'),(35,'Pride Works','Environmental Activity Report'),
(36,'Finance','Payment Request'),(37,'Finance','Expense Claim'),(38,'Finance','Income Receipt'),(39,'Finance','Monthly Reconciliation'),
(40,'Secretary','Meeting Minutes'),(41,'Secretary','Correspondence Register'),(42,'Secretary','Membership Register Update'),(43,'Secretary','Resolution Record'),
(44,'ED','Approval Request'),(45,'ED','Executive Decision'),(46,'ED','Project Review'),
(47,'HRM','Staff Information Form'),(48,'HRM','Employment Contract'),(49,'HRM','Monthly Payslip'),(50,'HRM','Leave Request'),(51,'HRM','Performance Review'),(52,'HRM','Staff Attendance'),(53,'HRM','Disciplinary Record'),(54,'HRM','Staff Exit Checklist'),(55,'HRM','Training and Development')
on conflict(form_number) do update set group_name=excluded.group_name,form_name=excluded.form_name;


-- Seed staff from the October 2026 payroll and signed contract schedule.
-- Lidya Nkhoma (NPYDF-010) is replaced by Elias Phiri as instructed.
-- Memory Lungu and Executive 9/10 are included as staff placeholders; no salary is assumed.
insert into public.staff_records(full_name,employee_id,position,project,monthly_salary,status) values
('Francis Banda','NPYDF-001','Executive Director / Chair','Organisation',4000,'Active'),
('Ishmael Banda','NPYDF-002','Operations / Vice Chair','Organisation',2800,'Active'),
('Artness Banda','NPYDF-003','Programmes / Secretary General','Organisation',2500,'Active'),
('Yvonne Mumba','NPYDF-004','HR / Vice Secretary','Organisation',2800,'Active'),
('Annie Mwanza','NPYDF-005','Finance / Treasurer','Finance',2500,'Active'),
('Victor Mwale','NPYDF-006','Stores / Vice Treasurer','Pride Farms',2000,'Active'),
('Marcel Banda','NPYDF-007','Fundraising / Publicity','Organisation',2800,'Active'),
('Esmelly Mwanza','NPYDF-008','Programmes Assistant / Vice Publicity','Organisation',1500,'Active'),
('Jessy Nyirongo','NPYDF-009','Project Manager / Coordinator','Organisation',3000,'Active'),
('Elias Phiri','NPYDF-010','Youth Co-ordinator – Eastern','Eastern Province Coordination',1000,'Active'),
('Memory Lungu',null,'Pride Works Lead','Pride Works',0,'Active'),
('Executive 9',null,'Executive','Organisation',0,'Active'),
('Executive 10',null,'Executive','Organisation',0,'Active')
on conflict(full_name) do update set employee_id=excluded.employee_id,position=excluded.position,project=excluded.project,monthly_salary=excluded.monthly_salary,status=excluded.status;

-- Import the October 2026 payslips from the supplied payroll schedule.
-- All are marked Unpaid because the report does not confirm settlement.
insert into public.payslips(staff_id,payroll_month,basic,overtime,transport,bonus,napsa,paye,other_deductions,deductions,paid)
select s.id,date '2026-10-01',v.basic,0,0,0,v.napsa,0,0,v.napsa,false
from (values
 ('NPYDF-001',4000::numeric,200::numeric),
 ('NPYDF-002',2800,140),
 ('NPYDF-003',2500,125),
 ('NPYDF-004',2800,140),
 ('NPYDF-005',2500,125),
 ('NPYDF-006',2000,100),
 ('NPYDF-007',2800,140),
 ('NPYDF-008',1500,75),
 ('NPYDF-009',3000,150),
 ('NPYDF-010',1000,50)
) as v(employee_id,basic,napsa)
join public.staff_records s on s.employee_id=v.employee_id
on conflict(staff_id,payroll_month) do nothing;

-- Contract references are imported; dates remain blank because the signed start/end dates
-- are not specified in the supplied contracts. HR must enter confirmed dates.
insert into public.employment_contracts(contract_ref,staff_id,contract_type,start_date,end_date,salary,duties,status)
select v.contract_ref,s.id,'Employment',null,null,v.salary,v.duties,'Active - dates to confirm'
from (values
 ('NPYDF-001/HR/2026','NPYDF-001',4000::numeric,'Executive Director / Chair'),
 ('NPYDF-002/HR/2026','NPYDF-002',2800,'Operations / Vice Chair'),
 ('NPYDF-003/HR/2026','NPYDF-003',2500,'Programmes / Secretary General'),
 ('NPYDF-004/HR/2026','NPYDF-004',2800,'HR / Vice Secretary'),
 ('NPYDF-005/HR/2026','NPYDF-005',2500,'Finance / Treasurer'),
 ('NPYDF-006/HR/2026','NPYDF-006',2000,'Stores / Vice Treasurer'),
 ('NPYDF-007/HR/2026','NPYDF-007',2800,'Fundraising / Publicity'),
 ('NPYDF-008/HR/2026','NPYDF-008',1500,'Programmes Assistant / Vice Publicity'),
 ('NPYDF-009/HR/2026','NPYDF-009',3000,'Project Manager / Coordinator'),
 ('NPYDF-010/HR/2026','NPYDF-010',1000,'Youth Co-ordinator – Eastern')
) as v(contract_ref,employee_id,salary,duties)
join public.staff_records s on s.employee_id=v.employee_id
on conflict(contract_ref) do update set staff_id=excluded.staff_id,salary=excluded.salary,duties=excluded.duties,status=excluded.status;

-- Limit the shared approval queue to its submitter and designated reviewers.
drop policy if exists "submitter and reviewers read submissions" on public.submissions;
create policy "submitter and reviewers read submissions" on public.submissions for select
 using (submitted_by = auth.uid()
   or public.has_any_role(array['executive_director','secretary','treasurer']));
