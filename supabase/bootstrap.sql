begin;
set local standard_conforming_strings = on;
select pg_advisory_xact_lock(hashtext('waveify_migrations'));
create schema if not exists waveify_admin;
revoke all on schema waveify_admin from public, anon, authenticated;
create table if not exists waveify_admin.migrations (version text primary key, checksum text not null, applied_at timestamptz not null default now());
do $apply$
        declare previous text;
        begin
          select checksum into previous from waveify_admin.migrations where version = '0004_waveify_library.sql';
          if previous is null then
            execute $body_f94495e810f4b014$-- Account library snapshots use independent tables, avoiding legacy schema assumptions.
create table if not exists public.waveify_libraries (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.waveify_libraries enable row level security;
create policy waveify_library_owner on public.waveify_libraries
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
grant select, insert, update, delete on public.waveify_libraries to authenticated;

-- NULL denotes a stale revision. No lost updates, including concurrent first writes.
create or replace function public.waveify_save_library(expected_revision bigint, library_data jsonb)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare saved_revision bigint;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if expected_revision = 0 then
    insert into public.waveify_libraries(owner_id, revision, data)
      values(auth.uid(), 1, library_data)
      on conflict (owner_id) do nothing returning revision into saved_revision;
  else
    update public.waveify_libraries set data = library_data,
      revision = revision + 1, updated_at = now()
      where owner_id = auth.uid() and revision = expected_revision
      returning revision into saved_revision;
  end if;
  return saved_revision;
end;
$$;
revoke all on function public.waveify_save_library(bigint, jsonb) from public;
grant execute on function public.waveify_save_library(bigint, jsonb) to authenticated;

insert into storage.buckets(id, name, public) values ('waveify_media', 'waveify_media', false)
  on conflict (id) do nothing;
create policy waveify_media_read on storage.objects for select to authenticated
  using (bucket_id = 'waveify_media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy waveify_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'waveify_media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy waveify_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'waveify_media' and (storage.foldername(name))[1] = (select auth.uid())::text);

create table public.waveify_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  data jsonb not null,
  is_public boolean not null default false
);
alter table public.waveify_profiles enable row level security;
create policy waveify_profiles_read on public.waveify_profiles for select to authenticated
  using (id = (select auth.uid()) or is_public);
create policy waveify_profiles_write on public.waveify_profiles for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
grant select, insert, update, delete on public.waveify_profiles to authenticated;

create table public.waveify_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references public.waveify_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
alter table public.waveify_follows enable row level security;
create policy waveify_follows_read on public.waveify_follows for select to authenticated
  using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()) or
    exists (select 1 from public.waveify_profiles p where p.id = followed_id and p.is_public));
create policy waveify_follows_insert on public.waveify_follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and exists (
    select 1 from public.waveify_profiles p where p.id = followed_id and p.is_public));
create policy waveify_follows_delete on public.waveify_follows for delete to authenticated
  using (follower_id = (select auth.uid()));
grant select, insert, delete on public.waveify_follows to authenticated;

-- Recursively remove transport locations and local-only metadata from shared documents.
create function public.waveify_public_document(value jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare result jsonb; item record;
begin
  if jsonb_typeof(value) = 'object' then
    result := '{}'::jsonb;
    for item in select key, val from jsonb_each(value) as e(key,val) loop
      if item.key not in ('sourceUrl', 'sourceUri', 'streamUrl', 'audioUrl', 'localLyrics', 'email', 'filePath', 'localPath') then
        result := result || jsonb_build_object(item.key, public.waveify_public_document(item.val));
      end if;
    end loop;
    return result;
  elsif jsonb_typeof(value) = 'array' then
    return coalesce((select jsonb_agg(public.waveify_public_document(e)) from jsonb_array_elements(value) e), '[]'::jsonb);
  elsif jsonb_typeof(value) = 'string' and
    (value #>> '{}') ~ '^(file:|storage:|blob:|data:|/|[A-Za-z]:[\\/])' then
    return 'null'::jsonb;
  end if;
  return value;
end;
$$;


-- Update the public projection in the same transaction as library persistence.
create function public.waveify_project_profile() returns trigger language plpgsql
security invoker set search_path = '' as $$
begin
  insert into public.waveify_profiles(id, username, data, is_public)
    values(new.owner_id, nullif(new.data->'user'->>'username', ''),
      public.waveify_public_document(new.data->'user'), coalesce((new.data->'user'->>'isPublic')::boolean, false))
    on conflict (id) do update set username = excluded.username,
      data = excluded.data, is_public = excluded.is_public;
  return new;
end;
$$;
create trigger waveify_profile_projection after insert or update on public.waveify_libraries
  for each row execute function public.waveify_project_profile();

create table public.waveify_public_playlists (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null
);
create table public.waveify_public_history (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null
);
alter table public.waveify_public_playlists enable row level security;
alter table public.waveify_public_history enable row level security;
create policy waveify_shared_playlists_read on public.waveify_public_playlists for select to authenticated
  using (exists(select 1 from public.waveify_profiles p where p.id = owner_id and p.is_public));
create policy waveify_shared_history_read on public.waveify_public_history for select to authenticated
  using (exists(select 1 from public.waveify_profiles p where p.id = owner_id and p.is_public
    and coalesce((p.data->>'showHistory')::boolean, true)));
create policy waveify_shared_playlists_write on public.waveify_public_playlists for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy waveify_shared_history_write on public.waveify_public_history for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
grant select, insert, update, delete on public.waveify_public_playlists, public.waveify_public_history to authenticated;

create function public.waveify_project_sharing() returns trigger language plpgsql
security invoker set search_path = '' as $$
declare item record;
begin
  delete from public.waveify_public_playlists where owner_id = new.owner_id;
  delete from public.waveify_public_history where owner_id = new.owner_id;
  if coalesce((new.data->'user'->>'isPublic')::boolean, false) then
    for item in select key, value from jsonb_each(coalesce(new.data->'playlists', '{}'::jsonb)) loop
      if coalesce((item.value->'playlist'->>'isPublic')::boolean, false) then
        insert into public.waveify_public_playlists(id, owner_id, data)
          values(item.key, new.owner_id, public.waveify_public_document(item.value));
      end if;
    end loop;
    if coalesce((new.data->'user'->>'showHistory')::boolean, true) then
      insert into public.waveify_public_history(owner_id, data)
        values(new.owner_id, public.waveify_public_document(coalesce(new.data->'history', '[]'::jsonb)));
    end if;
  end if;
  return new;
end;
$$;
create trigger waveify_sharing_projection after insert or update on public.waveify_libraries
  for each row execute function public.waveify_project_sharing();

-- Only aggregate real submitted history for public profiles explicitly participating.
-- Raw private library snapshots never leave this narrowly scoped function.
create function public.waveify_leaderboard(artist_id text default null,
  selected_period text default 'weekly', result_limit integer default 20)
returns jsonb language sql stable security definer set search_path = '' as $$
  with eligible as (
    select p.data as profile, h.event
    from public.waveify_libraries l join public.waveify_profiles p on p.id = l.owner_id
    cross join lateral jsonb_array_elements(coalesce(l.data->'history', '[]'::jsonb)) h(event)
    where auth.uid() is not null and p.is_public
      and coalesce((p.data->>'participateLeaderboards')::boolean, false)
      and (selected_period = 'all_time' or (h.event->>'listenedAt')::timestamptz >=
        now() - case selected_period when 'daily' then interval '1 day'
          when 'monthly' then interval '30 days' else interval '7 days' end)
      and (artist_id is null or exists(select 1
        from jsonb_array_elements(coalesce(h.event->'track'->'artists', '[]'::jsonb)) a
        where a->>'id' = artist_id))
  ), totals as (
    select profile, count(*) as plays,
      sum(greatest(0, least(coalesce((event->>'playedDurationMs')::bigint, 0), 86400000))) as duration
    from eligible group by profile
  ), ranked as (
    select row_number() over(order by duration desc, plays desc, profile->>'id') as rank,
      profile, plays, duration from totals
    order by duration desc, plays desc, profile->>'id'
    limit greatest(1, least(result_limit, 100))
  ) select jsonb_build_object('type', case when artist_id is null then 'global' else 'artist' end,
    'targetId', coalesce(artist_id, ''), 'period', selected_period, 'updatedAt', now(),
    'entries', coalesce(jsonb_agg(jsonb_build_object('rank', rank, 'user', profile,
      'playCount', plays, 'playedDurationMs', duration)), '[]'::jsonb)) from ranked;
$$;
revoke all on function public.waveify_leaderboard(text, text, integer) from public;
grant execute on function public.waveify_leaderboard(text, text, integer) to authenticated;
$body_f94495e810f4b014$;
            insert into waveify_admin.migrations(version, checksum) values ('0004_waveify_library.sql', 'f94495e810f4b014f89577d7ec296d40aa4f1a641954a5960c3cf27750fab52d');
          elsif previous <> 'f94495e810f4b014f89577d7ec296d40aa4f1a641954a5960c3cf27750fab52d' then
            raise exception 'Waveify migration checksum mismatch: 0004_waveify_library.sql';
          end if;
        end $apply$;
do $apply$
        declare previous text;
        begin
          select checksum into previous from waveify_admin.migrations where version = '0005_waveify_remote.sql';
          if previous is null then
            execute $body_3d827be14b3159da$-- Independent protocol: legacy playback_state and track UUID relations stay intact.
create table if not exists public.waveify_playback_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  device_name text not null default 'Waveify',
  track_id text,
  track_title text,
  track_artist text,
  is_playing boolean not null default false,
  position_seconds double precision not null default 0,
  command text not null default 'none'
    check (command in ('none', 'play', 'pause', 'next', 'previous')),
  command_id uuid not null default gen_random_uuid(),
  command_sender_id uuid,
  command_created_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.waveify_playback_state enable row level security;
create policy "owners manage remote playback"
  on public.waveify_playback_state for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
revoke all on public.waveify_playback_state from anon;
grant select, insert, update, delete on public.waveify_playback_state to authenticated;
alter table public.waveify_playback_state replica identity full;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'waveify_playback_state'
     ) then
    alter publication supabase_realtime add table public.waveify_playback_state;
  end if;
end $$;
$body_3d827be14b3159da$;
            insert into waveify_admin.migrations(version, checksum) values ('0005_waveify_remote.sql', '3d827be14b3159da18246359f73b54ca859a957e307b01954c6ac30877e8eb1c');
          elsif previous <> '3d827be14b3159da18246359f73b54ca859a957e307b01954c6ac30877e8eb1c' then
            raise exception 'Waveify migration checksum mismatch: 0005_waveify_remote.sql';
          end if;
        end $apply$;
do $apply$
        declare previous text;
        begin
          select checksum into previous from waveify_admin.migrations where version = '0006_waveify_limits.sql';
          if previous is null then
            execute $body_57fb72eb99888dec$-- Bounded cloud payloads; audio remains private and local playback stays available.
-- NOT VALID preserves existing rows while enforcing the bound on new writes.
alter table public.waveify_libraries add constraint waveify_library_size
  check (octet_length(data::text) <= 16777216) not valid;
create index waveify_follows_target on public.waveify_follows(followed_id);
create index waveify_public_playlists_owner on public.waveify_public_playlists(owner_id);
create index waveify_playback_recent on public.waveify_playback_state(user_id, updated_at desc);
-- Supabase installations may grant ALL through public-schema default privileges.
-- Explicitly remove TRUNCATE/REFERENCES/TRIGGER and anonymous table access.
revoke all on public.waveify_libraries, public.waveify_profiles,
  public.waveify_follows, public.waveify_public_playlists,
  public.waveify_public_history, public.waveify_playback_state
  from public, anon, authenticated;
grant select, insert, update, delete on public.waveify_libraries,
  public.waveify_profiles, public.waveify_public_playlists,
  public.waveify_public_history, public.waveify_playback_state to authenticated;
grant select, insert, delete on public.waveify_follows to authenticated;
update storage.buckets set public = false,
  file_size_limit = least(coalesce(file_size_limit, 26214400), 26214400)
  where id = 'waveify_media';
$body_57fb72eb99888dec$;
            insert into waveify_admin.migrations(version, checksum) values ('0006_waveify_limits.sql', '57fb72eb99888dec69d6e69c1cffef4eaa6c3544ed21c0459029b8363a9a1a3e');
          elsif previous <> '57fb72eb99888dec69d6e69c1cffef4eaa6c3544ed21c0459029b8363a9a1a3e' then
            raise exception 'Waveify migration checksum mismatch: 0006_waveify_limits.sql';
          end if;
        end $apply$;
commit;
notify pgrst, 'reload schema';
