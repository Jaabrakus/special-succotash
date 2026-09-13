'use strict';
// Bounded original scalar routines and read-only source data, never game execution.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {moduleImage}=require('./source_projectile_routine_audit.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const {isoFile,reader}=require('./socom2_weapon_reference.cjs');
const {archive}=require('./socom_geometry/archive.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),f=Math.fround;
const BASE=path.resolve(__dirname,'../art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1');
const HASH={FTSCore:'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',ZSealEtc:'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'};
const REGIONS=['head','rarm','larm','body','rleg','lleg'];
function images(folder=BASE){const result={};for(const name of Object.keys(HASH)){const im=moduleImage(path.join(folder,name+'.bin'));assert.equal(sha(im.bytes),HASH[name],'source version mismatch');result[name]=im;}return result;}
function span(m,im,lo,hi,execute=true){m.map(lo,im.bytes.subarray(im.offset(lo),im.offset(hi)),{execute,name:'pinned original source span'});}
function machine(){const m=new FloatFixtureMachine({maxSteps:20000,maxMappedBytes:256*1024});m.map(0x100000,Buffer.alloc(8192),{write:true,name:'bounded synthetic stack'});return m;}
function field(row,key){const matches=[];for(let i=0;i<row.length-1;i++)if(row[i]===key&&Array.isArray(row[i+1]))matches.push(row[i+1]);assert(matches.length<=1,'ambiguous source field '+key);return matches[0]??null;}
function numericFields(row){const result={};for(let i=0;i<row.length-1;i++)if(typeof row[i]==='string'&&Array.isArray(row[i+1])&&row[i+1].length===1&&typeof row[i+1][0]==='number')result[row[i]]=row[i+1][0];return result;}
function sourceData(iso){
  const bytes=isoFile(iso,['RUN','READERC.ZAR']),entries=archive(bytes).entries;
  function entry(name){const e=entries.filter(e=>e.name===name);assert.equal(e.length,1);const raw=bytes.subarray(e[0].offset,e[0].offset+e[0].size);return{tree:reader(raw),sha256:sha(raw),offset:e[0].offset,bytes:e[0].size};}
  const chars=entry('character.rdr'),materials=entry('materials.rdr');
  assert.equal(chars.tree.length,1);const rows=field(chars.tree[0],'characters');assert(rows);
  const records=[];
  for(let i=0;i<rows.length;){const name=rows[i++];assert.equal(typeof name,'string');let parent=null;if(rows[i]===':'){i++;parent=rows[i++];assert.equal(typeof parent,'string');}const row=rows[i++];assert(Array.isArray(row));records.push({name,parent,row});}
  const selected=['mp_seal','mp_terror'].map(name=>{const found=records.filter(r=>r.name===name);assert.equal(found.length,1);const row=found[0].row,health=numericFields(field(row,'health')),armor=numericFields(field(row,'armor'));for(const region of REGIONS)assert(Number.isFinite(health[region])&&Number.isFinite(armor[region]));return{name,parent:found[0].parent,health,armor};});
  assert.deepEqual(selected[0].health,selected[1].health);assert.deepEqual(selected[0].armor,selected[1].armor);
  return{archive:'RUN/READERC.ZAR',archive_sha256:sha(bytes),character_reader:{sha256:chars.sha256,offset:chars.offset,bytes:chars.bytes},material_reader:{sha256:materials.sha256,offset:materials.offset,bytes:materials.bytes},character_records:records.length,multiplayer_profiles:selected,material_rows:field(materials.tree,'SOILS').map(row=>({name:field(row,'NAME')[0],...numericFields(row)}))};
}
function armorReference(hp,armor,damage,piercing){
  let through=f(f(damage)-f(f(armor)*f(f(10-f(piercing))/10)));if(through<=0)through=0;
  const armorAfter=Math.max(0,f(f(armor)-f(f(f(damage)-through)/4)));
  return{hp:Math.max(0,f(f(hp)-through)),armor:armorAfter,through};
}
function originalArmor(im,{hp,armor,damage,piercing}){
  const m=machine();span(m,im,0x3c7400,0x3c7490);const b=m.map(0x110000,Buffer.alloc(16),{write:true});b.writeFloatLE(hp,0);b.writeFloatLE(armor,4);m.setFloat(12,damage);m.setFloat(13,piercing);m.run(0x3c7400,{args:[0x110000,0x110004],stackPointer:0x101000});return{hp:b.readFloatLE(0),armor:b.readFloatLE(4)};
}
function originalRangeDamage(im,{impact,modifier,effective,maximum,distance,minimumDamage=0}){
  const m=machine();for(const[lo,hi]of[[0x3c7600,0x3c7ad0],[0x3d4530,0x3d4538],[0x3d2050,0x3d2058],[0x3d27e0,0x3d27f8],[0x309200,0x309234],[0x3c5950,0x3c5960]])span(m,im,lo,hi);span(m,im,0x3f64c0,0x3f64cc,false);
  const b=m.map(0x110000,Buffer.alloc(2048),{write:true});b.writeUInt32LE(0x110100,12);b.writeUInt32LE(0x110200,16);b.writeUInt32LE(0x110300,32);b[10]=1;b[0x100+124]=51;b.writeFloatLE(effective,0x100+64);b.writeFloatLE(maximum,0x100+60);b.writeFloatLE(modifier,0x100+100);b.writeFloatLE(impact,0x200+12);b.writeFloatLE(distance,0x400);
  m.setFloat(12,minimumDamage);m.run(0x3c7600,{args:[0x110000,0x110400],stackPointer:0x101000});return m.float(0);
}
function rangeDamageReference({impact,modifier,effective,maximum,distance,minimumDamage=0}){
  let damage=f(f(impact)+f(modifier));distance=f(distance);effective=f(effective);maximum=f(maximum);
  if(distance>effective){const width=f(maximum-effective);damage=width<=0?0:f(damage*f(1-f(f(distance-effective)/width)));}
  return damage===0||damage<f(minimumDamage)?0:f(14*damage);
}
function originalPenetration(im,{range,piercing,penetration,distanceSquared}){
  const m=machine();span(m,im,0x3c8eb0,0x3c8f18);span(m,im,0x3d4520,0x3d4528);
  const b=m.map(0x110000,Buffer.alloc(512),{write:true});b.writeUInt32LE(0x110100,16);b.writeFloatLE(range,148);b.writeFloatLE(piercing,0x100+20);m.set64(21,0x110000n);m.setFloat(22,penetration);m.setFloat(20,distanceSquared);m.run(0x3c8eb0,{stackPointer:0x101000,returnAddress:0x3c8f18});return{range:b.readFloatLE(148),resultCode:Number(m.u(2))};
}
function penetrationReference({range,piercing,penetration,distanceSquared}){
  range=f(range);const candidate=f(f(range+f(range*f(f(.1)*f(piercing))))*f(penetration));const out=candidate<range?candidate:range;return{range:out,resultCode:f(distanceSquared)<=f(out*out)?2:4};
}
function originalPools(ims,{health,maxima,armor,region,damage,piercing}){
  const m=machine();span(m,ims.ZSealEtc,0x5a5830,0x5a5a80);span(m,ims.ZSealEtc,0x65f640,0x65f658,false);span(m,ims.ZSealEtc,0x6508a8,0x6508b4,false);span(m,ims.FTSCore,0x3c7400,0x3c7490);
  const b=m.map(0x110000,Buffer.alloc(8192),{write:true});for(let i=0;i<6;i++){b.writeFloatLE(health[i],4092+4*i);b.writeFloatLE(maxima[i],4116+4*i);b.writeFloatLE(armor[i],4140+4*i);}m.setFloat(12,damage);m.setFloat(13,piercing);m.run(0x5a5830,{args:[0x110000,region],stackPointer:0x101000});return{health:Array.from({length:6},(_,i)=>b.readFloatLE(4092+4*i)),armor:Array.from({length:6},(_,i)=>b.readFloatLE(4140+4*i)),changed:Number(m.u(2))};
}
function poolsReference({health,maxima,armor,region,damage,piercing}){
  const h=health.map(f),a=armor.map(f);let changed=0;
  function apply(r,d,p){if(d<=0||r<0||r>=6)return;if(h[r]<=0){if(r!==0&&r!==3)apply(3,f(d*f(.3)),10);return;}const out=armorReference(h[r],a[r],d,p);h[r]=out.hp;a[r]=out.armor;changed=1;if(r===3){const fraction=f(h[3]/f(maxima[3]));for(const limb of[2,1,5,4])h[limb]=Math.min(h[limb],f(f(maxima[limb])*fraction));}}
  apply(region,f(damage),f(piercing));return{health:h.map(v=>Math.max(0,v)),armor:a,changed};
}
function originalHealthRatio(im,health,maxima,active=true){
  const m=machine();span(m,im,0x5a56d0,0x5a5790);const b=m.map(0x110000,Buffer.alloc(8192),{write:true});b[225]=active?16:0;for(let i=0;i<6;i++){b.writeFloatLE(health[i],4092+4*i);b.writeFloatLE(maxima[i],4116+4*i);}m.run(0x5a56d0,{args:[0x110000],stackPointer:0x101000});return m.float(0);
}
function originalDeathDecision(im,health,active=true){
  const m=machine();span(m,im,0x5a54d0,0x5a5558);const b=m.map(0x110000,Buffer.alloc(8192),{write:true});b[225]=active?16:0;b.writeFloatLE(health[0],4092);b.writeFloatLE(health[3],4104);m.run(0x5a54d0,{args:[0x110000,3,5],stackPointer:0x101000,returnAddress:0x5a5558});return Number(m.u(5))===1;
}
function audit(iso,folder=BASE){
  const ims=images(folder),source=sourceData(iso),fixtures={armor:[],range_damage:[],penetration:[],body_pools:[],health_ratio:[],death_condition:[]};
  for(const c of [{hp:50,armor:25,damage:36.4,piercing:3},{hp:8,armor:0,damage:36.4,piercing:3},{hp:50,armor:25,damage:1,piercing:0},{hp:50,armor:25,damage:200,piercing:10},{hp:50,armor:0,damage:0,piercing:0},{hp:50,armor:25,damage:35,piercing:9}]){const actual=originalArmor(ims.FTSCore,c),expected=armorReference(c.hp,c.armor,c.damage,c.piercing);assert.deepEqual(actual,{hp:expected.hp,armor:expected.armor});fixtures.armor.push({input:c,output:actual});}
  for(const extra of[{distance:0},{distance:500},{distance:750},{distance:1000},{distance:1100},{distance:501,effective:500,maximum:500},{distance:750,minimumDamage:2},{distance:250,impact:0,modifier:0}]){const c={impact:2.3,modifier:.3,effective:500,maximum:1000,...extra},actual=originalRangeDamage(ims.FTSCore,c);assert.equal(actual,rangeDamageReference(c));fixtures.range_damage.push({input:c,output:actual});}
  for(const extra of[{penetration:0},{penetration:.25},{penetration:.6},{penetration:.97},{penetration:.99},{penetration:1},{penetration:.25,distanceSquared:200000},{penetration:.25,distanceSquared:105625},{penetration:.25,distanceSquared:105626}]){const c={range:1000,piercing:3,distanceSquared:10000,...extra},actual=originalPenetration(ims.FTSCore,c);assert.deepEqual(actual,penetrationReference(c));fixtures.penetration.push({input:c,output:actual});}
  const p=source.multiplayer_profiles[0],health=REGIONS.map(r=>p.health[r]),armor=REGIONS.map(r=>p.armor[r]);
  for(const extra of[...Array.from({length:7},(_,region)=>({region})),{region:3,damage:200},{region:1,health:[8,0,30,50,30,30]},{region:0,health:[0,30,30,50,30,30]},{region:3,damage:0}]){const c={health,maxima:health,armor,damage:36.4,piercing:3,...extra},actual=originalPools(ims,c);assert.deepEqual(actual,poolsReference(c));fixtures.body_pools.push({input:c,output:actual});}
  for(const c of[{health,maxima:health,active:true},{health:[8,15,15,25,15,15],maxima:health,active:true},{health,maxima:health,active:false}]){const actual=originalHealthRatio(ims.ZSealEtc,c.health,c.maxima,c.active);let num=f(3*f(c.health[0])),den=f(3*f(c.maxima[0]));for(const i of[3,1,2,4,5]){num=f(num+f(c.health[i]));den=f(den+f(c.maxima[i]));}assert.equal(actual,!c.active||den===0?0:f(num/den));fixtures.health_ratio.push({input:c,output:actual});}
  for(const c of[{health,active:true},{health:[0,30,30,50,30,30],active:true},{health:[8,30,30,0,30,30],active:true},{health:[8,0,0,50,0,0],active:true},{health,active:false}]){const actual=originalDeathDecision(ims.ZSealEtc,c.health,c.active);assert.equal(actual,!c.active||c.health[0]<=0||c.health[3]<=0);fixtures.death_condition.push({input:c,output:actual});}
  return{schema_version:1,status:'Original scalar equations and MP health data verified offline; canonical runtime integration is separate',source,module_hashes:HASH,region_order:REGIONS,source_pcs:{range_damage:'0x3c7600',unit_conversion:'0x3c5950',armor:'0x3c7400',body_pools:'0x5a5830',health_ratio:'0x5a56d0',death_condition:'0x5a54d0',penetration_range:'0x3c8eb0'},fixtures,fixture_count:Object.values(fixtures).reduce((n,r)=>n+r.length,0),limitations:['Finite normal float32 fixture arithmetic is not complete bit-exact PS2 emulation.','Ordinary firearm range fixtures use synthetic node/source and target positions; full collision, gameplay and network callbacks are not executed.','Original ricochet, special material/type flags, shotgun branch and all contact ordering are not fully fixture-tested.','This audit does not change current 8-pellet shotgun tuning or any gameplay profile.']};
}
if(require.main===module){const[iso,out]=process.argv.slice(2);assert(iso,'usage: node tools/source_damage_equation_audit.cjs ISO [NEW_REPORT.json]');const result=audit(iso);if(out)fs.writeFileSync(out,JSON.stringify(result,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({result:'PASS',fixtures:result.fixture_count,profiles:result.source.multiplayer_profiles,source:result.source.character_reader,report:out??null},null,2));}
module.exports={audit,sourceData,images,originalArmor,originalRangeDamage,originalPenetration,originalPools,originalHealthRatio,originalDeathDecision,armorReference,rangeDamageReference,penetrationReference,poolsReference,REGIONS};
