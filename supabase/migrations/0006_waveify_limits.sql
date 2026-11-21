-- Bounded cloud payloads; audio remains private and local playback stays available.
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
