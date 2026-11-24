-- Presidency University Universal Portal — Stage 1
-- Run in the Supabase SQL Editor (or via supabase db push) as the project owner.
-- Auth role claims are read from app_metadata.role (student | faculty | admin).
-- For faculty notice authoring, also set app_metadata.school_id to the school's UUID.

begin;

create extension if not exists pgcrypto with schema extensions;

create type public.program_degree as enum ('UG', 'PG', 'PhD');
create type public.notice_category as enum ('Exam', 'Admission', 'Tender', 'IQAC');
create type public.application_status as enum ('Pending', 'Under Review', 'Accepted', 'Rejected');

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  dean text,
  heritage_tag text,
  description text,
  created_at timestamptz not null default now()
);

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  title text not null,
  degree public.program_degree not null,
  duration text not null,
  semester_fee numeric(12,2) not null check (semester_fee >= 0),
  seats integer not null default 0 check (seats >= 0),
  cutoff text,
  highlights text[] not null default '{}',
  syllabus_url text,
  created_at timestamptz not null default now(),
  unique (school_id, title, degree)
);

create table public.faculty (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  name text not null,
  designation text not null,
  email text not null unique,
  research_tags text[] not null default '{}',
  publications_count integer not null default 0 check (publications_count >= 0),
  cv_url text,
  created_at timestamptz not null default now()
);

create table public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category public.notice_category not null,
  is_urgent boolean not null default false,
  pdf_url text,
  published_at timestamptz not null default now(),
  -- Enables faculty to publish only notices for their assigned school.
  school_id uuid references public.schools(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.library_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  author text not null,
  isbn text,
  category text not null,
  total_copies integer not null default 0 check (total_copies >= 0),
  available_copies integer not null default 0 check (available_copies >= 0 and available_copies <= total_copies),
  digital_url text,
  created_at timestamptz not null default now()
);

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  tracking_code text not null unique,
  program_id uuid not null references public.programs(id) on delete restrict,
  applicant_name text not null check (length(trim(applicant_name)) between 2 and 160),
  email text not null check (length(email) <= 254),
  phone text not null check (length(phone) between 7 and 32),
  merit_score numeric(5,2) not null check (merit_score between 0 and 100),
  scholarship_tier text not null default 'None',
  transcript_url text,
  status public.application_status not null default 'Pending',
  created_at timestamptz not null default now()
);

create index programs_school_degree_idx on public.programs (school_id, degree);
create index faculty_school_name_idx on public.faculty (school_id, name);
create index notices_published_at_idx on public.notices (published_at desc);
create index notices_category_published_idx on public.notices (category, published_at desc);
create index notices_school_id_idx on public.notices (school_id);
create index library_items_title_idx on public.library_items using gin (to_tsvector('english', title || ' ' || author || ' ' || category));
create index applications_status_created_idx on public.applications (status, created_at desc);
create index applications_program_idx on public.applications (program_id);

-- Use the Supabase JWT's app_metadata, which users cannot edit themselves.
create or replace function public.jwt_role()
returns text language sql stable
set search_path = ''
as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') $$;

create or replace function public.jwt_school_id()
returns uuid language plpgsql stable
set search_path = ''
as $$
declare v text;
begin
  v := auth.jwt() -> 'app_metadata' ->> 'school_id';
  if v is null or v = '' then return null; end if;
  return v::uuid;
exception when invalid_text_representation then return null;
end;
$$;

alter table public.schools enable row level security;
alter table public.programs enable row level security;
alter table public.faculty enable row level security;
alter table public.notices enable row level security;
alter table public.library_items enable row level security;
alter table public.applications enable row level security;

-- Public discovery reads.
create policy schools_public_read on public.schools for select to anon, authenticated using (true);
create policy programs_public_read on public.programs for select to anon, authenticated using (true);
create policy faculty_public_read on public.faculty for select to anon, authenticated using (true);
create policy notices_public_read on public.notices for select to anon, authenticated using (true);
create policy library_public_read on public.library_items for select to anon, authenticated using (true);

-- Admin CMS writes.
create policy schools_admin_manage on public.schools for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy programs_admin_manage on public.programs for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy faculty_admin_manage on public.faculty for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy library_admin_manage on public.library_items for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy notices_admin_manage on public.notices for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');

-- Faculty may author and manage notices belonging to their assigned school.
create policy faculty_school_notice_insert on public.notices for insert to authenticated
  with check (
    public.jwt_role() = 'faculty'
    and school_id = public.jwt_school_id()
    and created_by = (select auth.uid())
  );
create policy faculty_school_notice_update on public.notices for update to authenticated
  using (public.jwt_role() = 'faculty' and school_id = public.jwt_school_id() and created_by = (select auth.uid()))
  with check (public.jwt_role() = 'faculty' and school_id = public.jwt_school_id() and created_by = (select auth.uid()));
create policy faculty_school_notice_delete on public.notices for delete to authenticated
  using (public.jwt_role() = 'faculty' and school_id = public.jwt_school_id() and created_by = (select auth.uid()));

-- Public can submit applications, but cannot read, change, or remove them.
create policy applications_public_submit on public.applications for insert to anon, authenticated
  with check (status = 'Pending');
create policy applications_admin_read on public.applications for select to authenticated
  using (public.jwt_role() = 'admin');
create policy applications_admin_update on public.applications for update to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy applications_admin_delete on public.applications for delete to authenticated
  using (public.jwt_role() = 'admin');

-- Storage buckets. Public assets are readable publicly, writes are admin-only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('public-circulars', 'public-circulars', true, 20971520, array['application/pdf']),
  ('application-docs', 'application-docs', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy circulars_public_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'public-circulars');
create policy circulars_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'public-circulars' and public.jwt_role() = 'admin');
create policy circulars_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'public-circulars' and public.jwt_role() = 'admin')
  with check (bucket_id = 'public-circulars' and public.jwt_role() = 'admin');
create policy circulars_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'public-circulars' and public.jwt_role() = 'admin');

-- Private transcripts: admins alone can list/read/download and manage files.
create policy application_docs_admin_read on storage.objects for select to authenticated
  using (bucket_id = 'application-docs' and public.jwt_role() = 'admin');
-- Anonymous uploads are required by the public application funnel. The private bucket
-- and lack of public SELECT keep uploaded files inaccessible; size/MIME limits are set above.
create policy application_docs_public_insert on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'application-docs');
create policy application_docs_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'application-docs' and public.jwt_role() = 'admin');
create policy application_docs_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'application-docs' and public.jwt_role() = 'admin')
  with check (bucket_id = 'application-docs' and public.jwt_role() = 'admin');
create policy application_docs_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'application-docs' and public.jwt_role() = 'admin');

-- Seed data: four schools with sample programs, faculty, notices, and library records.
insert into public.schools (id, code, name, dean, heritage_tag, description) values
('10000000-0000-4000-8000-000000000001','SET','School of Engineering & Technology','Dr. Ananya Rao','Future Ready','Engineering, computing, and applied technology programs grounded in research and practice.'),
('10000000-0000-4000-8000-000000000002','SHS','School of Arts, Humanities & Sciences','Dr. Meera Sen','Ideas That Shape Us','A broad foundation in the sciences, humanities, and creative disciplines.'),
('10000000-0000-4000-8000-000000000003','SMC','School of Management & Commerce','Dr. Vikram Nair','Lead With Purpose','Business education connecting analytical rigor, entrepreneurship, and ethical leadership.'),
('10000000-0000-4000-8000-000000000004','SLPG','School of Law & Public Governance','Dr. Farah Ahmed','Justice in Action','Legal education and public governance focused on justice, institutions, and civic life.')
on conflict (id) do update set code=excluded.code, name=excluded.name, dean=excluded.dean, heritage_tag=excluded.heritage_tag, description=excluded.description;

insert into public.programs (id, school_id, title, degree, duration, semester_fee, seats, cutoff, highlights, syllabus_url) values
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Computer Science & Engineering','UG','4 years',125000,180,'PU CET / JEE Main','{AI,Cloud Computing,Industry Internship}',null),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Electronics & Communication Engineering','UG','4 years',115000,120,'PU CET / JEE Main','{Embedded Systems,Semiconductor Design,IoT}',null),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','Computer Science','PG','2 years',140000,60,'Bachelor''s degree / PU CET','{Machine Learning,Research Project,Cloud}',null),
('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','Psychology','UG','3 years',85000,90,'Merit / PU CET','{Cognitive Science,Research Methods,Fieldwork}',null),
('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000002','English','PG','2 years',78000,45,'Bachelor''s degree / Merit','{Literary Studies,Academic Writing,Digital Humanities}',null),
('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000003','Business Administration','UG','3 years',105000,120,'PU CET / Merit','{Finance,Marketing,Entrepreneurship}',null),
('20000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000003','Master of Business Administration','PG','2 years',190000,90,'CAT / MAT / PU CET','{Leadership,Consulting,Live Capstone}',null),
('20000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000004','Law','UG','5 years',135000,60,'PU Law Admission Test','{Moot Court,Constitutional Law,Legal Aid Clinic}',null),
('20000000-0000-4000-8000-000000000009','10000000-0000-4000-8000-000000000004','Public Policy','PG','2 years',110000,40,'Bachelor''s degree / Interview','{Policy Analysis,Governance,Field Practicum}',null)
on conflict (id) do update set school_id=excluded.school_id, title=excluded.title, degree=excluded.degree, duration=excluded.duration, semester_fee=excluded.semester_fee, seats=excluded.seats, cutoff=excluded.cutoff, highlights=excluded.highlights;

insert into public.faculty (id, school_id, name, designation, email, research_tags, publications_count, cv_url) values
('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Dr. Kavya Iyer','Professor & Dean','kavya.iyer@example.edu','{Artificial Intelligence,Responsible Computing}',42,null),
('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Dr. Arjun Mukherjee','Associate Professor','arjun.mukherjee@example.edu','{Cognitive Psychology,Learning Sciences}',28,null),
('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','Dr. Nisha Menon','Professor','nisha.menon@example.edu','{Strategy,Social Entrepreneurship}',35,null),
('30000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004','Dr. Zoya Rahman','Associate Professor','zoya.rahman@example.edu','{Constitutional Law,Access to Justice}',22,null)
on conflict (id) do update set school_id=excluded.school_id, name=excluded.name, designation=excluded.designation, email=excluded.email, research_tags=excluded.research_tags, publications_count=excluded.publications_count;

insert into public.notices (id, title, category, is_urgent, published_at, school_id) values
('40000000-0000-4000-8000-000000000001','Semester examination timetable published','Exam',true,now() - interval '1 day',null),
('40000000-0000-4000-8000-000000000002','Applications open for the upcoming academic year','Admission',true,now() - interval '3 days',null),
('40000000-0000-4000-8000-000000000003','Request for proposals: campus library resources','Tender',false,now() - interval '6 days',null),
('40000000-0000-4000-8000-000000000004','IQAC: annual quality assurance report available','IQAC',false,now() - interval '10 days',null)
on conflict (id) do update set title=excluded.title, category=excluded.category, is_urgent=excluded.is_urgent, published_at=excluded.published_at;

insert into public.library_items (id, title, author, isbn, category, total_copies, available_copies, digital_url) values
('50000000-0000-4000-8000-000000000001','Introduction to Algorithms','Thomas H. Cormen et al.','9780262046305','Computer Science',18,7,null),
('50000000-0000-4000-8000-000000000002','Research Methods in Psychology','Beth Morling',null,'Psychology',12,4,null),
('50000000-0000-4000-8000-000000000003','Principles of Marketing','Philip Kotler and Gary Armstrong','9780134492513','Business',15,6,null),
('50000000-0000-4000-8000-000000000004','The Constitution of India','B. R. Ambedkar (ed.)',null,'Law',20,9,null),
('50000000-0000-4000-8000-000000000005','The Oxford Handbook of Public Policy','Michael Moran, Martin Rein, Robert E. Goodin',null,'Public Policy',8,2,null)
on conflict (id) do update set title=excluded.title, author=excluded.author, isbn=excluded.isbn, category=excluded.category, total_copies=excluded.total_copies, available_copies=excluded.available_copies;

commit;

-- After running this script:
-- 1) Assign role and (for faculty) school_id in each user's app_metadata using a trusted admin path.
-- 2) Configure frontend to use the anon key only; never expose the service_role key.
-- 3) The public application insert policy intentionally does not grant SELECT. The client can
--    generate a tracking_code before insert and show it immediately; do not select the inserted row.
-- 4) application-docs accepts anonymous uploads for the admissions funnel, but only admins can
--    read/list/download files. Restrict public upload rates further at the application/API layer.
