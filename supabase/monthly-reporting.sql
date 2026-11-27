-- NPYDF monthly programme reporting workflow
-- Run once in Supabase SQL Editor after the existing NPYDF schema migrations.
create table if not exists public.monthly_reports (
  id uuid primary key default gen_random_uuid(),
  programme text not null check (programme in ('Pride Pathways','Pride Lady','Pride Farms','Innovation Hub','Pride Works')),
  reporting_month date not null,
  report_data jsonb not null default '{}'::jsonb,
  submitted_by uuid not null references auth.users(id),
  status text not null default 'pending_secretary'
    check (status in ('pending_secretary','pending_ed','approved','returned','rejected')),
  secretary_note text,
  secretary_at timestamptz,
  ed_note text,
  ed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(programme, reporting_month, submitted_by)
);
alter table public.monthly_reports enable row level security;
drop policy if exists "monthly report submit own" on public.monthly_reports;
drop policy if exists "monthly report read own or reviewers" on public.monthly_reports;
drop policy if exists "monthly report secretary review" on public.monthly_reports;
drop policy if exists "monthly report ED decision" on public.monthly_reports;
create policy "monthly report submit own" on public.monthly_reports
 for insert to authenticated
 with check (submitted_by = auth.uid() and public.is_staff() and status = 'pending_secretary');
create policy "monthly report read own or reviewers" on public.monthly_reports
 for select to authenticated
 using (submitted_by = auth.uid() or public.has_any_role(array['executive_director','secretary']));
create policy "monthly report secretary review" on public.monthly_reports
 for update to authenticated
 using (public.has_any_role(array['secretary']) and status = 'pending_secretary')
 with check (public.has_any_role(array['secretary']) and status in ('pending_ed','returned'));
create policy "monthly report ED decision" on public.monthly_reports
 for update to authenticated
 using (public.has_any_role(array['executive_director']) and status = 'pending_ed')
 with check (public.has_any_role(array['executive_director']) and status in ('approved','returned','rejected'));
create index if not exists monthly_reports_status_month_idx
 on public.monthly_reports(status, reporting_month desc);
create index if not exists monthly_reports_submitter_idx
 on public.monthly_reports(submitted_by, reporting_month desc);
create or replace function public.set_monthly_report_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists monthly_reports_updated_at on public.monthly_reports;
create trigger monthly_reports_updated_at before update on public.monthly_reports
 for each row execute function public.set_monthly_report_updated_at();
