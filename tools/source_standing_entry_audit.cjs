'use strict';
// Offline original-instruction evidence. No runtime/profile/source-asset writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const PROJECT = path.resolve(__dirname, '..');
const READER = '/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers/animset.rdr.json';
const HASHES = {
  'FTSCore.bin': 'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
  'ZSealEtc.bin': 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1',
  animset_reader: '6462c387c3d452b19df2eddf3cbde5f7543f1e0c23070e6e8069cf554e785f64'
};
const B = 0x10000000, ACTOR = B, CLIP = B + 0x2000, FIELD = B + 0x2400;
const ITEM = B + 0x2500, STACK = B + 0x7000;
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const field = (row, key) => row.indexOf(key) < 0 ? null : row[row.indexOf(key) + 1];
function slice(m, first, stop) {
  m.pc = first; m.nextPC = first + 4; m.inDelaySlot = false;
  m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function audit() {
  const core = moduleImage('FTSCore.bin'), seal = moduleImage('ZSealEtc.bin');
  for (const im of [core, seal]) assert.equal(sha(im.bytes), HASHES[im.name]);
  const readerBytes = fs.readFileSync(READER);
  assert.equal(sha(readerBytes), HASHES.animset_reader);
  const rows = JSON.parse(readerBytes);
  const set = rows.find(r => field(r, 'anim_set_name')?.[0] === 'Seal anim set');
  const walk = field(set, 'anim_set_anims').find(r => field(r, 'type_name')?.[0] === 'Walk');
  const defaultWalk = field(walk, 'modes').find(r => r[0] === 'default')[1];
  assert.equal(defaultWalk, 'seal_walk_alert');
  const tablePointer = seal.bytes.readUInt32LE(seal.offset(0x661060 + 2 * 4));
  const tableOffset = seal.offset(tablePointer);
  const actionName = seal.bytes.subarray(tableOffset, seal.bytes.indexOf(0, tableOffset)).toString();
  assert.equal(actionName, 'Walk');
  const assetPath = path.join(PROJECT, 'assets/animations/seal_reference/seal_walk_alert.tres');
  const assetBytes = fs.readFileSync(assetPath), asset = assetBytes.toString();
  assert.match(asset, /^metadata\/source_name = "seal_walk_alert"$/m);
  const settings = /^metadata\/source_settings = \{([\s\S]*?)^\}/m.exec(asset)[1];
  assert.match(settings, /^"anim_name": "seal_walk_alert",$/m);
  assert.doesNotMatch(settings, /"BlendTime"\s*:/);
  const m = new FloatFixtureMachine({maxSteps: 5000});
  for (const im of [core, seal]) m.map(im.base, im.bytes, {execute: true, name: 'pinned original ' + im.name});
  const b = m.map(B, Buffer.alloc(0x8000), {write: true, name: 'disclosed synthetic actor, clip, parser result and stack'});
  const readerCases = [];
  for (const [kind, value] of [['absent', null], ['float', 0], ['float', .2], ['float', .5], ['integer', 1]]) {
    b.fill(0); m.set64(29, BigInt(STACK)); b.writeUInt32LE(CLIP, STACK - B + 264);
    // Stop at the original lookup call. Execute its delay-slot initialization,
    // but do not claim to execute the packed-reader lookup or substitute a stub.
    const prefixSteps = slice(m, 0x287f28, 0x287f40);
    m.step(); m.step();
    assert.equal(b.readUInt32LE(CLIP - B + 32), 0x3ecccccd);
    if (kind !== 'absent') {
      b[FIELD - B] = 4; b.writeUInt16LE(1, FIELD - B + 2); b.writeUInt32LE(ITEM, FIELD - B + 4);
      b[ITEM - B] = kind === 'integer' ? 1 : 2;
      if (kind === 'integer') b.writeInt32LE(value, ITEM - B + 4);
      else b.writeFloatLE(value, ITEM - B + 4);
    }
    // An explicit lookup-result input: null or a disclosed one-item scalar list.
    m.set64(2, BigInt(kind === 'absent' ? 0 : FIELD));
    const suffixSteps = slice(m, 0x287f48, 0x287fd0);
    const expected = Math.fround(kind === 'absent' ? .4 : value);
    assert.equal(b.readFloatLE(CLIP - B + 32), expected);
    m.set64(21, BigInt(CLIP)); m.set64(22, BigInt(ACTOR + 368));
    const timerSteps = slice(m, 0x28df70, 0x28df80);
    assert.equal(b.readFloatLE(376), expected); assert.equal(b.readFloatLE(380), expected);
    readerCases.push({kind, value, decoded_blend_seconds: expected, actor_remaining_376: expected,
      actor_duration_380: expected, steps: {prefix: prefixSteps + 2, reader_suffix: suffixSteps, timer_copy: timerSteps}});
  }
  const requests = [];
  for (const [first, actorRegister] of [[0x5855fc, 18], [0x5868ac, 19], [0x586b24, 19]]) {
    b.writeInt16LE(2, 372); m.set64(actorRegister, BigInt(ACTOR));
    const steps = slice(m, first, 0x588bc0);
    assert.equal(m.u32(4), BigInt(ACTOR)); assert.equal(m.u32(5), 2n);
    assert.equal(m.u32(6), 2n); assert.equal(m.u32(7), 0n); assert.equal(m.u32(8), 0n);
    requests.push({start: '0x' + first.toString(16), action_id: 2, action_name: actionName,
      disclosed_actor_field_372: 2, reverse_flag: 0, steps});
  }
  // The ordinary actor timer and curve execute original code. The full source
  // controller and render pose are deliberately outside this bounded fixture.
  const timings = [];
  for (const delta of [0, 1 / 60, .1, .2, .3, .4, .5]) {
    b.writeFloatLE(.4, 376); b.writeFloatLE(.4, 380); b.writeFloatLE(delta, 736);
    m.set64(17, BigInt(ACTOR)); m.set64(29, BigInt(STACK)); m.setFloat(2, 0);
    const steps = slice(m, 0x576898, 0x5768d4);
    const remaining = Math.max(0, Math.fround(Math.fround(.4) - Math.fround(delta)));
    assert.equal(b.readFloatLE(376), remaining);
    const x = Math.fround(remaining / Math.fround(.4));
    const ease = x <= .5 ? 2 * x * x : 1 - 2 * (x - 1) * (x - 1);
    assert(Math.abs(m.float(0) - ease) < 1e-6);
    timings.push({delta, remaining, old_weight: m.float(0), new_weight: 1 - m.float(0), steps});
  }
  return {schema_version: 1, status: 'PASS', source_hashes: HASHES, unknown_stubs: 0,
    reader_cases: readerCases, movement_entry_requests: requests, original_timer_cases: timings,
    provenance: {action_table_address: '0x661068', action: actionName, action_id: 2,
      default_walk: defaultWalk, reader: READER, asset: assetPath, asset_sha256: sha(assetBytes), blend_time_absent: true},
    source_ranges: {
      missing_blend_default_and_override: disasm(core, 0x287f28, 0x287fd0),
      movement_entry_gate: disasm(seal, 0x586ad8, 0x586b58),
      ordinary_entry_mode_resolution: disasm(seal, 0x588cf4, 0x588d60),
      queue_entry: disasm(seal, 0x5894f0, 0x589508),
      destination_blend_assignment: disasm(core, 0x28df70, 0x28df80),
      ordinary_actor_blend: disasm(seal, 0x576860, 0x576908),
      quadratic_curve: disasm(core, 0x2874f0, 0x287550)
    }, limitations: [
      'Original instruction slices with disclosed actor/parser-result records; packed-reader lookup, allocator, complete mode lookup and full controller are not executed.',
      'The entry gates and queue/mode call chain are static original-code evidence, not a whole playable actor frame.',
      'Default-mode rifle idle-to-standing entry only; no claim about readiness lifecycle, pistol remapping, crouch/prone entry, traversal, reload or death.',
      'Duration and quadratic weight only; outgoing snapshot, loop phase transfer and original procedural pose require separate integration/proof.',
      'Finite-normal scalar float32 fixture, not bit-exact R5900/VU hardware or rendered parity.',
      'No Godot runtime activation is performed by this audit.'
    ]};
}
if (require.main === module) {
  const result = audit(), outputArg = process.argv.find(x => x.startsWith('--output='));
  if (outputArg) {
    const output = path.resolve(outputArg.slice(9));
    assert(output.startsWith('/private/tmp/'), 'only a new temporary report is allowed');
    fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(`SOURCE_STANDING_ENTRY PASS reader=${result.reader_cases.length} entry=${result.movement_entry_requests.length} timer=${result.original_timer_cases.length} unknown_stubs=0`);
}
module.exports = {audit};
