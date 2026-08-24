import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  createReviewContract,
  REVIEW_KIND,
  REVIEW_SCHEMA_VERSION,
  validateReviewContract,
} from "../src/review-contract.js";

test("creates a review-only Godot-authoritative document", () => {
  const document = createReviewContract({
    assetPath: "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx",
    assetName: "PS1 Gas Mask Operator",
    clipName: "rifle_aiming_idle",
    durationSeconds: 2,
    boneCount: 65,
    markers: [
      { id: "release", type: "GRENADE_RELEASED", time_seconds: 0.9 },
      { id: "plant", type: "FOOT_PLANT_LEFT", time_seconds: 0.2, bone: "mixamorig_LeftFoot" },
    ],
  });

  assert.equal(document.schema_version, REVIEW_SCHEMA_VERSION);
  assert.equal(document.kind, REVIEW_KIND);
  assert.equal(document.review_only, true);
  assert.equal(document.apply_to_gameplay, false);
  assert.equal(document.authority, "godot");
  assert.deepEqual(document.authored_changes, []);
  assert.equal(document.markers[0].id, "plant");
  assert.equal(validateReviewContract(document).valid, true);
});

test("clamps marker time to the clip duration", () => {
  const document = createReviewContract({
    assetPath: "local://take.fbx",
    assetName: "take.fbx",
    clipName: "Take 001",
    durationSeconds: 1.5,
    markers: [{ type: "ACTION_RECOVERY", time_seconds: 8 }],
  });
  assert.equal(document.markers[0].time_seconds, 1.5);
});

test("rejects any document that tries to apply itself to gameplay", () => {
  const document = createReviewContract({
    assetPath: "local://take.glb",
    assetName: "take.glb",
    clipName: "Take 001",
    durationSeconds: 1,
  });
  document.review_only = false;
  document.apply_to_gameplay = true;
  document.authored_changes.push({ bone: "mixamorig_RightHand" });

  const result = validateReviewContract(document);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((error) => error.includes("gameplay")));
  assert.ok(result.errors.some((error) => error.includes("authored_changes")));
});

test("rejects unknown events and out-of-range marker times", () => {
  const document = createReviewContract({
    assetPath: "local://take.glb",
    assetName: "take.glb",
    clipName: "Take 001",
    durationSeconds: 1,
  });
  document.markers = [{ type: "RUN_CODE", time_seconds: 5 }];

  const result = validateReviewContract(document);
  assert.equal(result.valid, false);
  assert.equal(result.errors.length, 2);
});

test("keeps the checked-in JSON schema aligned with the browser contract", async () => {
  const schemaUrl = new URL(
    "../../../config/contracts/animation_review_contract.schema.json",
    import.meta.url,
  );
  const schema = JSON.parse(await readFile(schemaUrl, "utf8"));

  assert.equal(schema.properties.schema_version.const, REVIEW_SCHEMA_VERSION);
  assert.equal(schema.properties.kind.const, REVIEW_KIND);
  assert.equal(schema.properties.review_only.const, true);
  assert.equal(schema.properties.apply_to_gameplay.const, false);
  assert.equal(schema.properties.authority.const, "godot");
  assert.equal(schema.properties.authored_changes.maxItems, 0);
});
