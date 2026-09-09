'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict');
const {extract,reader}=require('./socom2_weapon_reference.cjs');
const ref=JSON.parse(fs.readFileSync('config/reference/socom2_weapon_settings.json'));
const aliases=JSON.parse(fs.readFileSync('config/reference/socom2_weapon_aliases.json')).aliases;
assert.equal(ref.weapons.length,86);
assert.equal(ref.source.reader_sha256,'8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b');
assert.throws(()=>reader(Buffer.alloc(12))); // unsupported version cannot produce settings
assert(ref.weapons.find(w=>w.name==='M16A2').unparsed_atoms.some(a=>a.context==='STANCE_PRONE'&&a.value===0));
let count=0;
for(const file of fs.readdirSync('config/weapons').filter(f=>f.endsWith('.json'))){
  const p=JSON.parse(fs.readFileSync('config/weapons/'+file));if(!p.reticle?.socom2_source_name)continue;
  const w=ref.weapons.find(w=>w.name===p.reticle.socom2_source_name);assert(w);
  const alias=aliases[p.weapon_id];
  if(alias){assert.equal(w.name,alias.source_name);assert.equal(w.display_name,alias.source_display_name);}
  else assert.equal(p.weapon_id.replace(/[^a-z0-9]/gi,'').toLowerCase(),w.name.replace(/[^a-z0-9]/gi,'').toLowerCase());
  if(w.mode_flags.length)assert.deepEqual(p.fire_modes,w.mode_flags.map(k=>({SingleMode:'semi',BurstMode:'burst',AutoMode:'auto'})[k]));
  assert(Math.abs(60/p.ballistics.fire_rate_rpm-w.numeric.FireWait)<1e-10);
  for(const [raw,stance] of [['STANCE_STAND','STANDING'],['STANCE_CROUCH','CROUCHED'],['STANCE_PRONE','PRONE']]){
    const s=w.stances[raw],r=p.reticle.socom2_stances[stance];
    assert.equal(r.shot_kick_px,s.ReticuleKnock);assert.equal(r.maximum_shot_kick_px,s.ReticuleKnockMax);
    assert.equal(r.shot_kick_return,s.ReticuleKnockReturn);assert.equal(r.vrc_return_speed_px_per_second,s.ReticuleKnockReturn);
  }
  count++;
}
assert.equal(count,32);
assert.deepEqual(ref.weapons.find(w=>w.name==='JACKHAMMER').mode_flags,['AutoMode']);
assert.deepEqual(ref.weapons.find(w=>w.name==='Model 18').mode_flags,['SingleMode','AutoMode']);
for(const id of ['designator','air_to_ground_missile','exploding_fuel','assaultrifle_1']){
  const p=JSON.parse(fs.readFileSync('config/weapons/'+id+'.json'));assert(!p.reticle.socom2_stances);
}
if(process.argv[2])assert.deepEqual(extract(process.argv[2]),ref,'re-extraction must match every recorded value');
console.log('SOCOM2_WEAPON_REFERENCE PASS matched='+count+' source_records='+ref.weapons.length+' iso_verified='+!!process.argv[2]);
