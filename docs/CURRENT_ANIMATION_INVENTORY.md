# Current animation inventory

Read-only configuration audit, 2026-09-11. No animation assets or gameplay changed.

## Scope

The canonical profile loader uses `const MAP_PATH := "res://config/operator_animation_map.json"` in `scripts/player/operator_animation_profile.gd:7`.

The map registers 155 clip names. These are NOT all proven active clips: the registry includes legacy, candidates, references, aliases, and fallbacks. The reference manifest contains 261 imported clips. Neither number establishes that 300+ animations are currently used.

## Explicit weapon-family assignments

These are configured runtime slots, not a frame-by-frame gameplay coverage test. Procedural layers and blending can alter their visible result.

### TWO_HAND_PISTOL

| Slot | Clip |
|---|---|
| idle_crouched | pistol_compressed_idle_crouched |
| idle_prone | pistol_idle_prone |
| idle_standing | pistol_compressed_idle_standing |
| idle_standing_moving | pistol_idle |
| jump_down | pistol_jump_down |
| jump_loop | jump_loop |
| jump_up | pistol_jump |
| jump_up_standing | pistol_jump |
| locomotion/crouch_backward | pistol_crouch_backward |
| locomotion/crouch_forward | pistol_crouch_forward |
| locomotion/crouch_left | pistol_crouch_left |
| locomotion/crouch_right | pistol_crouch_right |
| locomotion/run_left | pistol_run_left |
| locomotion/run_right | pistol_run_right |
| locomotion_ready/crouch_backward | seal_pfp_crouchwalk_bw |
| locomotion_ready/crouch_forward | seal_pfp_crouchwalk |
| locomotion_ready/crouch_left | pistol_crouch_left |
| locomotion_ready/crouch_right | pistol_crouch_right |
| locomotion_ready/run_backward | seal_pfp_run_bw |
| locomotion_ready/run_forward | seal_pfp_run |
| locomotion_ready/run_left | seal_p_lstrafe_fast |
| locomotion_ready/run_right | seal_p_rstrafe_fast |
| locomotion_ready/walk_backward | seal_pfp_walk_bw |
| locomotion_ready/walk_forward | seal_pfp_walk |
| locomotion_ready/walk_left | pistol_strafe_left |
| locomotion_ready/walk_right | pistol_strafe_right |
| ready_crouched | legacy_pistol_ready_crouched |
| ready_crouched_moving | legacy_pistol_ready_crouched |
| ready_prone | seal_pfp_prone |
| ready_prone_moving | seal_pfp_prone |
| ready_standing | legacy_pistol_ready_standing |
| ready_standing_moving | legacy_pistol_ready_standing |
| reload_standing | pistol_reload |
| reload_crouched | pistol_reload |

### TWO_HAND_RIFLE

| Slot | Clip |
|---|---|
| firing_standing | seal_fp_stand |
| idle_standing | seal_stand_alert02 |
| locomotion_ready/crouch_backward | seal_fp_crouchwalk_bw |
| locomotion_ready/crouch_forward | seal_fp_crouchwalk |
| locomotion_ready/crouch_left | crouch_left |
| locomotion_ready/crouch_right | crouch_right |
| locomotion_ready/run_backward | seal_fp_run_bw |
| locomotion_ready/run_forward | seal_fp_run |
| locomotion_ready/run_left | seal_lstrafe_fast |
| locomotion_ready/run_right | seal_rstrafe_fast |
| locomotion_ready/walk_backward | seal_fp_walk_bw |
| locomotion_ready/walk_forward | seal_fp_walk |
| locomotion_ready/walk_left | walk_left |
| locomotion_ready/walk_right | walk_right |
| ready_crouched | seal_fp_crouch |
| ready_crouched_moving | seal_fp_crouch |
| ready_prone | seal_fp_prone |
| ready_prone_moving | seal_fp_prone |
| ready_standing | seal_stand_alert02 |
| ready_standing_moving | seal_fp_stand |

## Lean resources

```json
{
  "standing_full_body": true,
  "blend_seconds": 0.18,
  "preserve_grounded_legs": true,
  "enabled": true,
  "families": {
    "TWO_HAND_PISTOL": {
      "CROUCHED": {
        "left": "res://assets/animations/seal_reference/seal_p_crouch2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_p_crouch2rlean.tres"
      },
      "PRONE": {
        "left": "res://assets/animations/seal_reference/seal_p_prone2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_p_prone2rlean.tres"
      },
      "STANDING": {
        "left": "res://assets/animations/seal_reference/seal_p_stand2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_p_stand2rlean.tres"
      }
    },
    "TWO_HAND_RIFLE": {
      "CROUCHED": {
        "left": "res://assets/animations/seal_reference/seal_crouch2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_crouch2rlean.tres"
      },
      "PRONE": {
        "left": "res://assets/animations/seal_reference/seal_prone2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_prone2rlean.tres"
      },
      "STANDING": {
        "left": "res://assets/animations/seal_reference/seal_stand2llean.tres",
        "right": "res://assets/animations/seal_reference/seal_stand2rlean.tres"
      }
    }
  }
}
```

## All registered clips

SOCOM source names below come from the gameplay manifest where available. A blank source means it is not mapped by that manifest, not that it is original. Legacy diagonal registrations may be inactive in the source-cardinal graph.

| Registered name | Resource | Gameplay-manifest source |
|---|---|---|
| seal_stand_alert02 | res://assets/animations/seal_reference/seal_stand_alert02.tres | — |
| aim_idle | res://assets/animations/seal_gameplay/held_aim_idle.tres | seal_recoil |
| aim_idle_crouch | res://assets/animations/seal_gameplay/held_aim_idle_crouch.tres | seal_crouch_recoil |
| backward_dive_pose_candidate | res://assets/animations/authored/backward_dive_pose_candidate.tres | — |
| climb | res://assets/animations/mixamo/Climbing.fbx | — |
| traversal_hang | res://assets/animations/seal_reference/seal_hang.tres | — |
| traversal_pull_up | res://assets/animations/seal_reference/seal_hang2climbup.tres | — |
| traversal_ladder_idle | res://assets/animations/seal_reference/seal_ladder.tres | — |
| traversal_ladder_move | res://assets/animations/seal_reference/seal_climbladder.tres | — |
| traversal_ladder_slide | res://assets/animations/seal_reference/seal_ladderslide.tres | — |
| combat_fire | res://assets/animations/seal_gameplay/combat_fire.tres | seal_recoil |
| crouch_back_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward left.fbx | — |
| crouch_back_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward right.fbx | — |
| crouch_backward | res://assets/animations/seal_gameplay/crouch_backward.tres | seal_crouchwalk_bw |
| crouch_dive_back | res://assets/animations/authored/crouch_dive_back.tres | — |
| crouch_dive_left | res://assets/animations/authored/crouch_dive_left.tres | — |
| crouch_dive_right | res://assets/animations/authored/crouch_dive_right.tres | — |
| crouch_fire | res://assets/animations/seal_gameplay/crouch_fire.tres | seal_crouch_recoil |
| crouch_forward | res://assets/animations/seal_gameplay/crouch_forward.tres | seal_crouchwalk |
| crouch_forward_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward left.fbx | — |
| crouch_forward_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward right.fbx | — |
| crouch_grenade_toss | res://assets/animations/seal_gameplay/crouch_grenade_toss.tres | seal_crouch_throwgrenade |
| crouch_lateral_left | res://assets/animations/seal_gameplay/crouch_lateral_left.tres | seal_crouchstrafe_left |
| crouch_lateral_right | res://assets/animations/seal_gameplay/crouch_lateral_right.tres | seal_crouchstrafe_right_fast |
| crouch_left | res://assets/animations/seal_gameplay/crouch_left.tres | seal_crouchstrafe_left |
| crouch_right | res://assets/animations/seal_gameplay/crouch_right.tres | seal_crouchstrafe_right_fast |
| crouch_start | res://assets/animations/mixamo/Rifle Crouch Idle To Walk.fbx | — |
| crouch_stop | res://assets/animations/mixamo/Crouch Stop Walking.fbx | — |
| crouch_to_prone | res://assets/animations/seal_gameplay/crouch_to_prone.tres | seal_crouch2prone |
| crouch_to_stand | res://assets/animations/mixamo/Crouch To Standing With Rifle.fbx | — |
| death_kneel_back | res://assets/animations/mixamo/Rifle Kneel Hit To Back.fbx | — |
| death_right | res://assets/animations/mixamo/Pro Rifle Pack/death from right.fbx | — |
| dive_roll | res://assets/animations/seal_gameplay/seal_dive_to_prone.tres | seal_dive2prone |
| grenade_throw | res://assets/animations/seal_gameplay/grenade_throw.tres | seal_prone_throwgrenade |
| grenade_toss | res://assets/animations/seal_gameplay/grenade_toss.tres | seal_tossgrenade |
| idle_crouch | res://assets/animations/seal_gameplay/idle_crouch.tres | seal_crouch |
| idle_prone | res://assets/animations/seal_gameplay/idle_prone.tres | seal_prone |
| idle_rifle | res://assets/animations/seal_gameplay/idle_rifle.tres | seal_stand |
| jump_back_crouch | res://assets/animations/authored/jump_back_crouch.tres | — |
| jump_backward_action | res://assets/animations/mixamo/Jump Away.fbx | — |
| jump_dive_left | res://assets/animations/authored/jump_dive_left.tres | — |
| jump_dive_right | res://assets/animations/authored/jump_dive_right.tres | — |
| jump_down | res://assets/animations/seal_gameplay/jump_down.tres | seal_land_soft |
| jump_forward_action | res://assets/animations/seal_gameplay/jump_forward_action.tres | seal_runningjump_launch |
| jump_loop | res://assets/animations/seal_gameplay/jump_loop.tres | seal_runningjump_in_air |
| jump_peak_slide_candidate | res://assets/animations/authored/jump_peak_slide_candidate.tres | — |
| jump_slide_crouch | res://assets/animations/authored/jump_slide_crouch.tres | — |
| jump_slide_prone | res://assets/animations/seal_gameplay/seal_dive_to_prone.tres | seal_dive2prone |
| jump_up | res://assets/animations/seal_gameplay/jump_up.tres | seal_runningjump_launch |
| jump_up_standing | res://assets/animations/seal_gameplay/jump_up_standing.tres | seal_jump |
| pistol_compressed_idle_crouched | res://assets/animations/seal_gameplay/pistol_compressed_idle_crouched.tres | seal_p_crouch |
| pistol_compressed_idle_standing | res://assets/animations/seal_gameplay/pistol_compressed_idle_standing.tres | seal_p_stand |
| pistol_crouch_backward | res://assets/animations/seal_gameplay/pistol_crouch_backward.tres | seal_p_crouchwalk_bw |
| pistol_crouch_forward | res://assets/animations/seal_gameplay/pistol_crouch_forward.tres | seal_p_crouchwalk |
| pistol_crouch_left | res://assets/animations/seal_gameplay/pistol_crouch_left.tres | seal_p_crouchstrafe_left |
| pistol_crouch_right | res://assets/animations/seal_gameplay/pistol_crouch_right.tres | seal_p_crouchstrafe_right |
| pistol_fire | res://assets/animations/seal_gameplay/pistol_fire.tres | seal_p_recoil |
| pistol_idle | res://assets/animations/seal_gameplay/pistol_idle.tres | seal_p_stand |
| pistol_idle_kneeling | res://assets/animations/seal_gameplay/pistol_idle_kneeling.tres | seal_p_crouch |
| pistol_idle_prone | res://assets/animations/seal_gameplay/pistol_idle_prone.tres | seal_p_prone |
| pistol_jump | res://assets/animations/seal_gameplay/pistol_jump.tres | seal_p_runningjump_launch |
| pistol_jump_alt | res://assets/animations/seal_gameplay/pistol_jump_alt.tres | seal_p_runningjump_launch |
| pistol_jump_down | res://assets/animations/seal_gameplay/pistol_jump_down.tres | seal_p_land_soft |
| pistol_kneel_to_stand | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol kneel to stand.fbx | — |
| pistol_prone_fire | res://assets/animations/seal_gameplay/pistol_prone_fire.tres | seal_p_prone_recoil |
| pistol_recovery_reference_crouched | res://assets/animations/seal_gameplay/held_pistol_recovery_reference_crouched.tres | seal_p_recoil |
| pistol_recovery_reference_standing | res://assets/animations/seal_gameplay/held_pistol_recovery_reference_standing.tres | seal_p_recoil |
| pistol_reload | res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reload_Pistol.scn | — |
| pistol_reload_hold_prone | res://assets/animations/mixamo/Prone Forward Stop.fbx | — |
| pistol_run_back_left | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run backward arc.fbx | — |
| pistol_run_back_right | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run backward arc (2).fbx | — |
| pistol_run_backward | res://assets/animations/seal_gameplay/pistol_run_backward.tres | seal_p_run_bw |
| pistol_run_forward | res://assets/animations/seal_gameplay/pistol_run_forward.tres | seal_p_run |
| pistol_run_forward_left | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run arc.fbx | — |
| pistol_run_forward_right | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol run arc (2).fbx | — |
| pistol_run_left | res://assets/animations/seal_gameplay/pistol_run_left.tres | seal_p_run_90l |
| pistol_run_right | res://assets/animations/seal_gameplay/pistol_run_right.tres | seal_p_run_90r |
| pistol_stand_to_kneel | res://assets/animations/seal_gameplay/pistol_stand_to_kneel.tres | seal_p_stand2crouch |
| pistol_strafe_left | res://assets/animations/seal_gameplay/pistol_strafe_left.tres | seal_p_lstrafe |
| pistol_strafe_right | res://assets/animations/seal_gameplay/pistol_strafe_right.tres | seal_p_rstrafe |
| pistol_walk_back_left | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward arc.fbx | — |
| pistol_walk_back_right | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk backward arc (2).fbx | — |
| pistol_walk_backward | res://assets/animations/seal_gameplay/pistol_walk_backward.tres | seal_p_walk_bw |
| pistol_walk_forward | res://assets/animations/seal_gameplay/pistol_walk_forward.tres | seal_p_walk |
| pistol_walk_forward_left | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk arc.fbx | — |
| pistol_walk_forward_right | res://assets/animations/mixamo/Pistol_Handgun Locomotion Pack/pistol walk arc (2).fbx | — |
| prone_backward | res://assets/animations/mixamo/Moving Backward In Prone Position.fbx | — |
| prone_fire | res://assets/animations/seal_gameplay/prone_fire.tres | seal_prone_recoil |
| prone_forward | res://assets/animations/seal_gameplay/prone_forward.tres | seal_prone_crawl |
| prone_reload | res://assets/animations/mixamo/Prone Reloading.fbx | — |
| prone_stop_backward | res://assets/animations/mixamo/Prone Backwards Stop.fbx | — |
| prone_stop_forward | res://assets/animations/mixamo/Prone Forward Stop.fbx | — |
| prone_turn_left | res://assets/animations/seal_gameplay/prone_turn_left.tres | seal_prone_lstrafe |
| prone_turn_right | res://assets/animations/seal_gameplay/prone_turn_right.tres | seal_prone_rstrafe |
| reload | res://assets/animations/mixamo/Reloading.fbx | — |
| reload_ak47 | res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reloading_Rifle_AK47.scn | — |
| roll | res://assets/animations/mixamo/Run To Rolling.fbx | — |
| run_back_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint backward left.fbx | — |
| run_back_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint backward right.fbx | — |
| run_backward | res://assets/animations/seal_gameplay/run_backward.tres | seal_run_bw |
| run_forward | res://assets/animations/seal_gameplay/run_forward.tres | seal_run |
| run_forward_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint forward left.fbx | — |
| run_forward_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint forward right.fbx | — |
| run_lateral_left | res://assets/animations/seal_gameplay/run_lateral_left.tres | seal_run_90l |
| run_lateral_right | res://assets/animations/seal_gameplay/run_lateral_right.tres | seal_run_90r |
| run_left | res://assets/animations/seal_gameplay/run_left.tres | seal_run_90l |
| run_right | res://assets/animations/seal_gameplay/run_right.tres | seal_run_90r |
| run_to_stop | res://assets/animations/mixamo/Run To Stop.fbx | — |
| seal_fp_crouch | res://assets/animations/seal_firing_reference/seal_fp_crouch.tres | — |
| seal_fp_crouch_step | res://assets/animations/seal_firing_reference/seal_fp_crouch_step.tres | — |
| seal_fp_crouchwalk | res://assets/animations/seal_firing_reference/seal_fp_crouchwalk.tres | — |
| seal_fp_crouchwalk_bw | res://assets/animations/seal_firing_reference/seal_fp_crouchwalk_bw.tres | — |
| seal_fp_jog | res://assets/animations/seal_firing_reference/seal_fp_jog.tres | — |
| seal_fp_prone | res://assets/animations/seal_firing_reference/seal_fp_prone.tres | — |
| seal_fp_run | res://assets/animations/seal_firing_reference/seal_fp_run.tres | — |
| seal_fp_run_bw | res://assets/animations/seal_firing_reference/seal_fp_run_bw.tres | — |
| seal_fp_stand | res://assets/animations/seal_firing_reference/seal_fp_stand.tres | — |
| seal_fp_step | res://assets/animations/seal_firing_reference/seal_fp_step.tres | — |
| seal_fp_twist_pitch | res://assets/animations/seal_firing_reference/seal_fp_twist_pitch.tres | — |
| seal_fp_walk | res://assets/animations/seal_firing_reference/seal_fp_walk.tres | — |
| seal_fp_walk_bw | res://assets/animations/seal_firing_reference/seal_fp_walk_bw.tres | — |
| seal_lstrafe_fast | res://assets/animations/seal_firing_reference/seal_lstrafe_fast_locomotion.tres | — |
| seal_p_lstrafe_fast | res://assets/animations/seal_firing_reference/seal_p_lstrafe_fast_locomotion.tres | — |
| seal_p_rstrafe_fast | res://assets/animations/seal_firing_reference/seal_p_rstrafe_fast_locomotion.tres | — |
| seal_pfp_crouch | res://assets/animations/seal_firing_reference/seal_pfp_crouch_composed.tres | — |
| seal_pfp_crouch_step | res://assets/animations/seal_firing_reference/seal_pfp_crouch_step.tres | — |
| seal_pfp_crouchwalk | res://assets/animations/seal_firing_reference/seal_pfp_crouchwalk_composed.tres | — |
| seal_pfp_crouchwalk_bw | res://assets/animations/seal_firing_reference/seal_pfp_crouchwalk_bw_composed.tres | — |
| seal_pfp_jog | res://assets/animations/seal_firing_reference/seal_pfp_jog.tres | — |
| seal_pfp_prone | res://assets/animations/seal_firing_reference/seal_pfp_prone_composed.tres | — |
| seal_pfp_run | res://assets/animations/seal_firing_reference/seal_pfp_run_composed.tres | — |
| seal_pfp_run_bw | res://assets/animations/seal_firing_reference/seal_pfp_run_bw.tres | — |
| seal_pfp_stand | res://assets/animations/seal_firing_reference/seal_pfp_stand.tres | — |
| seal_pfp_step | res://assets/animations/seal_firing_reference/seal_pfp_step.tres | — |
| seal_pfp_walk | res://assets/animations/seal_firing_reference/seal_pfp_walk_composed.tres | — |
| seal_pfp_walk_bw | res://assets/animations/seal_firing_reference/seal_pfp_walk_bw.tres | — |
| seal_rstrafe_fast | res://assets/animations/seal_firing_reference/seal_rstrafe_fast_locomotion.tres | — |
| start_backward | res://assets/animations/mixamo/Shooter Pack/start walking backwards.fbx | — |
| start_forward | res://assets/animations/mixamo/Start Walking.fbx | — |
| stop_backward | res://assets/animations/mixamo/Shooter Pack/walk backwards stop.fbx | — |
| stop_forward | res://assets/animations/mixamo/Shooter Pack/stop walking.fbx | — |
| turn_90_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/turn 90 left.fbx | — |
| turn_90_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/turn 90 right.fbx | — |
| walk_back_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk backward left.fbx | — |
| walk_back_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk backward right.fbx | — |
| walk_backward | res://assets/animations/seal_gameplay/walk_backward.tres | seal_walk_bw |
| walk_forward | res://assets/animations/seal_gameplay/walk_forward.tres | seal_walk |
| walk_forward_left | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk forward left.fbx | — |
| walk_forward_right | res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk forward right.fbx | — |
| walk_left | res://assets/animations/seal_gameplay/walk_left.tres | seal_lstrafe |
| walk_right | res://assets/animations/seal_gameplay/walk_right.tres | seal_rstrafe |
| legacy_pistol_idle_standing | res://assets/animations/authored/pistol_compressed/pistol_compressed_idle_standing.tres | — |
| legacy_pistol_ready_standing | res://assets/animations/authored/pistol_compressed/pistol_recovery_reference_standing.tres | — |
| legacy_pistol_idle_crouched | res://assets/animations/authored/pistol_compressed/pistol_compressed_idle_crouched.tres | — |
| legacy_pistol_ready_crouched | res://assets/animations/authored/pistol_compressed/pistol_recovery_reference_crouched.tres | — |

## Important mixed-source entries

`prone_reload` maps to `res://assets/animations/mixamo/Prone Reloading.fbx`; `reload` maps to Mixamo Reloading; `pistol_reload` and `reload_ak47` map to AGLS scenes. The current setup is not an all-SOCOM 1:1 animation set. Weapon fitting, masks, held frames, playback scaling, and procedural corrections also affect the final pose.

