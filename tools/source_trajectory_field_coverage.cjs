'use strict';
// Offline observer. See docs/SOURCE_TRAJECTORY_FIELD_COVERAGE.md.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {ammoNames} = require('./source_weapon_catalog_join.cjs');
const ROOT = path.resolve(__dirname, '..');
const SOURCE = 'art_source/socom2_ballistics_reference_20260912/weapon_reader_full.json';
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const values = (r, tag) => r.fields.filter(f => f.tag === tag).map(f => f.values);
const scalar = (r, tag) => {
  const a = values(r, tag);
  return a.length === 1 && a[0].length === 1 ? a[0][0] : null;
};
const idFields = r => values(r, 'ID');
const reference = r => ({name:r.name, source_index:r.index, context:r.context, ids:idFields(r)});
const near = (a,b) => Number.isFinite(a) && Number.isFinite(b) && Math.abs(a-b) <= 1e-8 * Math.max(1,Math.abs(a),Math.abs(b));

// Explicitly reviewed code paths, not an inference from matching word names.
const COVERAGE = {
  FireWait: {status:'source_cadence_copied_to_32_named_profiles', key:'ballistics.fire_rate_rpm', transform:'60 / saved RPM compared to raw source seconds', reader:'scripts/weapons/socom_weapon_controller.gd:189', server:'scripts/network/socom_multiplayer_rounds.gd:245'},
  Muzzle_Velocity: {status:'saved_scalar_consumed_for_tracer_not_temporal_damage', key:'ballistics.muzzle_velocity_mps', reader:'scripts/weapons/weapon_ballistics.gd:360', server:'scripts/network/socom_shot_presentation.gd:16'},
  Maximum_Range: {status:'saved_scalar_consumed_for_immediate_ray_range', key:'ballistics.max_range_m', reader:'scripts/weapons/weapon_ballistics.gd:277'},
  Effective_Range: {status:'saved_metadata_UI_only_not_trajectory_or_damage_falloff', key:'ballistics.effective_range_m', reader:'scripts/ui/socom_buy_menu.gd:385'},
  Gravity_Acceleration: {status:'raw_source_not_consumed_by_firearm_runtime', reader:null},
  AccelerationFactor: {status:'raw_source_not_consumed_by_firearm_runtime', reader:null},
  NumProjectilesFired: {status:'separate_tuned_pellet_count_not_source_copy', key:'ballistics.pellet_count', reader:'scripts/weapons/weapon_ballistics.gd:274'},
  ReticuleKnock: {status:'source_stance_scalar_copied_no_original_pixel_or_angle_equivalence_claim', key:'reticle.socom2_stances.*.shot_kick_px', reader:'scripts/weapons/weapon_reticle_stance_profile.gd:4'},
  ReticuleKnockMax: {status:'source_stance_scalar_copied_no_original_pixel_or_angle_equivalence_claim', key:'reticle.socom2_stances.*.maximum_shot_kick_px', reader:'scripts/weapons/weapon_reticle_stance_profile.gd:4'},
  ReticuleKnockReturn: {status:'source_stance_scalar_copied_no_original_timestep_equivalence_claim', key:'reticle.socom2_stances.*.vrc_return_speed_px_per_second', reader:'scripts/weapons/weapon_reticle_stance_profile.gd:4'},
  Ammo_Capacity: {status:'saved_magazine_capacity_consumed_source_value_comparison_only', key:'ballistics.magazine_capacity', reader:'scripts/network/socom_multiplayer_combat.gd:10'},
  NumMags: {status:'source_number_not_directly_read_runtime_uses_saved_reserve_rounds', key:'ballistics.reserve_ammo', reader:'scripts/network/socom_multiplayer_round_loadout.gd:103'},
  ImpactDamage: {status:'not_source_equation_runtime_uses_tuned_shot_or_pellet_damage', key:'ballistics.damage', reader:'scripts/weapons/weapon_ballistics.gd:241'},
  Piercing: {status:'source_ammo_field_not_configured_into_current_penetration_power', reader:'scripts/weapons/weapon_ballistics.gd:27'},
  RecoilPct: {status:'raw_source_not_used_as_runtime_recoil_equation', reader:null},
};
for (const tag of ['AccBurstCnt_Min','AccBurstCnt_Max','AccScalar_Min','AccScalar_Max',
  'AccuracyBurstCnt_Min','AccuracyBurstCnt_Max','AccuracyScalar_Min','AccuracyScalar_Max',
  'TargetDilateUponFire','TargetDilateUponMovement','TargetDilateUponMovementMult','TargetConstrict','TargetMin','TargetMax',
  'SniperDecayRate','SniperDistPPFrameX','SniperDistPPFrameY','SniperDistLimitX','SniperDistLimitY',
  'FireRifleKickRate','FireRifleKickReturnRate','FireRifleKickBaseDist','FireRifleKickRandomDist']) {
  COVERAGE[tag] = {status:'raw_reference_not_a_verified_runtime_angle_or_recoil_equation', reader:null};
}
for (const tag of ['SingleMode','BurstMode','AutoMode']) {
  COVERAGE[tag] = {status:'copied_mode_enum_in_named_source_profiles', key:'fire_modes', reader:'scripts/weapons/weapon_fire_mode_policy.gd'};
}

function duplicateIds(records) {
  const map = new Map();
  for (const r of records) for (const field of idFields(r)) for (const id of field) {
    const key = JSON.stringify(id);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(reference(r));
  }
  return [...map].filter(([,rows])=>rows.length > 1).map(([id,rows])=>({id:JSON.parse(id),records:rows}));
}

function build(source, profiles) {
  const byName = new Map();
  for (const r of source.weapons) {
    if (!byName.has(r.name)) byName.set(r.name, []);
    byName.get(r.name).push(r);
  }
  const exact = new Map();
  const profileRows = profiles.map(p => {
    const name = p.data.reticle?.socom2_source_name;
    const linked = typeof name === 'string' ? byName.get(name) || [] : [];
    if (typeof name === 'string') assert.equal(linked.length,1,'Explicit source reference must resolve uniquely');
    if (linked.length === 1) {
      if (!exact.has(linked[0].index)) exact.set(linked[0].index, []);
      exact.get(linked[0].index).push(p);
    }
    const originalId = p.data.socom_original_id ?? null;
    return {file:p.file, weapon_id:p.data.weapon_id, explicit_source_name:name ?? null,
      source_link_status:linked.length === 1 ? 'explicit_saved_source_name' : 'no_explicit_source_behavior_link',
      source_record:linked.length === 1 ? reference(linked[0]) : null,
      legacy_original_id:originalId, legacy_original_name:p.data.socom_recom_data?.original_name ?? null,
      numeric_id_candidates: originalId === null ? [] : source.weapons.filter(r=>idFields(r).some(a=>a.includes(originalId))).map(reference),
      note:'Numeric IDs and legacy labels are indexed without silently activating or claiming matching source behavior.'};
  });
  const records = section => source[section].map(r => {
    const matching = section === 'weapons' ? exact.get(r.index) || [] :
      profiles.filter(p => {
        const row = profileRows.find(x=>x.file===p.file);
        if (!row.source_record) return false;
        const weapon = source.weapons[row.source_record.source_index];
        return values(weapon,'AMMO_TYPES').some(a=>ammoNames(a).includes(r.name));
      });
    const comparison = (p, tag) => {
      const sourceValue = scalar(r, tag);
      const keys = {FireWait:'fire_rate_rpm',Muzzle_Velocity:'muzzle_velocity_mps',Maximum_Range:'max_range_m',Effective_Range:'effective_range_m',Ammo_Capacity:'magazine_capacity',NumProjectilesFired:'pellet_count'};
      const rawSaved = p.data.ballistics[keys[tag]] ?? null;
      const compared = tag === 'FireWait' && Number.isFinite(rawSaved) ? 60/rawSaved : rawSaved;
      return {tag, raw_source_value:sourceValue, saved_key:'ballistics.'+keys[tag], saved_value:rawSaved,
        compared_value:compared, numerically_equal:near(sourceValue, compared),
        note:'Value comparison, not a units/application/lineage proof.'};
    };
    return {...reference(r), raw_internal_name_fields:values(r,'InternalName'),
      linked_profiles:matching.map(p=>({file:p.file,weapon_id:p.data.weapon_id,
        comparisons:['FireWait','Muzzle_Velocity','Maximum_Range','Effective_Range','Ammo_Capacity','NumProjectilesFired']
          .filter(tag=>values(r,tag).length).map(tag=>comparison(p,tag))})),
      ammo_references:section === 'weapons' ? values(r,'AMMO_TYPES').flatMap(a=>ammoNames(a)).map(name=>({name,
        matches:source.ammunition.filter(a=>a.name===name).map(reference)})) : [],
      fields:[r,...r.nested_tagged_blocks].flatMap(block=>block.fields.map(f=>({context:block.context,
        field_index:f.index,tag:f.tag,values:f.values,
        coverage:COVERAGE[f.tag] || {status:'outside_reviewed_trajectory_field_scope_no_consumption_claim'}}))),
      unparsed_atoms:[r,...r.nested_tagged_blocks].flatMap(block=>block.unparsed_atoms)};
  });
  const weapons = records('weapons'), ammunition = records('ammunition');
  const special = tag => [...weapons,...ammunition].flatMap(r=>r.fields.filter(f=>f.tag===tag).map(f=>({record:r.name,index:r.source_index,ids:r.ids,context:f.context,values:f.values,linked_profiles:r.linked_profiles})));
  return {schema_version:1,status:'Offline field/identity index; no new trajectory policy implemented',
    limitations:['Same numeric scalar does not establish source units, executable behavior or provenance.',
      'Absent source gravity/acceleration fields do not prove zero; original defaults/dispatch remain unknown.',
      'Duplicate IDs and unparsed atoms are preserved; no lossy ID dictionary.',
      'Raw angle-related fields are not converted into degrees/radians without original code evidence.'],
    source:source.source, coverage_rules:COVERAGE,profiles:profileRows,weapons,ammunition,
    duplicate_weapon_ids:duplicateIds(source.weapons),duplicate_ammo_ids:duplicateIds(source.ammunition),
    special_fields:{gravity:special('Gravity_Acceleration'),acceleration:special('AccelerationFactor'),pellets:special('NumProjectilesFired')},
    counts:{source_weapons:weapons.length,source_ammunition:ammunition.length,runtime_profiles:profiles.length,
      explicit_source_profiles:profileRows.filter(p=>p.source_record).length,
      source_weapon_records_with_explicit_profiles:weapons.filter(w=>w.linked_profiles.length).length,
      covered_source_tag_names:Object.keys(COVERAGE).filter(tag=>source.field_inventory[tag]).length,
      all_source_tag_names:Object.keys(source.field_inventory).length}};
}

function selfTest() {
  const f=(tag,values,index=0)=>({tag,values,index});
  const r=(name,index,fields)=>({name,index,context:'TEST['+index+']',fields,nested_tagged_blocks:[],unparsed_atoms:[]});
  const source={source:{},field_inventory:{FireWait:{},ID:{}},
    weapons:[r('Gun',0,[f('ID',[3]),f('FireWait',[0.2])])],
    ammunition:[r('A',0,[f('ID',[28])]),r('B',1,[f('ID',[28])])]};
  const p={file:'gun.json',data:{weapon_id:'gun',reticle:{socom2_source_name:'Gun'},ballistics:{fire_rate_rpm:300}}};
  const output=build(source,[p]);
  assert.equal(output.profiles[0].source_link_status,'explicit_saved_source_name');
  assert.equal(output.weapons[0].linked_profiles[0].comparisons[0].numerically_equal,true);
  assert.equal(output.duplicate_ammo_ids[0].records.length,2);
  assert.throws(()=>build(source,[{...p,data:{...p.data,reticle:{socom2_source_name:'Missing'}}}]));
  assert.equal(near(null,0),false);
  console.log('SOURCE_TRAJECTORY_FIELD_COVERAGE_SELF_TEST PASS');
}

function run(output) {
  assert(output,'Usage: source_trajectory_field_coverage.cjs NEW_REPORT.json');
  const target=path.resolve(output), allowed=path.join(ROOT,'art_source')+path.sep;
  assert(target.startsWith(allowed)||target.startsWith('/private/tmp/'),'Output restricted to research directories');
  assert(!fs.existsSync(target),'Refuse to overwrite output');
  assert(fs.existsSync(path.dirname(target)),'Output parent must exist');
  const inputs=[];
  const read = p => {const absolute=path.join(ROOT,p),bytes=fs.readFileSync(absolute);inputs.push({path:p,sha256:sha(bytes)});return JSON.parse(bytes);};
  const source=read(SOURCE);
  const profiles=fs.readdirSync(path.join(ROOT,'config/weapons')).filter(p=>p.endsWith('.json')).sort().map(file=>({file:'config/weapons/'+file,data:read('config/weapons/'+file)})).filter(p=>p.data.weapon_id && p.data.ballistics);
  const report=build(source,profiles);
  assert.equal(report.counts.source_weapons,86);assert.equal(report.counts.source_ammunition,39);
  assert.equal(report.counts.runtime_profiles,45);assert.equal(report.counts.explicit_source_profiles,32);
  for(const p of ['tools/source_trajectory_field_coverage.cjs','tools/socom2_weapon_reference.cjs','tools/source_ballistics_audit.cjs',
    'tools/socom2_weapon_reference_test.cjs','scripts/weapons/weapon_ballistics.gd','scripts/weapons/weapon_rig_contract.gd',
    'scripts/weapons/weapon_reticle_stance_profile.gd','scripts/network/socom_multiplayer_rounds.gd',
    'scripts/weapons/socom_weapon_controller.gd','scripts/ui/socom_buy_menu.gd']) {
    inputs.push({path:p,sha256:sha(fs.readFileSync(path.join(ROOT,p)))});
  }
  // Check all inputs again before write to catch concurrent source changes.
  for(const input of inputs) assert.equal(sha(fs.readFileSync(path.join(ROOT,input.path))),input.sha256,'Input changed during observation');
  report.inputs=inputs;
  fs.writeFileSync(target,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log('SOURCE_TRAJECTORY_FIELD_COVERAGE PASS '+JSON.stringify({...report.counts,duplicate_weapon_ids:report.duplicate_weapon_ids.length,duplicate_ammo_ids:report.duplicate_ammo_ids.length,output:target}));
}
if(require.main===module) {if(process.argv[2]==='--self-test')selfTest();else run(process.argv[2]);}
module.exports={build,duplicateIds};
