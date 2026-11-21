-- Independent protocol: legacy playback_state and track UUID relations stay intact.
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
