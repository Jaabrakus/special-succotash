"use strict";

// Explicit opt-in preset only. Preserve every other current setting and refuse
// to overwrite an existing candidate. Originals and canonical map stay intact.
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "config/operator_animation_map.json");
const output = path.join(root, "config/animation_presets/seal_source_pistol_candidate.json");
const settings = JSON.parse(fs.readFileSync(source, "utf8"));
settings.description = "Source pistol full-body trial: native pistol locomotion and ready poses; gameplay, camera, jump, reload, grip and gait timing unchanged. Not proof of original-engine parity.";
settings.locomotion.legacy_pistol_upper_body = false;
const slots = settings.family_animation_slots.TWO_HAND_PISTOL;
for (const slot of ["ready_standing", "ready_standing_moving"]) slots[slot] = "seal_pfp_stand";
for (const slot of ["ready_crouched", "ready_crouched_moving"]) slots[slot] = "seal_pfp_crouch";
const shots = settings.event_routes.FIRE_ACCEPTED.family_states.TWO_HAND_PISTOL.posture_states;
shots.STANDING = "seal_pfp_stand";
shots.CROUCHED = "seal_pfp_crouch";
for (const clip of ["seal_pfp_stand", "seal_pfp_crouch"]) {
  const resource = settings.clips[clip];
  if (!resource || !fs.existsSync(path.join(root, resource.replace(/^res:\/\//, "")))) {
    throw new Error("Candidate refers to a missing source clip: " + clip);
  }
}
fs.writeFileSync(output, JSON.stringify(settings, null, 2) + "\n", {flag: "wx"});
console.log("SOURCE_POSE_CANDIDATE created " + output);
