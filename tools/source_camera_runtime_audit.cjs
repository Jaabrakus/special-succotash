'use strict';
// Offline original-instruction observer. Does not edit a Godot camera/profile.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const {extract} = require('./extract_iso_camera_reference.cjs');
const F = Math.fround;
const CAMERA = 0x10000000, ARRAY = 0x10002000, STACK = 0x10004000;
const DEFAULT_ISO = '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso';
const DEFAULT_DECODER = '/Users/kiwimango/Downloads/SOCOM-II-animation-extractor';
const HASHES = {
  'FTSCore.bin': 'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
  'ZSealEtc.bin': 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'
};
function slice(m, start, stop) {
  m.pc = start; m.nextPC = start + 4; m.inDelaySlot = false;
  m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function floats(bytes, offset, count) {
  return Array.from({length: count}, (_, i) => bytes.readFloatLE(offset + 4 * i));
}
function audit(iso = DEFAULT_ISO, decoder = DEFAULT_DECODER) {
  const core = moduleImage('FTSCore.bin'), seal = moduleImage('ZSealEtc.bin');
  for (const im of [core, seal]) assert.equal(crypto.createHash('sha256').update(im.bytes).digest('hex'), HASHES[im.name]);
  const reader = extract(iso, decoder);
  assert.equal(reader.source.entry_sha256, 'c09f0b84bd8b612d69b24df678a7b5ce8c1fb72a79706445939b7f6d0e6db0bc');
  const modes = ['back', 'side', 'first', 'peekl', 'peekr'].map((name, index) => ({
    index, name,
    offset_source: ['side', 'height', 'dist'].map(field => reader.parameters[`cam_${name}_${field}`]),
    aim_source: reader.parameters[`cam_${name}_aim`]
  }));
  const records = Buffer.alloc(modes.length * 24);
  for (const mode of modes) [...mode.offset_source, ...mode.aim_source].forEach((v, i) => {
    assert(Number.isFinite(v)); records.writeFloatLE(v, mode.index * 24 + i * 4);
  });
  function machine() {
    const m = new FloatFixtureMachine({maxSteps: 1000});
    m.map(core.base, core.bytes, {name: 'original FTSCore', execute: true});
    const camera = m.map(CAMERA, Buffer.alloc(2048), {name: 'synthetic camera owner', write: true});
    m.map(ARRAY, records, {name: 'verified decoded source camera records'});
    const globals = Buffer.alloc(8); globals.writeUInt32LE(modes.length); globals.writeUInt32LE(ARRAY, 4);
    m.map(0x44c404, globals, {name: 'synthetic source record count and pointer'});
    m.map(STACK, Buffer.alloc(4096), {name: 'bounded stack', write: true});
    m.set64(29, BigInt(STACK + 2048));
    return {m, camera};
  }
  const cases = [];
  {
    const {m, camera} = machine();
    camera[228] = 4; camera[321] = 4; m.set64(16, BigInt(CAMERA));
    const steps = slice(m, 0x29b3e0, 0x29b490);
    assert.equal(camera[228], 0); assert.equal(camera[320], 2); assert.equal(camera[321], 0);
    assert.deepEqual(floats(camera, 28, 3), modes[0].offset_source);
    assert.deepEqual(floats(camera, 4, 3), modes[0].aim_source);
    cases.push({name: 'camera setup resets preset to back', steps, preset: camera[228],
      offset_source: floats(camera, 28, 3), aim_source: floats(camera, 4, 3), norm: camera.readFloatLE(40)});
  }
  for (const mode of modes) {
    const {m, camera} = machine(); camera[228] = mode.index; m.set64(4, BigInt(CAMERA));
    const steps = slice(m, 0x29bdf0, 0x29bea0);
    assert.deepEqual(floats(camera, 28, 3), mode.offset_source);
    assert.deepEqual(floats(camera, 4, 3), mode.aim_source);
    assert.deepEqual(floats(camera, 16, 3), mode.aim_source);
    cases.push({name: `preset ${mode.name} selection`, steps, offset_source: floats(camera, 28, 3), aim_source: floats(camera, 4, 3)});
  }
  {
    const {m, camera} = machine(); m.set64(17, BigInt(CAMERA)); camera.writeFloatLE(4, 232);
    const steps = slice(m, 0x3191e8, 0x319208);
    const bits = Buffer.alloc(4); bits.writeUInt32LE(0x3f1c61aa);
    assert.equal(m.float(12), bits.readFloatLE()); assert.equal(m.u32(5), 1n);
    cases.push({name: 'world loader overrides stored half horizontal angle', steps,
      half_hfov_radians: m.float(12), full_hfov_degrees: m.float(12) * 360 / Math.PI,
      setter_call: '0x319268 -> 0x291490'});
  }
  for (const degrees of [70, 49, 90]) {
    const {m, camera} = machine(); m.set64(4, BigInt(CAMERA)); m.setFloat(12, degrees);
    const steps = slice(m, 0x2913f0, 0x291424);
    const b = Buffer.alloc(4); b.writeUInt32LE(0x3c8efa35);
    const expected = F(b.readFloatLE() * F(F(.5) * F(degrees)));
    assert.equal(camera.readFloatLE(224), expected);
    cases.push({name: `degree setter ${degrees}`, steps, degrees, half_hfov_radians: camera.readFloatLE(224)});
  }
  const scalar = bits => { const b = Buffer.alloc(4); b.writeUInt32LE(bits); return b.readFloatLE(); };
  for (const [root, lean] of [
    [[0, 0, 0], 0], [[0, 2, 0], 0], [[0, 3, 0], 0],
    [[0, 5.6, 0], 0], [[0, 10, 0], 0], [[.3, 18, 1.2], 0],
    [[0, 10, 0], -.75], [[0, 10, 0], .75]
  ]) {
    const {m, camera} = machine();
    const stack = m.region(STACK, 4096, 'write').bytes;
    root.forEach((v, i) => stack.writeFloatLE(v, 2048 + 288 + i * 4));
    const leanBytes = Buffer.alloc(4); leanBytes.writeFloatLE(lean);
    m.map(0x4161c0, leanBytes, {name: 'synthetic already-filtered source lean'});
    m.set64(19, BigInt(CAMERA + 512)); m.set64(18, BigInt(CAMERA + 528));
    const steps = slice(m, 0x29aa08, 0x29ab78);
    const [x, y, z] = root.map(F);
    const t = y >= scalar(0x40b33333) ? 1 : Math.max(0, Math.min(1, F(F(y - scalar(0x400ad36f)) * scalar(0x3e953c00))));
    const bonus = y === 0 ? 10 : F(F(4.5 * t) + 5.5);
    const expectedX = F(x + F(F(lean) * (lean < 0 ? 2.5 : scalar(0x40333333))));
    const expectedY = F(y + bonus), expectedZ = F(z + 28);
    const expectedRadius = F(Math.sqrt(F(F(expectedX * expectedX) + F(expectedZ * expectedZ))));
    assert.equal(camera.readFloatLE(512), expectedX);
    assert.equal(camera.readFloatLE(516), expectedY);
    assert.equal(camera.readFloatLE(528), expectedRadius);
    assert.deepEqual(floats(stack, 2048 + 288, 3), [expectedX, 0, expectedZ]);
    cases.push({name: 'active state-2 skeleton pivot and pre-orbit vector', root_source: root.map(F), lean: F(lean), steps,
      height_bonus: bonus, pivot_xy_source: floats(camera, 512, 2), back_source: floats(stack, 2048 + 288, 3), radius_source: camera.readFloatLE(528)});
  }
  for (const pitchDegrees of [-70, -30, 0, 25, 60]) {
    const {m, camera} = machine();
    const radians = pitchDegrees * Math.PI / 180, x = F(Math.sin(radians / 2)), w = F(Math.cos(radians / 2));
    [x, 0, 0, w].forEach((v, i) => camera.writeFloatLE(v, 768 + i * 4));
    const result = m.run(0x307170, {args: [CAMERA + 768, CAMERA + 800], stackPointer: STACK + 2048});
    const sourceBack = [camera.readFloatLE(832), camera.readFloatLE(836), camera.readFloatLE(840)];
    assert.deepEqual(sourceBack, [0, F(0 - F(w * F(x + x))), F(1 - F(x * F(x + x)))]);
    assert(Math.abs(sourceBack[1] + Math.sin(radians)) < 2e-7);
    assert(Math.abs(sourceBack[2] - Math.cos(radians)) < 2e-7);
    cases.push({name: 'original quaternion matrix confirms X pitch signs', pitch_degrees: pitchDegrees,
      quaternion_input: [x, 0, 0, w], positive_z_basis: sourceBack, steps: result.steps});
  }
  for (const [radius, unitY] of [[28, -.9], [28, -.5], [28, 0], [28, .5], [28, .9], [30, -.25]]) {
    const {m, camera} = machine(); camera.writeFloatLE(radius, 512);
    m.set64(18, BigInt(CAMERA + 512)); m.setFloat(0, F(Math.abs(unitY)));
    const steps = slice(m, 0x29ad28, 0x29ad4c);
    const expected = F(F(radius) + F(F(Math.abs(unitY)) * F(14 - F(radius))));
    assert.equal(camera.readFloatLE(512), expected);
    cases.push({name: 'active state-2 pitch radius collapse', radius_source: radius, normalized_back_y: unitY,
      supplied_abs_y: F(Math.abs(unitY)), collapsed_radius_source: camera.readFloatLE(512), steps});
  }
  assert.equal(core.bytes.readUInt32LE(core.offset(0x319268)), 0x0c0a4524, 'original setter call changed');
  return {
    schema_version: 1, status: 'PASS', original_instruction_cases: cases.length,
    domain: 'finite-normal host IEEE float32 fixture interpreter, not complete R5900 FPU',
    unknown_external_stubs: 0, source_hashes: HASHES, reader_source: reader.source,
    verified_camera_records: modes, fixtures: cases,
    source_ranges: {
      world_load_override: disasm(core, 0x3191d0, 0x319270),
      degree_setter: disasm(core, 0x2913f0, 0x291490),
      radians_setter: disasm(core, 0x291490, 0x291548),
      reset_preset: disasm(core, 0x29b3e0, 0x29b49c),
      select_preset: disasm(core, 0x29bdf0, 0x29bea0),
      first_record_reader: disasm(seal, 0x59c760, 0x59c888)
      , active_pivot: disasm(core, 0x29aa08, 0x29ab78)
      , active_pitch_radius: disasm(core, 0x29ad20, 0x29ad54)
      , original_pitch_quaternion: disasm(seal, 0x5af470, 0x5af500)
      , original_quaternion_matrix: disasm(core, 0x307170, 0x307270)
    },
    limits: [
      'The loader establishes default HFOV, not all current zoom/projection scale states.',
      'Camera record selection is executed; full pose, collision, transition and scope solvers are not.',
      'Active-pivot fixtures inject model-local skel_root and filtered lean. Quaternion-matrix fixtures inject sine/cosine values, not the original trigonometric generator. Radius fixtures inject abs(normalized-back-Y).',
      'cam_full entries occur in source reader data but are not among the five appended runtime presets.',
      'No current Godot camera settings or gameplay behavior are changed by this observer.'
    ]
  };
}
if (require.main === module) {
  const report = audit();
  if (process.argv[2]) {
    const output = path.resolve(process.argv[2]);
    assert(output.startsWith('/private/tmp/'), 'new temporary report only');
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(`SOURCE_CAMERA_RUNTIME_AUDIT PASS original_cases=${report.original_instruction_cases} presets=5 unknown_stubs=0`);
}
module.exports = {audit};
