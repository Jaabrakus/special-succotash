'use strict';
// Saved, reviewable runtime policy. Raw executable images remain research-only.
// Translation card: docs/SOURCE_FIREARM_RUNTIME.md.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p));
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const sourcePath = 'art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json';
const scalar = (record, tag) => {
  const fields = record.fields.filter(f => f.tag === tag);
  assert.equal(fields.length, 1, tag);
  assert.equal(fields[0].values.length, 1, tag);
  return fields[0].values[0];
};
const optionalScalar = (record, tag, fallback) => record.fields.some(f=>f.tag===tag) ? scalar(record,tag) : fallback;
// Only ordinary firearms whose classifier and names were verified. Source
// also classifies other equipment ONE_FRAME; this is not permission to enable it.
const ordinary = id => (id >= 4 && id <= 20) || (id >= 31 && id <= 40)
  || (id >= 51 && id <= 70) || (id >= 81 && id <= 85)
  || (id >= 91 && id <= 94) || (id >= 101 && id <= 108);
function build() {
  const bytes = read(sourcePath), source = JSON.parse(bytes);
  assert.equal(source.weapons.length, 86);
  const profiles = {};
  for (const name of fs.readdirSync(path.join(root, 'config/weapons')).filter(n=>n.endsWith('.json')).sort()) {
    const p = JSON.parse(read('config/weapons/' + name));
    if (!p.weapon_id || !p.ballistics || !p.reticle?.socom2_source_name) continue;
    const matches = source.weapons.filter(w => w.name === p.reticle.socom2_source_name);
    assert.equal(matches.length, 1, p.weapon_id);
    const record = matches[0], id = scalar(record, 'ID');
    assert(ordinary(id), 'Do not silently promote a non-firearm: ' + p.weapon_id + ' ' + id);
    assert(!profiles[p.weapon_id], 'Duplicate runtime identity');
    const ammoRows = record.fields.filter(f=>f.tag==='AMMO_TYPES');
    assert.equal(ammoRows.length,1);
    assert.equal(ammoRows[0].values.length,1);
    const ammoRow=ammoRows[0].values[0];
    assert.equal(ammoRow[0],'NAME');
    const ammoMatches=source.ammunition.filter(a=>a.name===ammoRow[1][0]);
    assert.equal(ammoMatches.length,1,'Exact ammo name, not duplicated source ID');
    const ammo=ammoMatches[0];
    const combat={ammo_name:ammo.name,impact_damage:scalar(ammo,'ImpactDamage'),
      damage_modifier:optionalScalar(record,'Damage_Modifier',0),piercing:scalar(ammo,'Piercing'),
      effective_range_m:scalar(record,'Effective_Range'),maximum_range_m:scalar(record,'Maximum_Range'),
      pellet_count:optionalScalar(ammo,'NumProjectilesFired',1)};
    assert(combat.pellet_count>=1 && combat.pellet_count<=32);
    profiles[p.weapon_id] = {source_name:record.name, source_id:id, source_record_index:record.index,combat};
  }
  assert.equal(Object.keys(profiles).length, 32);
  const damageBytes=read('config/reference/socom2_damage_vectors.json');
  const damageEvidence=JSON.parse(damageBytes);
  assert.equal(damageEvidence.fixture_count,42);
  const mp=damageEvidence.source.multiplayer_profiles;
  assert.equal(mp[0].name,'mp_seal'); assert.equal(mp[1].name,'mp_terror');
  assert.deepEqual(mp[0].health,mp[1].health); assert.deepEqual(mp[0].armor,mp[1].armor);
  const materials={UNKNOWN:0,PARTICLE_SYSTEM:1};
  for(const row of damageEvidence.source.material_rows){
    assert(!Object.hasOwn(materials,row.name));
    assert(Number.isFinite(row.PENETRATION)&&row.PENETRATION>=0&&row.PENETRATION<=1);
    materials[row.name]=row.PENETRATION;
  }
  return {schema_version:1, policy_id:'socom2_verified_one_frame_v1', mode:'one_frame',
    query_range_scale:1.1, strict_terminal_range:true, dispersion_distribution:'source_signed_square_axes_v1',
    rng_algorithm:'socom2_lcg64_rand31_v1',
    damage_model:'socom2_mp_regions_v1',multiplayer_defaults:{health:mp[0].health,armor:mp[0].armor},
    material_policy:'socom2_exact_name_range_v1',materials,
    scope:'Verified query/cutoff, LCG, signed-square direction algebra, ordinary firearm damage/armor/MP pools and pellet count. Accepted-shot seeds, bloom/projection, world-unit mapping and material continuation remain adapted; explosives and unsupported guns retain project rules.',
    source:{boot:'SCUS_972.75', module:'FTSCore', module_sha256:'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
      reader:sourcePath, reader_sha256:sha(bytes), classifier_pc:'0x3d1e20', segment_pc:'0x3ca998', cutoff_pc:'0x3c9d28',
      character_reader_sha256:damageEvidence.source.character_reader.sha256,damage_fixture_sha256:sha(damageBytes)}, profiles};
}
const output = JSON.stringify(build(), null, 2) + '\n';
const dest = path.join(root, 'config/source_firearm_policy.json');
if (process.argv.includes('--check')) {
  assert.equal(fs.readFileSync(dest, 'utf8'), output, 'Saved policy differs from verified explicit source links');
  console.log('SOURCE_FIREARM_POLICY_GENERATION PASS profiles=32');
} else {
  // This generator owns this single generated contract, never weapon profiles.
  fs.writeFileSync(dest, output);
  console.log('Wrote config/source_firearm_policy.json profiles=32');
}
