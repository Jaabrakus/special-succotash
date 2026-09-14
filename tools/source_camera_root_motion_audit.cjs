'use strict';
// Offline observer: original scalar code only; no game, profile or source-asset writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const ROOT = 0x10000000, ACTOR = ROOT + 0x100, STACK = ROOT + 0x4000;
const BATCH = ROOT + 0x7000, ENTRY = BATCH + 0x100, POSE = BATCH + 0x200, PARTS = BATCH + 0x400;
const MOTION = '/private/tmp/socom-iso-motion-audit-20260912/motion';
const HASHES = {
  'FTSCore.bin': 'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
  'ZSealEtc.bin': 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'
};
function sha(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
function read3(b, p) { return [0, 4, 8].map(i => b.readFloatLE(p + i)); }
function write3(b, p, v) { v.forEach((x, i) => b.writeFloatLE(x, p + i * 4)); }
function slice(m, first, stop) {
  m.pc = first; m.nextPC = first + 4; m.inDelaySlot = false; m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function audit(directory = MOTION) {
  const seal = moduleImage('ZSealEtc.bin'), core = moduleImage('FTSCore.bin');
  for (const im of [seal, core]) assert.equal(sha(im.bytes), HASHES[im.name]);
  const m = new FloatFixtureMachine({maxSteps: 2000});
  m.map(seal.base, seal.bytes, {execute: true, name: 'original ZSealEtc'});
  const b = m.map(ROOT, Buffer.alloc(0x8000), {write: true, name: 'synthetic bounded actor and pose inputs'});
  const count = Buffer.alloc(4); count.writeUInt32LE(2);
  m.map(0x3de1e8, count, {name: 'synthetic two-part skeleton count'});
  const at = address => address - ROOT;
  b.writeUInt32LE(ROOT, at(ACTOR) + 744);
  b.writeUInt32LE(PARTS, at(ACTOR) + 468);
  b.writeUInt32LE(ROOT, at(PARTS));
  b.writeUInt32LE(ROOT + 0x50, at(PARTS) + 4);
  b.writeUInt32LE(ACTOR, at(BATCH) + 4); b.writeUInt32LE(ENTRY, at(BATCH) + 8);
  b.writeUInt32LE(POSE, at(ENTRY) + 4);
  const sentinel = [5, 6, 7];
  const samples = [], sources = [];
  for (const name of ['seal_stand', 'seal_crouch', 'seal_prone', 'seal_run', 'seal_walk', 'seal_p_stand', 'seal_jog', 'seal_runningjump_launch']) {
    const file = path.join(directory, name + '.json');
    if (!fs.existsSync(file)) { sources.push({name, status: 'not present under this source name'}); continue; }
    const bytes = fs.readFileSync(file), clip = JSON.parse(bytes);
    const track = clip.tracks.find(x => x.name === 'skel_root');
    assert(track && track.positions_raw.length > 0, `${name}: expected source root channel`);
    sources.push({name, file, sha256: sha(bytes), frames: clip.frames, samples: clip.samples,
      positions: track.positions_raw.length, duration: clip.duration});
    // All original keys, not only the first key that happened to reproduce the problem.
    for (let frame = 0; frame < track.positions_raw.length; frame++) {
      const raw = track.positions_raw[frame].map(v => v / 256);
      b.fill(0, at(POSE), at(POSE) + 64);
      write3(b, at(POSE), raw); b.writeInt16LE(0, at(POSE) + 12); b.writeFloatLE(1, at(POSE) + 28);
      write3(b, at(POSE) + 32, sentinel); b.writeInt16LE(1, at(POSE) + 44); b.writeFloatLE(1, at(POSE) + 60);
      b.writeUInt32LE(1, at(BATCH));
      const apply = m.run(0x577700, {args: [BATCH], stackPointer: STACK + 2048});
      assert.deepEqual(read3(b, 0), raw, 'original sampled-pose copy must retain raw root first');
      assert.deepEqual(read3(b, 0x50), sentinel, 'non-root part copy');
      const getter = m.run(0x553db0, {args: [ACTOR], stackPointer: STACK + 2048});
      assert.equal(getter.value, BigInt(ROOT));
      m.set64(17, BigInt(ACTOR)); m.set64(2, BigInt(ROOT)); m.set64(29, BigInt(STACK + 2048));
      write3(b, at(ACTOR) + 5312, [-2, 4, 9]);
      const cacheSteps = slice(m, 0x57b028, 0x57b064);
      assert.deepEqual(read3(b, at(ACTOR) + 5312), raw, 'raw sample cached before compensation');
      assert.deepEqual(read3(b, at(STACK) + 2048 + 200), [-2, 4, 9], 'previous sample retained for delta');
      const clearSteps = slice(m, 0x57b1d0, 0x59b870);
      assert.deepEqual(read3(b, 0), [0, raw[1], 0], 'original instructions remove X/Z, preserve Y');
      assert.deepEqual(read3(b, at(ACTOR) + 5312), raw, 'cached raw travel must remain intact');
      assert.deepEqual(read3(b, 0x50), sentinel, 'compensation cannot alter hips/other body parts');
      assert.equal(m.u32(4), BigInt(ACTOR));
      assert.equal(m.u32(5), BigInt(STACK + 2048 + 200));
      samples.push({clip: name, frame, raw_source: raw, post_horizontal_compensation: read3(b, 0),
        original_steps: {pose_copy: apply.steps, root_getter: getter.steps, cache: cacheSteps, clear: clearSteps}});
    }
  }
  assert(samples.some(x => x.clip === 'seal_run' && x.raw_source[2] === 28.25390625));
  const vertical = [];
  for (const flag of [0, 2]) {
    write3(b, 0, [0, 10.3046875, 0]);
    write3(b, at(STACK) + 200, [3, 11, 4]); b.writeFloatLE(20, at(ACTOR) + 740);
    b[at(ACTOR) + 4193] = flag;
    m.set64(18, BigInt(ACTOR)); m.set64(16, BigInt(ROOT)); m.set64(17, BigInt(STACK + 200));
    const steps = slice(m, 0x59b9b0, 0x59b9e0);
    assert.equal(b.readFloatLE(4), 10.3046875);
    assert.equal(b.readFloatLE(at(ACTOR) + 740), flag ? 20.6953125 : 20);
    vertical.push({name: 'ordinary vertical control flag', flag, steps, root_y: b.readFloatLE(4),
      entity_field_740: b.readFloatLE(at(ACTOR) + 740)});
  }
  // This deliberately starts AFTER the special animation lookup. It verifies the write,
  // not the complete state resolver. Ladderslide's name/ID setter is separately hashed.
  write3(b, 0, [0, 4, 0]); m.set64(16, BigInt(ROOT)); m.set64(2, 1n);
  const ladderSteps = slice(m, 0x59b998, 0x59ba58);
  const expectedLadder = Buffer.alloc(4); expectedLadder.writeUInt32LE(0x41370a3e);
  assert.equal(b.readFloatLE(4), expectedLadder.readFloatLE());
  const ladderNameOffset = seal.offset(0x6620c8);
  assert.equal(seal.bytes.subarray(ladderNameOffset, seal.bytes.indexOf(0, ladderNameOffset)).toString(), 'Ladderslide');
  vertical.push({name: 'Ladderslide lookup-success branch', steps: ladderSteps, injected_lookup_result: 1, root_y: b.readFloatLE(4)});
  return {schema_version: 1, status: 'PASS', source_hashes: HASHES, sources,
    sample_cases: samples.length, vertical_slice_cases: vertical.length, unknown_stubs: 0,
    formula: 'ordinary post-sampling root = (0, sampledRootY, 0), before transition blend and optional procedural effects',
    samples, vertical,
    source_ranges: {
      sampled_pose_copy: disasm(seal, 0x577700, 0x5777cc),
      current_root_getter: disasm(seal, 0x553db0, 0x553db8),
      update_call_and_linked_exceptions: disasm(seal, 0x57af40, 0x57b028),
      retain_raw_translation: disasm(seal, 0x57b028, 0x57b064),
      remove_horizontal_translation: disasm(seal, 0x57b0a8, 0x57b1e4),
      vertical_handler: disasm(seal, 0x59b870, 0x59ba78),
      ladder_name_registration: disasm(seal, 0x5e2b1c, 0x5e2b30),
      hierarchical_camera_point: disasm(core, 0x2869d0, 0x286b80),
      normalize_orientation_not_position: disasm(seal, 0x5480cc, 0x5483a8)
    },
    limits: [
      'Original pose copy and horizontal compensation execute unmodified instructions; scalar-slice entry inputs are synthetic and disclosed.',
      'Raw track decoding/interpolation is supplied by the existing verified extraction; this test injects decoded per-key values into the original pose-copy buffer.',
      'Linked/attached actors bypass the ordinary path; no claim of their world-space parity.',
      'The Y handler has additional actor-baseline effects. Jump root height plus current Godot jump physics is not proven exact by this offline observer.',
      'Transitions, optional original procedural effects, collision and camera trailing are not executed here.',
      'Finite-normal IEEE float32 scalar harness is not a full R5900 FPU/VU emulator.'
    ]};
}
if (require.main === module) {
  const report = audit();
  const arg = process.argv.find(x => x.startsWith('--output='));
  if (arg) {
    const output = path.resolve(arg.slice('--output='.length));
    assert(output.startsWith('/private/tmp/'), 'only a new temporary report may be generated');
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(`SOURCE_CAMERA_ROOT_MOTION PASS samples=${report.sample_cases} vertical_slices=${report.vertical_slice_cases} unknown_stubs=0`);
}
module.exports = {audit};
