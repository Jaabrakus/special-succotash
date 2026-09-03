# SOCOM-141 Standalone Systems (Unified Single Folder)

All 5 core gameplay systems are unified directly inside this single folder (`standalone_labs/`):

---

## Folder Layout

```
standalone_labs/
├── master_lab_hub.tscn        # Master Hub UI to launch any of the 5 labs with 1 click
├── master_lab_hub.gd
│
├── 1_camera_lab.tscn          # System 1: SOCOM Camera Lab
├── camera_lab_sandbox.gd
│
├── 2_guns_lab.tscn            # System 2: Weapon & Gunsmith Lab
├── guns_lab_sandbox.gd
├── dummy_target.gd
│
├── 3_grenade_lab.tscn         # System 3: Tactical Grenades Lab
│
├── 4_sound_lab.tscn           # System 4: 3D Sound & Foley Lab
│
├── 5_reticle_lab.tscn         # System 5: Reticle & Composure Lab
│
├── weapons/                   # Standalone weapon scenes (m16a2.tscn, assaultrifle_1.tscn, etc.)
├── configs/                   # JSON weapon profiles (fire rates, bloom, recoil, sockets)
└── README.md                  # This guide
```

---

## How to Run

1. **Master Hub**: Open `res://standalone_labs/master_lab_hub.tscn` and press **F6** to see the 5-button launcher.
2. **Individual Labs**: Double-click any of `1_camera_lab.tscn`, `2_guns_lab.tscn`, `3_grenade_lab.tscn`, `4_sound_lab.tscn`, or `5_reticle_lab.tscn` and press **F6** to run directly.

---

## Quick Reference of the 5 Systems

| # | System Scene | Key Features |
|---|---|---|
| 1 | **`1_camera_lab.tscn`** | Wall collisions, low ceiling clearance, shoulder offsets ($X/Y/Z$), FOV, and recoil kick recovery. |
| 2 | **`2_guns_lab.tscn`** | Sockets (`Socket_LeftHand`, `Socket_Muzzle`), fire rate RPM, bloom spread, recoil climb, and 10m/20m/35m targets with JSON saving. |
| 3 | **`3_grenade_lab.tscn`** | Smoke, Flashbang, and Frag physics trajectories (underhand/overhand), bounce restitution, and screen effects. |
| 4 | **`4_sound_lab.tscn`** | 3D acoustic propagation, wall occlusion loss, room reverb, and animation bone-synced footstep foley scrubbing. |
| 5 | **`5_reticle_lab.tscn`** | Dynamic reticle brackets, stance composure bonuses (Standing/Crouching/Prone), turning stress, and graze damage. |
