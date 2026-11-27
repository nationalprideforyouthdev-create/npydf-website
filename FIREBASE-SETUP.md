# NPYDF Admin Portal — Firebase setup
This replacement does not use Supabase. GitHub Pages hosts the admin interface; Firebase Authentication and Cloud Firestore provide staff identity and data.

## Configure Firebase
1. Visit https://console.firebase.google.com/ and create a project named **NPYDF Admin**.
2. Add a Web app named **NPYDF Staff Portal** and copy its web configuration into `firebase-config.js`. These browser config values identify the project; never put service-account credentials in the repository.
3. Authentication → Sign-in method → enable **Email/Password**.
4. Firestore Database → create a database in production mode.
5. Publish the contents of `firestore.rules` in Firestore → Rules. Do not use open/test rules.

## Create the first Executive Director account
1. In Authentication → Users, add an individual work email and a strong unique password.
2. Copy the Firebase Auth UID.
3. In Firestore Data, create collection `profiles`; create a document whose ID is exactly that UID.
4. Add `full_name` (string), `role` (string: `executive_director`) and `active` (boolean: `true`).
5. Add staff accounts the same way with roles `secretary`, `treasurer`, `project_lead` or `staff`.

Only trusted Firebase Console administrators should provision accounts and profile roles. Do not use employee IDs as passwords or put service-account keys in browser code.

## Publish
Enable GitHub Pages in repository Settings → Pages → Deploy from branch → `main` / root. Intended portal URL: https://nationalprideforyouthdev-create.github.io/npydf-website/admin.html

## Release scope
This initial release includes staff email/password authentication, active-profile checks, role-gated navigation, dashboard counts, record listing and basic creation for applications, monthly reports and programme activities. Application decisions, full report approval routing, payroll calculations, file uploads, detailed audit logs and automated backups are not implemented yet. Test Firestore Rules in Rules Playground before entering sensitive personal, safeguarding, payroll or financial records.