#!/usr/bin/env python3
import os
import subprocess
import time
import json

GODOT_BIN = "/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot"
PROJECT_DIR = "/Users/kiwimango/socom-141-camera-lab"
OUTPUT_DIR = os.path.join(PROJECT_DIR, ".agents/worker_regression_1/logs")
os.makedirs(OUTPUT_DIR, exist_ok=True)

test_suites = [
    # R1: Locomotion, Posture & Jump Mechanics
    {"id": "mobility", "script": "tools/mobility_regression.gd", "category": "R1_locomotion"},
    {"id": "locomotion_playback_cadence", "script": "tools/locomotion_playback_cadence_regression.gd", "category": "R1_locomotion"},
    {"id": "directional_locomotion_phase", "script": "tools/directional_locomotion_phase_regression.gd", "category": "R1_locomotion"},
    {"id": "diagonal_mobility", "script": "tools/diagonal_mobility_regression.gd", "category": "R1_locomotion"},
    {"id": "gait_lean_continuity", "script": "tools/gait_lean_continuity_regression.gd", "category": "R1_locomotion"},
    {"id": "stair_playability", "script": "tools/stair_playability_regression.gd", "category": "R1_locomotion"},
    {"id": "source_jump", "script": "tools/source_jump_regression.gd", "category": "R1_locomotion"},
    {"id": "seal_dive", "script": "tools/seal_dive_regression.gd", "category": "R1_locomotion"},
    {"id": "crouch_strafe_continuity", "script": "tools/crouch_strafe_continuity_probe.gd", "category": "R1_locomotion"},
    {"id": "prone_grounding", "script": "tools/prone_grounding_regression.gd", "category": "R1_locomotion"},
    {"id": "strafe_latency", "script": "tools/test_strafe_latency_regression.gd", "category": "R1_locomotion"},
    {"id": "strafe_head_orientation", "script": "tools/strafe_head_orientation_regression.gd", "category": "R1_locomotion"},

    # R2: Weapon Handling & Ballistics
    {"id": "weapon_fire", "script": "tools/weapon_fire_regression.gd", "args": ["--", "--camera-regression-map"], "category": "R2_weapon"},
    {"id": "all_weapon_fire_recovery", "script": "tools/all_weapon_fire_recovery_regression.gd", "category": "R2_weapon"},
    {"id": "weapon_auto_reload", "script": "tools/weapon_auto_reload_regression.gd", "category": "R2_weapon"},
    {"id": "socom2_matched_firing", "script": "tools/socom2_matched_firing_regression.gd", "category": "R2_weapon"},
    {"id": "socom2_weapon_behavior", "script": "tools/socom2_weapon_behavior_regression.gd", "category": "R2_weapon"},
    {"id": "rapid_tap_bloom", "script": "tools/rapid_tap_bloom_regression.gd", "category": "R2_weapon"},
    {"id": "bloom_shot_envelope", "script": "tools/bloom_shot_envelope_regression.gd", "category": "R2_weapon"},
    {"id": "weapon_bloom_profile", "script": "tools/weapon_bloom_profile_regression.gd", "category": "R2_weapon"},
    {"id": "weapon_stance_bloom", "script": "tools/weapon_stance_bloom_regression.gd", "category": "R2_weapon"},
    {"id": "reload_authority", "script": "tools/reload_authority_regression.gd", "category": "R2_weapon"},
    {"id": "reload_input", "script": "tools/reload_input_regression.gd", "category": "R2_weapon"},
    {"id": "gameplay_reload_completion", "script": "tools/gameplay_reload_completion_regression.gd", "category": "R2_weapon"},
    {"id": "dedicated_reload", "script": "tools/dedicated_reload_regression.gd", "category": "R2_weapon"},
    {"id": "tactical_grenade_profile", "script": "tools/tactical_grenade_profile_regression.gd", "category": "R2_weapon"},
    {"id": "grenade_trajectory_collision", "script": "tools/grenade_trajectory_collision_regression.gd", "category": "R2_weapon"},
    {"id": "grenade_aim_pitch", "script": "tools/grenade_aim_pitch_regression.gd", "category": "R2_weapon"},
    {"id": "grenade_throw_visual", "script": "tools/grenade_throw_visual_regression.gd", "category": "R2_weapon"},
    {"id": "player_health_weapon_ammo", "script": "tools/player_health_weapon_ammo_regression.gd", "category": "R2_weapon"},
    {"id": "firearm_family_live_contact", "script": "tools/firearm_family_live_contact_regression.gd", "category": "R2_weapon"},
    {"id": "firearm_family_presentation", "script": "tools/firearm_family_presentation_regression.gd", "category": "R2_weapon"},
    {"id": "test_dynamic_hand_owned_weapon", "script": "tools/test_dynamic_hand_owned_weapon.gd", "category": "R2_weapon"},
    {"id": "test_dynamic_reload_handoff", "script": "tools/test_dynamic_reload_handoff.gd", "category": "R2_weapon"},
    {"id": "sniper_torso_damage", "script": "tools/sniper_torso_damage_regression.gd", "category": "R2_weapon"},
    {"id": "shotgun_projectile", "script": "tools/shotgun_projectile_regression.gd", "category": "R2_weapon"},

    # R3: Camera & HUD Presentation
    {"id": "camera_obstruction_guard", "script": "tools/camera_obstruction_guard_regression.gd", "category": "R3_camera_hud"},
    {"id": "camera_passage_perception", "script": "tools/camera_passage_perception_regression.gd", "category": "R3_camera_hud"},
    {"id": "socom2_reticle", "script": "tools/socom2_reticle_regression.gd", "category": "R3_camera_hud"},
    {"id": "reticle_render_integration", "script": "tools/reticle_render_integration.gd", "category": "R3_camera_hud"},
    {"id": "custom_reticle", "script": "tools/custom_reticle_regression.gd", "category": "R3_camera_hud"},
    {"id": "contextual_hud", "script": "tools/contextual_hud_regression.gd", "category": "R3_camera_hud"},
    {"id": "action_hud_tracking", "script": "tools/action_hud_tracking_regression.gd", "category": "R3_camera_hud"},
    {"id": "stance_hud_bloom", "script": "tools/stance_hud_bloom_regression.gd", "category": "R3_camera_hud"},
    {"id": "public_training_range", "script": "tools/public_training_range_regression.gd", "category": "R3_camera_hud"},

    # Framework & System Rules
    {"id": "feature_contracts", "script": "tools/feature_contract_regression.gd", "category": "Architecture"},
    {"id": "god_file_budget", "script": "tools/god_file_budget_regression.gd", "category": "Architecture"},
    {"id": "socom_rule_end_to_end", "script": "tools/socom_rule_end_to_end_regression.gd", "category": "Architecture"}
]

results = []

for t in test_suites:
    sid = t["id"]
    script = t["script"]
    cat = t["category"]
    extra_args = t.get("args", [])
    cmd = [GODOT_BIN, "--headless", "-s", script] + extra_args
    log_file = os.path.join(OUTPUT_DIR, f"{sid}.log")
    
    print(f"[{cat}] Running {sid} ({script})...", flush=True)
    t0 = time.time()
    try:
        proc = subprocess.run(
            cmd,
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120
        )
        duration = round(time.time() - t0, 2)
        output = proc.stdout
        exit_code = proc.returncode
    except subprocess.TimeoutExpired as e:
        duration = round(time.time() - t0, 2)
        output = (e.stdout or "") + f"\nTIMEOUT after 120s"
        exit_code = -124

    with open(log_file, "w", encoding="utf-8") as f:
        f.write(f"COMMAND: {' '.join(cmd)}\n")
        f.write(f"EXIT_CODE: {exit_code}\n")
        f.write(f"DURATION: {duration}s\n\n")
        f.write(output)

    # Analyze errors / failures
    has_script_error = "SCRIPT ERROR" in output or "Parse Error" in output
    has_fail = exit_code != 0 or "FAIL" in output or has_script_error
    
    # Extract error lines
    fail_lines = [l.strip() for l in output.splitlines() if "FAIL" in l or "ERROR:" in l or "SCRIPT ERROR" in l]

    status = "PASS" if not has_fail else "FAIL"
    print(f"  -> {status} (code {exit_code}, {duration}s)", flush=True)
    if fail_lines:
        for fl in fail_lines[:5]:
            print(f"     ! {fl}", flush=True)

    results.append({
        "id": sid,
        "script": script,
        "category": cat,
        "command": " ".join(cmd),
        "exit_code": exit_code,
        "duration": duration,
        "status": status,
        "fail_lines": fail_lines,
        "log_path": log_file
    })

summary_file = os.path.join(PROJECT_DIR, ".agents/worker_regression_1/test_run_summary.json")
with open(summary_file, "w", encoding="utf-8") as f:
    json.dump(results, f, indent=2)

print("\n--- TEST RUN FINISHED ---")
total = len(results)
passed = sum(1 for r in results if r["status"] == "PASS")
failed = sum(1 for r in results if r["status"] == "FAIL")
print(f"Total: {total}, Passed: {passed}, Failed: {failed}")
