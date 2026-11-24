# Presidency University Universal Portal

Responsive React portal for university discovery, admissions, notices, faculty, library resources, student services and administration.

## Run locally

1. Install Node.js 20 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
4. Apply `supabase/migrations/20261120000000_initial.sql` to the Supabase project using the SQL Editor or Supabase CLI.
5. Run `npm run dev` and open the local URL Vite prints.

Without Supabase credentials, public screens use bundled sample data. Sign-in, application persistence, uploads and CMS writes require a configured project.

## Supabase setup notes

- Set a user's `app_metadata.role` to `student`, `faculty` or `admin`. Set `app_metadata.school_id` for faculty to the corresponding school's UUID. These claims must be written by a trusted server/admin path, never by the client.
- The SQL migration creates `public-circulars` and private `application-docs`. It includes a public insert policy on `application-docs` for the admissions upload flow; only admins can read those objects. Apply upload rate limits at the edge/API layer before production.
- The browser uses only the Supabase anon key. Never put the service role key in frontend environment variables.
- Public application submission intentionally has no public SELECT policy. The form displays its generated tracking ID immediately. A secure status lookup endpoint is needed if applicants later need to check status themselves.
- Sample records are illustrative and should be reviewed/replaced with approved institutional data before launch.

## Deployment

Build with `npm run build`; publish the generated `dist/` folder to Vercel, Netlify, or another static host. Configure the two `VITE_SUPABASE_*` environment variables in the host. Configure SPA fallback/rewrite to `/index.html` so direct navigation to portal routes works.

## Current scope

The student dashboard currently displays sample semester course, attendance, GPA and schedule data because the supplied six-table schema does not include enrollment, attendance or receipt tables. The faculty profile screen uses the supplied faculty table; faculty-side SIMS course rosters and notice publishing need course/enrollment data and a faculty publishing screen. Public circular download links and CV/syllabus URLs become active when populated in Supabase. Production deployment and live Supabase migration application require project credentials and access.
