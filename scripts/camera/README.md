# SOCOM Camera System Integration Contract & Marker Specification

This document defines the exact contract, node markers, collision layers, and input bindings required by the **SOCOM Camera System** (`scripts/camera/socom_camera.gd`).

---

## 1. Required Target Markers

The camera rig (`SocomCameraRig`) tracks four spatial reference points on any character or mannequin to calculate pitch framing, head avoidance, and posture transitions (Standing, Crouching, Prone):

```text
Target Character Root (CharacterBody3D or Node3D)
  ├── HeadMarker    (Marker3D, local position ~ (0.0, 1.70, 0.0))
  ├── TorsoMarker   (Marker3D, local position ~ (0.0, 1.20, 0.0))
  ├── PelvisMarker  (Marker3D, local position ~ (0.0, 0.85, 0.0))
  └── FeetMarker    (Marker3D, local position ~ (0.0, 0.05, 0.0))
```

### Marker Reference Roles:
- **`HeadMarker`**: Used for high-angle aim clearance, wall peek raycasts, and preventing the camera from clipping into the character's head during upward aiming.
- **`TorsoMarker`**: The primary aim anchor. Orbit rotations and shoulder offsets (X, Y, Z) are evaluated relative to this marker.
- **`PelvisMarker`**: Used for posture transition detection (e.g. crouching/prone height delta) to smoothly interpolate camera height without jarring cuts.
- **`FeetMarker`**: Used for ground clearance and preventing the camera spring arm from clipping through the floor when looking upwards.

---

## 2. Setting Up the Camera on Any Character

To attach the camera to any player or mannequin in code:

```gdscript
var camera_rig = SocomCameraRig.new()
camera_rig.name = "SocomCamera"
camera_rig.target = player_node
camera_rig.head_marker = player_node.get_node("HeadMarker")
camera_rig.torso_marker = player_node.get_node("TorsoMarker")
camera_rig.pelvis_marker = player_node.get_node("PelvisMarker")
camera_rig.feet_marker = player_node.get_node("FeetMarker")
add_child(camera_rig)
```

---

## 3. Physics & Wall Collision Requirements

The camera uses raycasts and sphere casts to prevent clipping through world geometry:
- **Collision Mask**: Layers `1` (Default World), `2` (Environment / Walls), and `19` (`VIRTUAL_WALL_OBSERVER_LAYER`).
- **Target Exclusion**: The camera automatically excludes `target.get_rid()` so the character's own collision capsule never pushes the camera.
- **Collision Cushion**: Default `0.18m` radius sphere cast prevents near-plane clipping when pressed back against a wall.

---

## 4. Aiming, Recoil & Input Contract

- **`aim_yaw` / `aim_pitch`**: Authoritative camera aim angles (radians).
- **`yaw` / `pitch`**: Current smoothed rendering angles.
- **Functional Recoil**: To apply weapon recoil kickback to the camera:
  ```gdscript
  camera_rig.apply_functional_recoil(
      pitch_kick_rad,      # Upward climb per shot (e.g. deg_to_rad(1.2))
      yaw_kick_rad,        # Horizontal deviation per shot (e.g. deg_to_rad(0.3))
      max_pitch_rad,       # Maximum cumulative climb (e.g. deg_to_rad(8.0))
      max_yaw_rad,         # Maximum cumulative horizontal drift
      recovery_delay_sec,  # Delay before centering (e.g. 0.08s)
      recovery_speed_rad   # Return speed (e.g. deg_to_rad(12.0)/s)
  )
  ```
- **Mouse Aim String Guide**: When `mouse_aim_string_enabled = true`, the blue reticle dot guides aim responsiveness with spring-mass damping before rotating the camera body.
