"use strict";
// Saved candidate generation, never overwrites the canonical profile or a trial.
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const profile = JSON.parse(fs.readFileSync(path.join(root,
  "config/animation_presets/seal_source_pistol_candidate.json"), "utf8"));
profile.description = "Source-owned body and one-handed pistol running. No legacy/procedural body or arm overlays. Native clip transitions and gameplay owners preserved; not original-engine parity.";
profile.locomotion.source_pose_only = true;
const output = path.join(root, "config/animation_presets/seal_source_pose_only.json");
fs.writeFileSync(output, JSON.stringify(profile, null, 2) + "\n", {flag: "wx"});
console.log("SOURCE_POSE_ONLY candidate " + output);
