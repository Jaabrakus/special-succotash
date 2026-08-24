# SOCOM-141 Operator Reviewer

This is the first safe browser companion for SOCOM-141. It makes animation review faster without rebuilding the game or moving gameplay authority out of Godot.

The reviewer can:

- load the canonical PS1 gas-mask operator and a default rifle animation;
- open local FBX or GLB models and animations;
- play, pause, slow down, restart, and scrub an animation;
- search the skeleton and inspect a bone's world transform;
- place review markers for foot plants, reload beats, grenade release, and action recovery;
- export and validate a versioned review-only JSON handoff.

It cannot edit the Godot project, camera, collisions, weapons, multiplayer state, or animation runtime. Exported JSON is review evidence only. Godot remains the authority.

## Run it

From this directory:

```sh
npm install
npm run dev
```

Then open the local address printed by Vite.

For a production build:

```sh
npm test
npm run build
```

## Safe handoff contract

The exported document follows:

`config/contracts/animation_review_contract.schema.json`

Every document is marked `review_only: true`, `apply_to_gameplay: false`, and `authority: "godot"`. The first version deliberately requires an empty `authored_changes` array.

## Next gates

1. Read-only review — this slice.
2. Draft corrections in a disposable browser workspace.
3. A Godot-side validator and preview importer.
4. Explicit human approval before any reviewed change reaches canonical assets.

Direct browser-to-game writes are outside the design.
