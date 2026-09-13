## 2026-09-12T01:53:24Z
Read /Users/kiwimango/socom-141-camera-lab/ORIGINAL_REQUEST.md.
Your working directory is /Users/kiwimango/socom-141-camera-lab/.agents/explorer_ballistics_2.
Read docs/GAMEPLAY_INTENT_DICTIONARY.md, docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md, and AGENTS.md.

Your mission is technical investigation for Requirement R1 & R3 regarding the 4 ballistics defects (WEAP-01, WEAP-02, WEAP-04, WEAP-05):
1. Investigate the extracted static data tables in `config/reference/socom2_weapon_settings.json` (from `RUN/ZWEAPON.ZAR` -> `zweapon.rdr`).
   - Examine the exact JSON schema and values for recoil (e.g. `ReticuleKnockMax` for Stand 45 vs Prone 20, crouch values, etc.), bloom, spread, and stance modifiers across weapons (especially M4A1 and default weapons).
2. Investigate the Godot implementation in `scripts/weapons/weapon_ballistics.gd`, `scripts/weapons/weapon_fire_mode_policy.gd`, `scripts/runtime/weapon_reload_coordinator.gd`, and `scripts/runtime/main_grenade_runtime.gd`.
   - WEAP-01: How prone recoil bloom fallback is currently implemented in `weapon_ballistics.gd` (e.g. lines 363-381). Identify exact lines where prone stance is handled/omitted and how recoil values for Prone, Crouch, Stand are calculated.
   - WEAP-02: How crouch bloom rate per shot (`crouch_bloom_per_shot_deg`) is currently defined and used in `weapon_ballistics.gd` (e.g. lines 41, 45). Verify why it is 1.35° and what value it should be (<= 0.32°) to match standing bloom.
   - WEAP-04: Auto-reload behavior in `weapon_reload_coordinator.gd` (e.g. lines 99, 172). Investigate the PS2 MIPS gameplay engine conventions (executable state machine for reloads) vs static table fields. Document how PS2 handles empty clip reload, mobility cancellation (sprint, dive, swap), and what makes it a runtime state machine behavior rather than a static table field.
   - WEAP-05: Grenade throw velocity in `main_grenade_runtime.gd` (e.g. lines 425-433). Investigate how velocity is handled at throw initiation and why player velocity is zeroed vs PS2 momentum inheritance.
3. Explicitly document the distinction between what is defined in the static ISO tables (`zweapon.rdr` / `socom2_weapon_settings.json`) vs what is governed by the PS2 runtime state machine (MIPS engine execution).
4. Review existing tests: `tools/ballistic_convergence_regression.gd`, `tools/ballistic_reference_reticle_regression.gd`, `tools/feature_contract_regression.gd`. Determine what tests exist or are needed to verify:
   - Prone recoil uses authentic ISO reduction (`ReticuleKnockMax: 20` vs Stand `45`).
   - Crouch bloom rate per shot is less than or equal to standing bloom rate (<= 0.32°).
5. Produce a comprehensive report in `/Users/kiwimango/socom-141-camera-lab/.agents/explorer_ballistics_2/handoff.md` and send a message when complete.
