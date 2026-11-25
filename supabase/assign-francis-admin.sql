-- NPYDF: assign the first Executive Director profile.
-- Run in Supabase SQL Editor after creating and confirming Francis Banda's Auth user.
-- Verify the UUID belongs to Francis before running this statement.

begin;

insert into public.profiles (id, full_name, role, active)
values (
  '88fcff6e-845f-484d-9485-5aa87da5786d'::uuid,
  'Francis Banda',
  'executive_director',
  true
)
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    active = true;

commit;

-- Verify the profile:
select id, full_name, role, active
from public.profiles
where id = '88fcff6e-845f-484d-9485-5aa87da5786d'::uuid;
