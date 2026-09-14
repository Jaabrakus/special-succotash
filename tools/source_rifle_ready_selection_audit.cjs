'use strict';
// Offline original-instruction observer. No gameplay, profile or asset writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const SHA = 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1';
const ROOT = 0x10000000, RECORDS = ROOT + 0x100, ACTOR = ROOT + 0x2000;
const STACK = ROOT + 0x7000, TABLE = 0x66ad00;
function callers(im, target) {
  const result = [];
  for (let pc = im.base; pc < im.base + im.bytes.length - 4; pc += 4) {
    const w = im.bytes.readUInt32LE(im.offset(pc));
    if ((w >>> 26) === 3 && (w & 0x3ffffff) * 4 === target) result.push(pc);
  }
  return result;
}
function slice(m, start, stop) {
  m.pc = start; m.nextPC = start + 4; m.inDelaySlot = false; m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function audit() {
  const im = moduleImage('ZSealEtc.bin');
  assert.equal(crypto.createHash('sha256').update(im.bytes).digest('hex'), SHA);
  const stringAt = pc => {
    const off = im.offset(pc);
    return im.bytes.subarray(off, im.bytes.indexOf(0, off)).toString();
  };
  const names = [[0x65cbc0, 'bored02'], [0x65cbc8, 'bored03'], [0x65cbd0, 'suspicious'],
    [0x65cbe0, 'ready'], [0x65cbe8, 'conversation']];
  for (const [pc, name] of names) assert.equal(stringAt(pc), name);
  const direct = {};
  for (const name of ['ZSealEtc.bin', 'FTSCore.bin']) {
    const image = name === 'ZSealEtc.bin' ? im : moduleImage(name);
    direct[name] = {
      mode_setter_57d710: callers(image, 0x57d710),
      mode_wrapper_58c5d0: callers(image, 0x58c5d0),
      controller_mode_5605a0: callers(image, 0x5605a0)
    };
  }
  assert.deepEqual(direct['ZSealEtc.bin'].mode_setter_57d710, [0x58c5e4]);
  assert.deepEqual(direct['ZSealEtc.bin'].mode_wrapper_58c5d0, [0x56076c, 0x5607a8, 0x5607e8]);
  assert.deepEqual(direct['FTSCore.bin'].mode_setter_57d710, []);
  assert.deepEqual(direct['FTSCore.bin'].mode_wrapper_58c5d0, []);
  const m = new FloatFixtureMachine({maxSteps: 1000});
  m.map(im.base, im.bytes, {execute: true, name: 'original ZSealEtc read-only'});
  const b = m.map(ROOT, Buffer.alloc(0x8000), {write: true, name: 'disclosed synthetic fixture records'});
  b[4] = 2; b.writeUInt32LE(RECORDS, 8);
  b[0x100] = 0; b[0x101] = 1; b.writeUInt16LE(7 << 2, 0x102);
  b[0x104] = 55; b[0x105] = 1; b.writeUInt16LE(17 << 2, 0x106);
  const lookup = [];
  for (const [mode, expected] of [[0, 7], [55, 17], [33, -1]]) {
    const r = m.run(0x5e5970, {args: [ROOT, mode], stackPointer: STACK});
    assert.equal(BigInt.asIntN(32, r.value), BigInt(expected));
    lookup.push({synthetic_mode_id: mode, expected_synthetic_clip_index: expected, steps: r.steps});
  }
  // Actual mode identifiers are registered dynamically. Distinct sentinels make
  // index selection testable without pretending these are original registry IDs.
  const table = Buffer.alloc(28);
  const sentinels = [0, 22, 22, 33, 44, 55, 66];
  sentinels.forEach((v, i) => table.writeUInt32LE(v, i * 4));
  m.map(TABLE, table, {name: 'synthetic runtime registration results'});
  const requests = [];
  for (const request of [0, 2, 3, 4, 5, 6]) {
    b.writeInt16LE(-1, ACTOR - ROOT + 4918);
    m.set64(17, BigInt(ACTOR)); m.set64(3, BigInt(request));
    const steps = slice(m, 0x5607c8, 0x58c5d0);
    assert.equal(m.u32(4), BigInt(ACTOR));
    assert.equal(m.u32(5), BigInt(sentinels[request]));
    requests.push({controller_request: request, synthetic_registered_mode_id: sentinels[request], steps});
  }
  return {status: 'PASS', source_sha256: SHA, original_lookup_cases: lookup.length,
    original_request_slice_cases: requests.length, unknown_stubs: 0, names, direct_calls: direct, lookup, requests,
    source_ranges: {
      mode_registration: disasm(im, 0x574e10, 0x574edc),
      reset_on_animation_set_change: disasm(im, 0x58c428, 0x58c458),
      mode_setter: disasm(im, 0x57d710, 0x57d7f0),
      mode_lookup: disasm(im, 0x5e5970, 0x5e5aa8),
      controller_awareness_choice: disasm(im, 0x570b70, 0x570cc8)
    },
    limits: ['Synthetic mode records and registered IDs; original instructions, not a whole live game frame.',
      'No random weighted branch fixture; that branch is retained as static original code evidence.',
      'Direct-call scan does not prove absence of computed indirect calls or other loaded modules.',
      'Ordinary playable actor default/ready policy remains unverified; no runtime activation justified by this report alone.']};
}
if (require.main === module) {
  const r = audit(), arg = process.argv.find(x => x.startsWith('--output='));
  if (arg) {
    const file = path.resolve(arg.slice(9));
    assert(file.startsWith('/private/tmp/'), 'only a new temporary report may be generated');
    fs.writeFileSync(file, JSON.stringify(r, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(`SOURCE_RIFLE_READY_SELECTION PASS lookup=${r.original_lookup_cases} request_slices=${r.original_request_slice_cases} unknown_stubs=0`);
}
module.exports = {audit};
