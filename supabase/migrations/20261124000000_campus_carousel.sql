begin;

create table public.hero_slides (
  id uuid primary key default gen_random_uuid(),
  eyebrow text,
  title text not null,
  highlighted_title text,
  description text,
  image_url text not null,
  image_alt text,
  primary_cta_text text,
  primary_cta_link text,
  secondary_cta_text text,
  secondary_cta_link text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date date not null,
  event_type text,
  location text,
  image_url text,
  registration_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text,
  published_at timestamptz not null default now(),
  is_pinned boolean not null default false,
  is_active boolean not null default true,
  link text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.campus_highlights (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text,
  image_url text not null,
  image_alt text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index hero_slides_active_order_idx on public.hero_slides (is_active, display_order);
create index events_active_date_idx on public.events (is_active, event_date);
create index announcements_active_published_idx on public.announcements (is_active, published_at desc);
create index campus_highlights_active_order_idx on public.campus_highlights (is_active, display_order);

alter table public.hero_slides enable row level security;
alter table public.events enable row level security;
alter table public.announcements enable row level security;
alter table public.campus_highlights enable row level security;

create policy hero_slides_public_read on public.hero_slides for select to anon, authenticated using (is_active = true);
create policy events_public_read on public.events for select to anon, authenticated using (is_active = true);
create policy announcements_public_read on public.announcements for select to anon, authenticated using (is_active = true);
create policy campus_highlights_public_read on public.campus_highlights for select to anon, authenticated using (is_active = true);

create policy hero_slides_admin_manage on public.hero_slides for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy events_admin_manage on public.events for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy announcements_admin_manage on public.announcements for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');
create policy campus_highlights_admin_manage on public.campus_highlights for all to authenticated
  using (public.jwt_role() = 'admin') with check (public.jwt_role() = 'admin');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('university-assets', 'university-assets', true, 20971520, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy university_assets_public_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'university-assets');
create policy university_assets_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'university-assets' and public.jwt_role() = 'admin');
create policy university_assets_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'university-assets' and public.jwt_role() = 'admin')
  with check (bucket_id = 'university-assets' and public.jwt_role() = 'admin');
create policy university_assets_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'university-assets' and public.jwt_role() = 'admin');

commit;
