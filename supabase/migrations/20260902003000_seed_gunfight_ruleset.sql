-- One deterministic public identity for the current authoritative 2v2 rules.
-- The match server still owns every live decision; this row is only the saved
-- version/build contract referenced by directory and result records.

insert into public.gameplay_rulesets (
  id,
  ruleset_key,
  version,
  game_build,
  lifecycle,
  weapon_manifest,
  movement_manifest,
  mode_manifest,
  content_sha256,
  activated_at
) values (
  '14100000-0000-4000-8000-000000000001'::uuid,
  'gunfight_2v2',
  1,
  '0.1.0',
  'active',
  '{"authority":"dedicated_server"}'::jsonb,
  '{"owner":"CharacterBody3D"}'::jsonb,
  '{"mode":"gunfight_2v2","rounds_to_win":3,"maximum_rounds":6}'::jsonb,
  encode(digest('socom-141|0.1.0|protocol=1|gunfight_2v2|ruleset=1', 'sha256'), 'hex'),
  now()
)
on conflict (ruleset_key, version) do update set
  game_build = excluded.game_build,
  lifecycle = excluded.lifecycle,
  weapon_manifest = excluded.weapon_manifest,
  movement_manifest = excluded.movement_manifest,
  mode_manifest = excluded.mode_manifest,
  content_sha256 = excluded.content_sha256,
  activated_at = coalesce(public.gameplay_rulesets.activated_at, excluded.activated_at);
