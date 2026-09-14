'use strict';
// Offline source observer only. Never loads a Godot scene or writes runtime data.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const PROJECT = path.resolve(__dirname, '..');
const READERS = '/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers';
const SEAL_SHA = 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1';
const READER_SHAS = {
  animset: '6462c387c3d452b19df2eddf3cbde5f7543f1e0c23070e6e8069cf554e785f64',
  motion: 'ac1a191449bb18f9c59916d516cf1ea435ab59cf6e80aa38b961995c1489d7fa',
  motion_range: 'dcf39bb12da39f6fee0a4229617624e8dea32bab146e9ce250d9f208af6f0fd3'
};
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const hex = a => '0x' + a.toString(16);
function field(row, name) {
  assert(Array.isArray(row), 'reader row must be an array');
  const i = row.indexOf(name);
  return i < 0 || !Array.isArray(row[i + 1]) ? null : row[i + 1];
}
function source(file) {
  const bytes = fs.readFileSync(file);
  return {file, sha256: sha(bytes), bytes: bytes.length};
}
function stringAt(image, address) {
  const offset = image.offset(address), end = image.bytes.indexOf(0, offset);
  assert(end >= offset && end - offset < 160, 'bounded original string');
  return image.bytes.subarray(offset, end).toString();
}
function slice(machine, start, stop) {
  machine.pc = start; machine.nextPC = start + 4; machine.inDelaySlot = false;
  machine.steps = 0; machine.lastPCs = [];
  while (machine.pc !== stop) machine.step();
  return machine.steps;
}
function weightedFixture(image, weights, randomInteger) {
  assert(weights.length >= 2 && weights.length <= 8);
  assert(weights.every(x => Number.isFinite(x) && x >= 0));
  assert(Number.isInteger(randomInteger) && randomInteger >= 0 && randomInteger <= 0x7fffffff);
  const base = 0x10000000, bytes = Buffer.alloc(256);
  weights.forEach((weight, index) => {
    bytes.writeUInt32LE(100 + index, index * 8);
    bytes.writeFloatLE(weight, index * 8 + 4);
  });
  const machine = new FloatFixtureMachine({maxSteps: 256});
  machine.map(image.base, image.bytes, {execute: true, name: 'hash-pinned original ZSealEtc'});
  machine.map(base, bytes, {name: 'disclosed synthetic mode-choice IDs and original reader weights'});
  machine.set64(2, BigInt(randomInteger));
  machine.set64(16, BigInt(weights.length));
  machine.set64(17, BigInt(base));
  machine.setFloat(20, 0);
  // Begins after the actual RNG call: the RNG output is an explicit fixture input,
  // not an unknown-function stub or a claim to execute the full actor controller.
  const steps = slice(machine, 0x5e59dc, 0x5e5a90);
  const normalized = Math.fround(Math.fround(randomInteger) * 2 ** -31);
  let cumulative = 0, expectedIndex = weights.length - 1;
  for (let i = 0; i < weights.length; i++) {
    cumulative = Math.fround(cumulative + Math.fround(weights[i]));
    if (normalized <= cumulative) { expectedIndex = i; break; }
  }
  const chosenIndex = Number(machine.u32(2)) - 100;
  assert.equal(chosenIndex, expectedIndex, 'original <= cumulative weighted-choice equation');
  return {weights, randomInteger, normalized, chosenIndex, steps};
}
function metadata(resource) {
  const relative = resource.replace(/^res:\/\//, '');
  const file = path.join(PROJECT, relative);
  if (!resource.startsWith('res://') || !file.startsWith(PROJECT + path.sep) || !fs.existsSync(file)) return {resource, missing: true};
  if (!file.endsWith('.tres')) return {resource, kind: path.extname(file).slice(1), source_name: null};
  const text = fs.readFileSync(file, 'utf8');
  const name = /^metadata\/source_name = "([^"]+)"$/m.exec(text)?.[1] || null;
  const base = /^metadata\/seal_composite_base = "([^"]+)"$/m.exec(text)?.[1] || null;
  const coverage = /^metadata\/source_coverage = "([^"]+)"$/m.exec(text)?.[1] || null;
  const number = key => {
    const match = new RegExp('^' + key + ' = ([0-9.eE+-]+)$', 'm').exec(text);
    return match ? Number(match[1]) : null;
  };
  return {resource, sha256: sha(Buffer.from(text)), source_name: name, composite_base: base,
    source_coverage: coverage, length_seconds: number('length'), loop_mode: number('loop_mode')};
}
function proneDirectionFixtures(image) {
  const base = 0x10000000, actor = base + 0x100, control = base + 0x2000;
  const cases = [];
  for (const input of [-1, -0.4, 0.4, 1]) {
    const machine = new FloatFixtureMachine({maxSteps: 128});
    machine.map(image.base, image.bytes, {execute: true, name: 'original prone selector'});
    const data = machine.map(base, Buffer.alloc(0x3000), {write: true, name: 'disclosed actor/control fixtures'});
    const write = (address, value) => data.writeFloatLE(value, address - base);
    // Dominant longitudinal channel, after the original ratio test. s0=0 means
    // classifier must not replace analog magnitude with digital +/-1.
    write(control, input); write(control + 4, 0);
    machine.set64(19, BigInt(actor)); machine.set64(17, BigInt(control));
    machine.set64(18, BigInt(control + 4)); machine.set64(16, 0n);
    const classifierSteps = slice(machine, 0x585944, 0x585cb0);
    const directionID = data.readInt16LE(actor - base + 4920);
    assert.equal(directionID, input > 0 ? 1 : 3);
    assert.equal(data.readFloatLE(control - base), Math.fround(input));
    machine.set64(17, BigInt(actor)); machine.setFloat(24, input); machine.setFloat(23, 0);
    const axisSteps = slice(machine, 0x583590, 0x5835f0);
    assert.equal(machine.float(24), Math.fround(input)); assert.equal(machine.float(23), 0);
    // Exact action request is identical for both signs; no backward file lookup.
    const selectSteps = slice(machine, 0x583720, 0x588bc0);
    assert.equal(machine.u32(5), 27n); assert.equal(machine.u32(6), 2n);
    machine.setFloat(24, input); machine.setFloat(22, Math.abs(input)); machine.setFloat(20, 0);
    const signSteps = slice(machine, 0x583900, 0x583910);
    assert.equal(machine.float(22), Math.fround(input));
    cases.push({input, directionID, actionID: 27, actionName: 'Prone crawl', signedPlaybackFactor: machine.float(22),
      originalSteps: {classifierSteps, axisSteps, selectSteps, signSteps}});
  }
  assert.equal(stringAt(image, 0x6619e0), 'Prone rstrafe');
  assert.equal(stringAt(image, 0x661a08), 'Prone lstrafe');
  return cases;
}
function audit() {
  const image = moduleImage('ZSealEtc.bin');
  assert.equal(sha(image.bytes), SEAL_SHA);
  const readers = {};
  for (const name of ['animset', 'motion', 'motion_range']) {
    const file = path.join(READERS, name + '.rdr.json');
    readers[name] = {...source(file), data: JSON.parse(fs.readFileSync(file))};
    assert.equal(readers[name].sha256, READER_SHAS[name], 'pinned source reader ' + name);
  }
  const sealRows = readers.animset.data.filter(x => field(x, 'anim_set_name')?.[0] === 'Seal anim set');
  assert.equal(sealRows.length, 1, 'unique original SEAL action set');
  const actionRows = field(sealRows[0], 'anim_set_anims');
  const actions = actionRows.filter(r => /^(Stand|Fire |Pistol |Step|Walk|Jog|Run|Strafe|180|Crouch|Prone)/.test(field(r, 'type_name')?.[0] || ''));
  const mode = (action, name) => field(actions.find(x => field(x, 'type_name')[0] === action), 'modes').find(x => x[0] === name);
  const readyWeights = mode('Stand', 'ready').slice(1).map(x => x[1]);
  const crouchWeights = mode('Crouch', 'default').slice(1).map(x => x[1]);
  assert.deepEqual(readyWeights, [0.5, 0.5]);
  assert.deepEqual(crouchWeights, [Math.fround(0.3), Math.fround(0.3), Math.fround(0.4)]);
  const samples = new Set([0, 1, 0x7ffffffe, 0x7fffffff]);
  for (const fraction of [0.3, 0.5, 0.6, 0.7]) {
    const edge = Math.floor(Math.fround(fraction) * 2 ** 31);
    for (const delta of [-129, -1, 0, 1, 129]) if (edge + delta <= 0x7fffffff) samples.add(edge + delta);
  }
  const weightedChoices = [readyWeights, crouchWeights, [0.2, 0.1]].flatMap(weights =>
    [...samples].sort((a, b) => a - b).map(random => weightedFixture(image, weights, random)));
  // The third row deliberately underfills the CDF to prove original last-entry fallback.
  assert.equal(weightedChoices.at(-1).chosenIndex, 1);
  const proneDirections = proneDirectionFixtures(image);
  const actionTable = [];
  for (let index = 0; index <= 119; index++) {
    const address = 0x661060 + index * 4;
    const string_address = image.bytes.readUInt32LE(image.offset(address));
    actionTable.push({index, table_address: hex(address), string_address: hex(string_address), name: stringAt(image, string_address)});
  }
  for (const [index, name] of [[1, 'Stand'], [17, 'Stand -> Crouch'], [19, 'Crouch -> Prone'],
    [25, 'Stand -> Prone'], [27, 'Prone crawl'], [83, 'Pistol stand'], [89, 'Pistol jog'], [90, 'Pistol run']]) {
    assert.equal(actionTable[index].name, name);
  }
  const motionRows = field(readers.motion.data, 'animations');
  assert.equal(motionRows.length, 398);
  const motionSettings = motionRows.filter(r => field(r, 'anim_name')?.[0].startsWith('seal_'));
  const mapFile = path.join(PROJECT, 'config/operator_animation_map.json');
  const map = JSON.parse(fs.readFileSync(mapFile));
  const configuredClips = Object.fromEntries(Object.entries(map.clips).map(([logical, resource]) => [logical, metadata(resource)]));
  const slots = {};
  for (const family of ['TWO_HAND_RIFLE', 'TWO_HAND_PISTOL']) {
    slots[family] = Object.fromEntries(Object.entries(map.family_animation_slots[family]).map(([slot, logical]) =>
      [slot, {logical, ...(configuredClips[logical] || {missing: true})}]));
  }
  const files = ['scripts/player/operator_locomotion_blend_tree.gd', 'scripts/player/operator_locomotion_route_builder.gd',
    'scripts/player/operator_source_locomotion_policy.gd', 'scripts/player/operator_animation_driver_actions.gd',
    'scripts/player/operator_animation_driver_runtime.gd', 'scripts/player/operator_animation_driver_api.gd'];
  return {schema_version: 1, status: 'PASS: source evidence and original weighted-choice fixtures; not full-game parity',
    original_module_sha256: SEAL_SHA, reader_sources: Object.fromEntries(Object.entries(readers).map(([k, v]) => [k, {file: v.file, sha256: v.sha256, bytes: v.bytes}])),
    action_count: actions.length, complete_source_actions: actions, complete_source_motion_settings: motionSettings,
    original_action_table: actionTable, weighted_choice_cases: weightedChoices.length, weightedChoices, unknown_stubs: 0,
    prone_direction_cases: proneDirections,
    runtime_snapshot: {profile: source(mapFile), source_files: files.map(f => source(path.join(PROJECT, f))),
      family_slots: slots, configured_clips: configuredClips, locomotion: map.locomotion,
      semantic_actions: map.semantic_actions, state_rules: map.state_rules},
    source_code: {
      fixed_action_index_registration: disasm(image, 0x5e324c, 0x5e329c),
      original_mode_selection: disasm(image, 0x5e5970, 0x5e5aa8),
      active_mode_change_and_default_fallback: disasm(image, 0x57d710, 0x57d800),
      action_change_snapshot_and_source_blend_time: disasm(image, 0x582fa0, 0x582ff8)
      ,prone_control_input_and_classifier: disasm(image, 0x584680, 0x5846a8)
      ,prone_classifier_call: disasm(image, 0x584798, 0x5847b4)
      ,prone_controller_call: disasm(image, 0x584abc, 0x584ad0)
      ,original_signed_control_classifier: disasm(image, 0x585944, 0x585998)
      ,prone_action_and_signed_clock: disasm(image, 0x583588, 0x583930)
      ,prone_lateral_name_registration: disasm(image, 0x5e24b4, 0x5e24f8)
    },
    limitations: [
      'Original weighted-choice slice receives a disclosed integer RNG result; it does not execute a whole player controller or alter global RNG.',
      'Configured clips and family slots are static provenance, not proof their route is reachable in the running scene.',
      'Source action registration and saved recipe do not by themselves establish input/state priorities or stance reverse-playback rules.',
      'No inference that transition_speed_A/B are time in seconds; no movement/weapon timing changes authorized by source metadata.',
      'Godot blend law, posture crossfade and source procedural aim remain separate audits. No visual parity claim or native launch.'
    ]};
}
if (require.main === module) {
  const report = audit(), arg = process.argv.find(x => x.startsWith('--output='));
  if (arg) {
    const output = path.resolve(arg.slice(9));
    assert(output.startsWith('/private/tmp/'), 'write reports only to new temporary paths');
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  }
  console.log(`SOURCE_ANIMATION_SELECTION PASS actions=${report.action_count} motion_records=398 weighted_choices=${report.weighted_choice_cases} prone_directions=${report.prone_direction_cases.length} unknown_stubs=0`);
}
module.exports = {audit, weightedFixture, metadata, proneDirectionFixtures};
