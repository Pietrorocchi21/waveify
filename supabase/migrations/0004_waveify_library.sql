-- Account library snapshots use independent tables, avoiding legacy schema assumptions.
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
