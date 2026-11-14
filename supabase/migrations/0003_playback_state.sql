create table if not exists public.playback_state (
  user_id uuid primary key references auth.users on delete cascade,
  device_name text not null default 'Dispositivo',
  device_id text not null,
  track_id uuid references public.tracks on delete set null,
  track_title text,
  track_artist text,
  is_playing boolean not null default false,
  position_seconds numeric not null default 0,
  command text not null default 'none',
  command_id uuid not null default gen_random_uuid(),
  updated_at timestamptz not null default now()
);

alter table public.playback_state enable row level security;

create policy "users manage own playback state"
on public.playback_state for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);