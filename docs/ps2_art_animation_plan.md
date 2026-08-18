# PS2 Tactical Art and Animation Target

This project should evoke a serious early-2000s console tactical game while remaining an original, unbranded work. The visual target is `assets/art_direction/mediterranean_blue_hour_ps2_target_v2.png`.

Movement and presentation reference: [Splinter Cell: Double Agent PS2 — Iceland playlist](https://www.youtube.com/watch?v=6K3o0RH6pJg&list=PL427E920AFADFE03F). Use it to study body weight, crouched movement, low-light silhouette readability, contextual transitions, and period-appropriate pacing. Do not copy its character, level, interface, dialogue, or branded assets.

## Rendering target

- Render internally at 640x360 and upscale cleanly to the 1280x720 window.
- Favor visibly low-poly silhouettes and strong proportions over tiny geometry detail.
- Use mostly hand-painted diffuse textures: 512x512 for the operator, 128-512px for environment surfaces and props.
- Keep materials matte. Use limited specular response, simple shadows, distance fog, restrained color banding, and subtle dithering.
- Use desaturated olive, blue-gray, dusty tan, charcoal, and aged cream. Warm lights should be sparse navigation landmarks.
- Avoid modern photorealistic PBR, ray-traced lighting, glossy tactical gear, excessive post-processing, and copied franchise assets.

## Character production target

- One original operator mesh, approximately 5,000-8,000 triangles.
- One shared humanoid skeleton, roughly 32-45 deform bones, with no facial rig required for the first playable slice.
- Separate sockets for primary weapon, muzzle, left-hand IK, right-hand IK, and equipment.
- One 512x512 operator diffuse atlas plus small weapon/equipment atlases. Normal maps are optional and should remain subtle.
- Export as a Godot-ready `.glb` with consistent bone names, scale, forward axis, and root motion policy.

## First playable animation set

All clips should be authored at 30 fps. Locomotion clips must loop cleanly and share consistent foot timing.

1. Rifle idle
2. Walk forward
3. Walk backward
4. Strafe left
5. Strafe right
6. Jog forward
7. Stealth walk forward
8. Standing turn left
9. Standing turn right
10. Aim idle with additive yaw/pitch range
11. Fire recoil
12. Tactical reload
13. Empty reload
14. Weapon obstruction/tuck
15. Enter crouch
16. Crouch idle
17. Crouch walk forward
18. Crouch walk backward
19. Crouch strafe left
20. Crouch strafe right
21. Exit crouch
22. Hit reaction front
23. Hit reaction back
24. Death fall

## Second animation pass

- Prone enter, idle, crawl, and exit
- Sprint start, loop, and stop
- Door interaction, pickup, objective interaction, and teammate revive
- Lean or corner-peek poses if the gameplay design adopts them
- Low mantle and ladder traversal if the first mission layout requires them
- Additional directional hit reactions and death variations
- Squad hand signals and contextual idle variations

Do not schedule ledge hanging, split jumps, complex takedowns, or a large traversal library until the first mission's squad combat, enemy AI, and networked animation states are stable.

## Godot animation setup

- Use an `AnimationTree` with a directional locomotion blend space.
- Blend the lower-body locomotion separately from upper-body aiming and recoil.
- Keep the current authoritative camera/weapon target; drive the chest, head, hands, and weapon toward it with additive animation plus IK.
- Preserve the existing obstruction behavior by blending into the weapon-tuck pose when the muzzle is blocked.
- Footstep events, muzzle events, magazine events, and interaction events should be animation call tracks, not hard-coded delays.

## Implementation order

1. Build and rig the low-poly operator.
2. Import the skeleton with rifle idle, four-direction walk, jog, aim, fire, and reload.
3. Replace the procedural mannequin only after the camera regression suite passes with the new mesh.
4. Add crouch and obstruction transitions.
5. Add reactions, death, prone, and interaction clips.
6. Polish foot planting, hand IK, animation blending, and multiplayer replication boundaries.
