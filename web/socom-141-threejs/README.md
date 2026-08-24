# SOCOM-141 Three.js Field Test

This is a separate playable web vertical slice. It does not replace or modify the Godot runtime.

The first slice contains:

- the canonical PS1 operator;
- a third-person camera based on the current SOCOM camera measurements;
- standing, crouched, prone, jumping, and responsive strafing movement;
- the current assault-rifle ammo, damage, fire-rate, spread, bloom, reticle, reload, and auto-reload values;
- charged frag throws with a predicted arc, collision, bounce, fuse, blast falloff, and target damage;
- a compact training range and four damageable targets.

This build is local-only. It is not a multiplayer authority implementation.

## Run

```sh
npm install
npm run dev
```

## Verify

```sh
npm test
npm run build
```

All source for this experiment stays inside this directory. The Godot project remains the reference until a side-by-side review approves further porting.
