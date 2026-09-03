import test from "node:test";
import assert from "node:assert/strict";

import { GRENADE, WEAPON } from "../src/gameplay-config.js";
import {
  blastDamage,
  bloomAfterShot,
  canonicalBoneName,
  grenadeSpeed,
  recoverBloom,
  resolveAxis,
  spreadDegrees,
} from "../src/simulation.js";

test("normalizes FBX and GLB Mixamo bone names to the same animation key", () => {
  assert.equal(canonicalBoneName("mixamorigHips"), "hips");
  assert.equal(canonicalBoneName("mixamorig:Hips_64"), "hips");
  assert.equal(canonicalBoneName("mixamorig:RightHand_47"), "righthand");
});

test("rifle bloom uses the tuned standing and crouched limits", () => {
  assert.equal(bloomAfterShot(1.3, false, WEAPON), 1.45);
  assert.equal(bloomAfterShot(0.9, true, WEAPON), 1);
  assert.ok(Math.abs(recoverBloom(0.5, 14, 0.02) - 0.22) < 1e-9);
});

test("movement spread reaches the tuned full-gait value before bloom", () => {
  assert.equal(spreadDegrees({ speedRatio: 1, crouched: false, bloom: 0 }, WEAPON), 1.45);
  assert.equal(spreadDegrees({ speedRatio: 0, crouched: false, bloom: 0 }, WEAPON), 0.32);
});

test("grenade charge and blast falloff stay bounded", () => {
  assert.equal(grenadeSpeed(-1, GRENADE), 9);
  assert.equal(grenadeSpeed(2, GRENADE), 16);
  assert.equal(blastDamage(0, GRENADE), 120);
  assert.equal(blastDamage(7, GRENADE), 0);
});

test("circle collision resolves outside an expanded wall", () => {
  const boxes = [{ min: { x: 1, z: -1 }, max: { x: 2, z: 1 } }];
  const position = { x: 1.1, z: 0 };
  assert.equal(resolveAxis(position, 0.3, boxes, "x"), 0.7);
});
