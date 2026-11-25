-- NPYDF Chipata secure administration foundation
-- Target: Supabase PostgreSQL. Apply in the Supabase SQL Editor.
-- IMPORTANT: Review the policies and test with separate accounts before production use.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('executive_director','secretary','treasurer','project_lead','staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  community text,
  interest text,
  status text not null default 'pending' check (status in ('pending','active','inactive','rejected')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  lead_name text,
  location text,
  status text not null default 'active',
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  project text not null,
  form_name text not null,
  submitted_by uuid not null references auth.users(id),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending_secretary'
    check (status in ('pending_secretary','pending_ed','approved_treasurer','completed','rejected')),
  secretary_note text,
  secretary_at timestamptz,
  ed_note text,
  ed_at timestamptz,
  treasurer_note text,
  treasurer_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.news_posts (
  id uuid primary key default gen_random_uuid(),
  headline text not null,
  slug text not null unique,
  summary text,
  body text not null,
  category text not null default 'Update',
  status text not null default 'draft' check (status in ('draft','published','archived')),
  published_at timestamptz,
  author_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.public_inquiries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  phone text,
  subject text not null,
  message text not null,
  status text not null default 'new' check (status in ('new','in_progress','closed')),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  table_name text not null,
  record_id text,
  created_at timestamptz not null default now()
);

create or replace function public.current_role()
returns text language sql stable security definer
set search_path = public
as $$
  select role from public.profiles
  where id = auth.uid() and active = true
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and active = true)
$$;

create or replace function public.has_any_role(allowed text[])
returns boolean language sql stable security definer
set search_path = public
as $$
  select coalesce(public.current_role() = any(allowed), false)
$$;

alter table public.profiles enable row level security;
alter table public.members enable row level security;
alter table public.projects enable row level security;
alter table public.submissions enable row level security;
alter table public.news_posts enable row level security;
alter table public.public_inquiries enable row level security;
alter table public.audit_log enable row level security;

-- Profiles: staff can view their own profile; ED manages staff profiles.
create policy "profile self read" on public.profiles for select
  using (id = auth.uid() or public.has_any_role(array['executive_director']));
create policy "ED manages profiles" on public.profiles for all
  using (public.has_any_role(array['executive_director']))
  with check (public.has_any_role(array['executive_director']));

-- Members: staff can read; ED and Secretary manage the register.
create policy "staff read members" on public.members for select using (public.is_staff());
create policy "secretary and ED manage members" on public.members for all
  using (public.has_any_role(array['executive_director','secretary']))
  with check (public.has_any_role(array['executive_director','secretary']));

-- Projects: staff read; ED and project leads maintain.
create policy "staff read projects" on public.projects for select using (public.is_staff());
create policy "ED and leads manage projects" on public.projects for all
  using (public.has_any_role(array['executive_director','project_lead']))
  with check (public.has_any_role(array['executive_director','project_lead']));

-- Submissions: submitter and authorised reviewers can read. Workflow stages are role-scoped.
create policy "submitter and reviewers read submissions" on public.submissions for select
  using (submitted_by = auth.uid() or public.is_staff());
create policy "staff create own submissions" on public.submissions for insert
  with check (submitted_by = auth.uid() and public.is_staff() and status = 'pending_secretary');
create policy "secretary checks submissions" on public.submissions for update
  using (public.has_any_role(array['secretary']) and status = 'pending_secretary')
  with check (public.has_any_role(array['secretary']) and status in ('pending_secretary','pending_ed'));
create policy "ED decides checked submissions" on public.submissions for update
  using (public.has_any_role(array['executive_director']) and status = 'pending_ed')
  with check (public.has_any_role(array['executive_director']) and status in ('approved_treasurer','rejected'));
create policy "treasurer completes approved submissions" on public.submissions for update
  using (public.has_any_role(array['treasurer']) and status = 'approved_treasurer')
  with check (public.has_any_role(array['treasurer']) and status in ('approved_treasurer','completed'));

-- Public website: only published stories are readable without login.
create policy "public reads published news" on public.news_posts for select
  using (status = 'published' or public.is_staff());
create policy "staff drafts news" on public.news_posts for insert
  with check (public.has_any_role(array['executive_director','secretary']));
create policy "ED and secretary update news" on public.news_posts for update
  using (public.has_any_role(array['executive_director','secretary']))
  with check (public.has_any_role(array['executive_director','secretary']));

-- Public contact form: anonymous visitors may submit an enquiry, not read records.
create policy "public submits enquiries" on public.public_inquiries for insert
  with check (length(trim(name)) between 2 and 120
    and length(trim(subject)) between 2 and 160
    and length(trim(message)) between 5 and 5000);
create policy "staff handles enquiries" on public.public_inquiries for select
  using (public.has_any_role(array['executive_director','secretary']));
create policy "staff updates enquiries" on public.public_inquiries for update
  using (public.has_any_role(array['executive_director','secretary']))
  with check (public.has_any_role(array['executive_director','secretary']));

create policy "ED reads audit log" on public.audit_log for select
  using (public.has_any_role(array['executive_director']));
create policy "staff writes audit log" on public.audit_log for insert
  with check (actor_id = auth.uid() and public.is_staff());

create index if not exists submissions_status_created_idx on public.submissions(status, created_at desc);
create index if not exists news_status_published_idx on public.news_posts(status, published_at desc);
create index if not exists members_status_idx on public.members(status);

-- Seed only the public programme list; no personal data.
insert into public.projects(name,lead_name,location,description) values
('Pride Pathways','Artness Banda','Chipata District','Skills development, vocational training and entrepreneurship.'),
('Pride Lady','Yvonne Mumba','Chipata District','Girls empowerment, mentorship, health and school support.'),
('Pride Farms','Victor Mwale','Kasenengwa, Madzimoyo and Msanga','Crop production, vegetables and poultry.'),
('Innovation Hub','Marcell Banda','Chipata Town','Digital skills, computer and phone repair, coding and content creation.'),
('Pride Works','Memory Lungu','Chipata District','Community clean-ups, environmental action and tree planting.')
on conflict (name) do nothing;
