// Read-only patch producer. Apply its output through apply_patch, review, test.
const fs = require('fs');
const map = {
  mark_23:'s2_mark_23', de__50:'s2_de_50', m9:'s2_m9', m4a1:'s2_m4a1',
  m16a2:'s2_m16a2', 'ak-47':'s2_ak47', 'aks-74':'s2_aks74', hk5:'s2_hk5',
  m14:'s2_m14', m40a1:'s2_m40a1', '870':'s2_870', m60e3:'s2_m60e3'
};
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const roster = read('config/weapon_roster_extensions.json').public_roster;
const families = read('config/weapon_family_visual_assignments.json');
const requested = process.argv[2];
if (requested && requested !== '--manifest' && !Object.hasOwn(map, requested)) throw Error('Unknown weapon');
if (JSON.stringify(Object.keys(map).sort()) !== JSON.stringify(Object.keys(roster).sort())) throw Error('Public roster differs');
const assetFields = ['model_fbx','normalized_scale','user_scale_multiplier','model_rotation_degrees','operator_mount','grip_offset','weapon_sockets','support_hand_pose','elbow_poles','stances','animation_hand_maps','animation_frame_pose_keys','gun_placement_line','camo_skin','scope_attachment','silencer_attachment'];
const edits = [];
const proof = [];
for (const [id, sourceId] of Object.entries(map)) {
  const path = `config/weapons/${id}.json`;
  const rawText = fs.readFileSync(path,'utf8');
  const original = JSON.parse(rawText);
  const source = read(`config/weapons/${sourceId}.json`);
  let oldRigId = original.visual_rig_id || '';
  if (!oldRigId && !original.socket_contract_authored && !families.excluded_weapon_ids.includes(id)) {
    const entry = families.model_assignments[original.model_fbx];
    if (entry && (!entry.categories.length || entry.categories.includes(original.category))) oldRigId = entry.visual_rig_id;
  }
  // Already-applied entries can still contribute their preserved pre-migration
  // provenance when emitting the final inventory. Never rebase on the new rig.
  if (oldRigId.startsWith('iso_public_')) oldRigId = read(`config/weapon_visual_rigs/${oldRigId}.json`).migration.previous_resolved_rig_id;
  const oldRig = oldRigId ? read(`config/weapon_visual_rigs/${oldRigId}.json`) : null;
  const previous = {...original, ...(oldRig?.visual || {})};
  const visual = {};
  for (const key of assetFields) {
    if (key in source) visual[key] = source[key];
    else if (['support_hand_pose','elbow_poles','stances','animation_hand_maps','animation_frame_pose_keys','gun_placement_line'].includes(key)) visual[key] = {};
  }
  // Keep the entire existing handling contract: clocks, source animation slots,
  // posture and attachment strategy. Only mesh-specific calibration is migrated.
  visual.handling_profile = previous.handling_profile;
  const rigId = `iso_public_${id.replaceAll('-','_')}_v1`;
  const rigPath = `config/weapon_visual_rigs/${rigId}.json`;
  if (requested === id && fs.existsSync(rigPath)) throw Error(`Refusing to overwrite ${rigPath}`);
  const document = {schema_version:1, visual_rig_id:rigId, revision:1, status:'published', family:source.handling_profile.family,
    source_model_fbx:source.model_fbx, visual, certification:{required_stances:['STANDING','CROUCHED','PRONE'],required_actions:['aim_idle','combat_fire','reload'],maximum_palm_error_m:.01,published_by:'public_iso_migration'},
    migration:{source_profile:`res://config/weapons/${sourceId}.json`,previous_resolved_rig_id:oldRigId,source_asset:source.source_asset}};
  // Change only the visual assignment and leave all authored gameplay bytes.
  let nextText;
  if (original.visual_rig_id) nextText = rawText.replace(/"visual_rig_id"\s*:\s*"[^"]+"/,`"visual_rig_id": "${rigId}"`);
  else nextText = rawText.replace('{',`{\n  "visual_rig_id": "${rigId}",\n  "visual_rig_schema_version": 1,`);
  if (requested === id) {
    edits.push({path, before:rawText, after:nextText});
    edits.push({path:rigPath, after:JSON.stringify(document,null,2)+'\n'});
  }
  proof.push({id,source_id:sourceId,rig_id:rigId,previous_resolved_rig_id:oldRigId,old_model:previous.model_fbx,new_model:source.model_fbx});
}
if (requested === '--manifest') edits.push({path:'config/public_iso_weapon_migration.json',after:JSON.stringify({schema_version:1,entries:proof},null,2)+'\n'});
if (!requested) throw Error('Specify one weapon ID or --manifest; output intentionally bounded.');
process.stdout.write(JSON.stringify(edits));
