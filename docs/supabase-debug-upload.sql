-- OpenVitals manual debug upload setup.
-- Dev-only: bundles can contain sensitive local health, BLE, packet, log, and database evidence.
-- Do not put a service-role key in the iOS app. Use the project URL plus anon key with these RLS policies.

create extension if not exists pgcrypto;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'openvitals-debug',
  'openvitals-debug',
  false,
  52428800,
  array['application/json']::text[]
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.openvitals_debug_uploads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  device_alias text not null,
  bucket text not null default 'openvitals-debug',
  storage_prefix text not null,
  bundle_path text not null,
  manifest_path text,
  bundle_file_name text not null,
  bundle_byte_count bigint not null,
  bundle_sha256 text not null,
  manifest_file_name text,
  manifest_byte_count bigint,
  manifest_sha256 text,
  validation_summary text,
  upload_status text not null default 'uploaded',
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists openvitals_debug_uploads_device_created_idx
  on public.openvitals_debug_uploads (device_alias, created_at desc);

create index if not exists openvitals_debug_uploads_metadata_gin_idx
  on public.openvitals_debug_uploads using gin (metadata);

alter table public.openvitals_debug_uploads enable row level security;

drop policy if exists "Dev insert OpenVitals debug upload rows" on public.openvitals_debug_uploads;
create policy "Dev insert OpenVitals debug upload rows"
  on public.openvitals_debug_uploads
  for insert
  to anon
  with check (
    bucket = 'openvitals-debug'
    and upload_status = 'uploaded'
    and storage_prefix <> ''
    and bundle_path like storage_prefix || '/%'
    and (manifest_path is null or manifest_path like storage_prefix || '/%')
    and bundle_file_name like 'open-vitals-local-data-%.openvitalsbundle.json'
    and bundle_byte_count > 0
    and bundle_sha256 ~ '^[0-9a-f]{64}$'
    and (manifest_sha256 is null or manifest_sha256 ~ '^[0-9a-f]{64}$')
  );

drop policy if exists "Dev read OpenVitals debug upload rows" on public.openvitals_debug_uploads;
create policy "Dev read OpenVitals debug upload rows"
  on public.openvitals_debug_uploads
  for select
  to anon
  using (true);

grant usage on schema public to anon;
grant select, insert on table public.openvitals_debug_uploads to anon;

drop policy if exists "Dev insert OpenVitals debug objects" on storage.objects;
create policy "Dev insert OpenVitals debug objects"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'openvitals-debug');

drop policy if exists "Dev read OpenVitals debug objects" on storage.objects;
create policy "Dev read OpenVitals debug objects"
  on storage.objects
  for select
  to anon
  using (bucket_id = 'openvitals-debug');
