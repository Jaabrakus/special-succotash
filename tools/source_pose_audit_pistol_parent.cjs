// Read-only source attachment evidence. Never writes source assets or profiles.
const fs = require('node:fs');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const base = '/Users/kiwimango/Downloads/SOCOM-II-animation-extractor';
const { archive } = require(base + '/extract.cjs');
const characterPath = base + '/output/readers/character.rdr.json';
const clibPath = base + '/output/mp1/CLIB_GEO.ZED';
const weaponPath = base + '/output/mp1/RUN_COMMON_WEAP_MDL.ZED';
const character = JSON.parse(fs.readFileSync(characterPath, 'utf8'));
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const namedRecords = [];
function visit(value) {
  if (!Array.isArray(value)) return;
  if (value[0] === 'name' && Array.isArray(value[1]) && value[1][0] === 'pistol') namedRecords.push(value);
  value.forEach(visit);
}
visit(character);
assert.equal(namedRecords.length, 1, 'One explicit pistol gear declaration');
const gear = namedRecords[0];
const offset = gear[gear.indexOf('ofs') + 1];
assert.equal(offset[0], 'rthigh', 'Configured gear attachment is thigh, not evidence of held parent');
const clib = fs.readFileSync(clibPath);
const entries = archive(clib).entries;
const hands = entries.filter(e => e.name === 'rhand');
const weaponNodes = entries.filter(e => ['pistol', 'rifle', 'weapon'].includes(e.name));
assert.equal(hands.length, 16);
assert.equal(weaponNodes.length, 0, 'Recovered CLIB has no held weapon helper child');
const weapons = fs.readFileSync(weaponPath);
const mark23 = archive(weapons).entries.find(e => e.name === 'a_mark23');
assert.ok(mark23, 'Original Mark 23 geometry entry exists');
const clips = ['seal_p_rstrafe_fast', 'seal_p_lstrafe_fast', 'seal_pfp_run'].map(name => {
  const path = '/private/tmp/socom-iso-motion-audit-20260912/motion/' + name + '.json';
  const raw = fs.readFileSync(path);
  const data = JSON.parse(raw);
  const helper = data.tracks.find(t => t.name === 'pistol');
  assert.ok(helper);
  assert.equal(helper.positions_raw.length, 1);
  assert.equal(helper.rotations_raw.length, 1);
  return { name, path, sha256: hash(raw), position_source_units: helper.positions_raw[0].map(x => x / 256), quaternion_xyzw_raw: helper.rotations_raw[0] };
});
console.log('SOURCE_PISTOL_PARENT ' + JSON.stringify({
  status: 'Explicit stowed gear parent recovered; held parent NOT recovered',
  held_parent: null,
  stowed_gear_record: { parent: offset[0], position: offset[1], rotation_degrees: offset[2], model: gear[gear.indexOf('model') + 1] },
  clib_right_hands: hands.map(e => ({ index: e.index, parentIndex: e.parentIndex, childProperties: entries.filter(c => c.parentIndex === e.index).map(c => c.name) })),
  clib_held_weapon_node_count: weaponNodes.length,
  mark23_model_entry: mark23,
  sources: [characterPath, clibPath, weaponPath].map(path => ({ path, sha256: hash(fs.readFileSync(path)) })),
  native_helpers: clips,
  interpretation: 'Do not apply this helper as world space or claim verified rhand space without runtime reparenting evidence. Gear rthigh declaration is not the held state.'
}));
console.log('SOURCE_PISTOL_PARENT PASS: read-only archive/config observation; held-parent recovery remains incomplete');
