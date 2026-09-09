# Stairs remain ordinary locomotion

Translation card: walk up and down stairs without Jump or climbing. Acceptance:
the canonical player traverses both directions, remains grounded and never enters
vault/hang/climb with traversal enabled. Map collision is owned by SocomMapRuntime
and its imported-asset builder; CharacterBody3D remains the only body mover.
Protect jump physics, camera, aim, weapons, networking and animation. Proof:
`tools/stair_playability_regression.gd`, both default and `-- --imported`.

Expanded translation card after player-awareness request: normal grounded standing
and crouched movement automatically recognizes small static risers from collision
geometry, without stair names/tags/ramps. CharacterBody owns the adjustment;
`player_step_probe.gd` is a stateless query helper. Shared `config/step_assist.json`
limits rise/descent to 28cm. A blocked horizontal capsule sweep triggers a top
ray, then full-body upward/across clearance. The controller performs a swept lift
and ordinary `move_and_slide`; bounded downward support checks keep sharp tread
corners grounded using the existing serialized contact override. No transform
teleports, animation root motion or extra horizontal travel. Jump ascent, airborne,
prone and committed traversal bypass this assist. Taller edges retain the existing
deliberate climb policy. Proof adds `-- --raw-steps`, `step_probe_regression.gd`
and network/jump regressions. The raw fixture uses ten 18cm risers and 32cm treads.

Map Lab's authored stairs already had a smooth convex ramp. They now carry
`walkable_stairs`, which both manual ledge and automatic vault probes reject.
Imported GLBs now expose four explicit **Stairs — smooth ramp** collision choices
in the imported-asset inspector. Choose the model-local uphill axis (-Z, +Z, +X,
or -X); then save the map normally. `properties.collision_mode` is consumed by the
same builder in editor preview and canonical runtime. Object rotation and scale
are retained; embedded solid shapes are disabled for this explicit replacement.

Optional ramp mode is for a **single straight stair flight** whose bounds cover the walking
surface. Do not use whole-building or railing-inclusive bounds, curved stairs,
or slopes exceeding the player's floor angle (default 45 degrees). Split those
assets into walkable flight modules first. Existing imported placements are not
guessed or bulk rewritten. This does not make every arbitrary mesh traversable.
Bullet/camera collision follows the smooth ramp, not each visible riser. Foot
contact presentation is unchanged; this pass does not claim exact tread IK.

System delta: MERGE. Existing map-editor ramp plus box/trimesh-only import scores
3/5/4/2/4/3 (correctness/ownership/runtime parity/editor/performance/coverage).
Shared stair geometry, explicit saved import choices and traversal exclusions
score 4/5/5/4/4/4. Evidence: `socom_stair_collision.gd`,
`socom_imported_map_asset_builder.gd`, `socom_map_runtime.gd`,
`socom_mantle_motor.gd`, and stair regression. No second step-up movement motor.

Second delta: MERGE geometry-aware stepping into the canonical controller.
Ramp-only approach scores 3/5/5/3/5/4; bounded static-riser probes score
4/5/5/5/4/4. Evidence: `player_step_probe.gd`, controller collision method,
raw stair traversal and negative clearance/drop tests. The modest query cost
is conditional on ordinary grounded movement; extra rise queries only run when
the forward capsule sweep is blocked. No moving-platform step support claimed.

API checked against [Godot ConvexPolygonShape3D documentation](https://docs.godotengine.org/en/latest/classes/class_convexpolygonshape3d.html).
Latest docs warn about unreleased APIs; this uses the existing points interface
and is tested on installed Godot 4.7.1.
Movement API: [CharacterBody3D](https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html).
