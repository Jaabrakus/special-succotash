# Hit confirmation without a body highlight

Translation card: keep the existing red hit X; remove whole-body impact color.
Acceptance: normal, head/rear, and explosive damage leave target materials
unchanged; damage and the 0.15-second red reticle X still activate.
Owner: LabLeakTargetDummy owns its material presentation. SocomDynamicReticle
continues to own the existing hit X. No new owner or runtime setting is needed.
Protected: shot/damage authority, hit sounds, blood effects, health labels,
flinch/death/respawn, aim, character team colors, animation and networking.
Proof: hit_feedback_performance_regression, body_hit_vfx_regression, feature
contract gate; optional rendered check via --render on the first regression.

The training target previously replaced its textured material with an emissive
yellow/red material for 0.08 seconds. Remove the two flash resources, timer and
impact material swaps. Its normal material remains installed from construction.
Network operators do not use this training-target flash implementation.

Canonical chain: main_training_world.spawn_target_dummy -> LabLeakTargetDummy ->
take_bullet_damage_region -> health/flinch without material replacement.
main_weapon_runtime confirmed hit -> dynamic_reticle.notify_hit -> red X draw.
No published build or browser ZIP is changed by this source edit.
