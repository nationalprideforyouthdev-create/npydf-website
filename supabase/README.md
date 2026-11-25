# NPYDF secure administration backend

This folder prepares the NPYDF website for a shared, server-backed administration system using Supabase (Postgres + Auth). The current GitHub Pages admin portal remains a local-only demonstration until the backend is configured and the front end is migrated.

## What is included
- `schema.sql`: starter database, role profiles, member/project registers, approval queue, news publishing, public enquiries, and row-level security (RLS).
- Roles: Executive Director, Secretary, Treasurer, Project Lead, Staff.
- Approval stages: staff submission → Secretary check → ED decision → Treasurer completion.
- Public news policy exposes only published posts.
- Public enquiry policy allows inserts but does not allow anonymous reads.

## Setup checklist
1. Create a Supabase project in an organisation-owned account. Enable MFA for administrators.
2. Open SQL Editor and run `schema.sql`.
3. In Authentication, create named staff accounts individually. Do not reuse the old demo password.
4. Add each staff user's UUID to `public.profiles` with their full name and approved role. Only the ED should be allowed to manage role assignments.
5. Test every role using separate test accounts before adding real data.
6. Configure the front end with the Supabase project URL and the publishable/anon key only. Never place a service-role key, database password, or secret key in GitHub Pages or browser JavaScript.
7. Migrate the admin portal to Supabase Auth and database calls; remove the old hard-coded USERS object and localStorage data path before real use.
8. Configure backups, retention, access review, MFA, and a safeguarding/HR data handling policy.

## Important limitations / production review
- This is a foundation, not a completed production deployment. No Supabase project has been created or connected from this repository.
- RLS is enabled, but workflow transitions should be moved into validated database functions or server-side Edge Functions before production. In particular, restrict which columns each role can update; the starter update policies are role-scoped but not column-scoped.
- Sensitive safeguarding, NRC, payroll, banking, medical, or disciplinary records must not be entered until the system has been security-reviewed and tested.
- Do not create public sign-up with elevated roles. Create staff accounts through an administrator-controlled invitation process.
- The public contact insert policy is a starter policy; add rate limiting, spam protection, and CAPTCHA/Edge Function validation before production.
- Never commit private keys or credentials. Supabase publishable keys are intended for browser use only when RLS is correctly configured.

## Website
Public website: https://nationalprideforyouthdev-create.github.io/npydf-website/
Admin demo: https://nationalprideforyouthdev-create.github.io/npydf-website/admin.html
