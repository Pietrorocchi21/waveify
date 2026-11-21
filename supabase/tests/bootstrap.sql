-- Disposable PostgreSQL test harness for Supabase contracts. Never production.
create role anon nologin;
create role authenticated nologin;
alter default privileges in schema public grant all on tables to anon, authenticated;
create schema auth;
create table auth.users(id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint);
create table storage.objects(id uuid default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant usage on schema auth, public, storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to authenticated;
