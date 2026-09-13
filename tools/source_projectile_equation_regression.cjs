'use strict';
// Bounded arithmetic-only source-instruction fixtures. No game/ISO boot, device,
// syscall, network or asset writes. Unsupported instructions/numerics fail closed.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const fs=require('node:fs');
const {moduleImage}=require('./source_projectile_routine_audit.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const SOURCE_HASH='cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836';
const F=Math.fround;
const categories=[
  [4,31,'PISTOLS'],[31,51,'SMGS'],[51,81,'ASSAULT RIFLES'],
  [81,91,'SHOTGUNS'],[91,101,'MACHINE GUNS'],[101,121,'SNIPER RIFLES'],
  [121,141,'GRENADES'],[141,145,'HEAVY WEAPONS'],[145,151,'LAUNCHERS'],
  [151,171,'EXPLOSIVES'],[171,185,'LAUNCHED'],[185,190,'MISSILE'],
  [190,201,'MISC EQUIP'],[201,205,'ARMOR'],[205,230,'TURRETED WEAPONS'],
  [230,254,'TURRETED LAUNCHERS']
];
const excludes=new Set([171,185,121,151,190,230]);
function category(id){return categories.find(([lo,hi])=>(id&255)>=lo&&(id&255)<hi)?.[0]??254;}
function direct(id){return !excludes.has(category(id));}
function scale(v,k){return v.map(x=>F(F(x)*F(k)));}
function add(a,b){return a.map((v,i)=>F(F(v)+F(b[i])));}
function normal(position,velocity,gravity,dt){
  const nextVelocity=add(velocity,scale([0,F(-F(gravity)),0],dt));
  return{velocity:nextVelocity,position:add(position,scale(nextVelocity,dt))};
}
function normalize(v){
  const q=v.map(F),length=F(Math.sqrt(F(F(F(q[0]*q[0])+F(q[1]*q[1]))+F(q[2]*q[2]))));
  return length===0?q:scale(q,F(1/length));
}
function oneFrame(position,velocity,range){
  const direction=normalize(velocity);
  return{position:add(position,scale(direction,F(F(1.1)*F(range)))),velocity:scale(direction,300)};
}
function fixtures(file){
  const im=moduleImage(file),hash=crypto.createHash('sha256').update(im.bytes).digest('hex');
  assert.equal(hash,SOURCE_HASH,'reject unaudited source release');
  const weapon=0x100000,projectile=0x110000,stack=0x120000;
  function machine(ranges){
    const m=new FloatFixtureMachine({maxSteps:10000,maxMappedBytes:256*1024});
    for(const [lo,hi]of ranges)m.map(lo,im.bytes.subarray(im.offset(lo),im.offset(hi)),{execute:true,name:`original ${lo.toString(16)}`});
    m.map(weapon,Buffer.alloc(512),{write:true,name:'synthetic weapon'});
    m.map(projectile,Buffer.alloc(512),{write:true,name:'synthetic projectile'});
    m.map(stack,Buffer.alloc(4096),{write:true,name:'bounded scratch stack'});
    m.set64(16,BigInt(projectile));m.set64(29,BigInt(stack+2048));
    return m;
  }
  const put=(m,a,v)=>{const b=Buffer.alloc(4);b.writeFloatLE(v);m.store(a,4,BigInt(b.readUInt32LE()));};
  const get=(m,a)=>{const b=Buffer.alloc(4);b.writeUInt32LE(Number(m.load(a,4)));return b.readFloatLE();};
  const vec=(m,a,v)=>v.forEach((x,i)=>put(m,a+i*4,x));
  const readvec=(m,a)=>[0,4,8].map(i=>get(m,a+i));
  let categoryCases=0;
  for(let id=0;id<256;id++){
    const m=machine([[0x3d1a60,0x3d1c70],[0x3d1e20,0x3d1e94]]);
    m.store(weapon+0x7c,1,BigInt(id));
    const result=m.run(0x3d1e20,{args:[weapon],stackPointer:stack+2048});
    assert.equal(result.value,direct(id)?1n:0n,`source classifier id ${id}`);categoryCases++;
  }
  const rows=[];
  const inputs=[
    {position:[10,20,30],velocity:[9000,100,30],gravity:98,dt:1/30,range:5000},
    {position:[-3,8,-20],velocity:[10,50,-10],gravity:98,dt:1/60,range:750},
    {position:[0,0,0],velocity:[0,0,900],gravity:0,dt:0.25,range:10000},
    {position:[1,2,3],velocity:[3,4,12],gravity:75,dt:0.016,range:1250},
    {position:[1,2,3],velocity:[0,0,0],gravity:0,dt:0,range:1000},
    {position:[1e8,-1e8,1e8],velocity:[1e12,0,-1e12],gravity:98,dt:0.25,range:1e10}
  ];
  for(const input of inputs)for(const mode of ['normal','one_frame']){
    const range=mode==='normal'?[0x3ca898,0x3ca998]:[0x3ca998,0x3caa40];
    const m=machine([range,[0x309110,0x3091a8],[0x309240,0x309274],[0x3d27b0,0x3d27c8],[0x3d27f0,0x3d27f8]]);
    m.store(projectile+12,4,BigInt(weapon));vec(m,projectile+0x48,input.position);vec(m,projectile+0x60,input.velocity);
    put(m,weapon+0x48,input.gravity);put(m,weapon+0x3c,input.range);m.setFloat(20,input.dt);m.set64(4,1n);
    m.run(range[0],{returnAddress:0x3cab10});
    const observed={position:readvec(m,projectile+0x54),velocity:readvec(m,projectile+0x60)};
    const expected=mode==='normal'?normal(input.position,input.velocity,input.gravity,input.dt):oneFrame(input.position,input.velocity,input.range);
    assert.deepEqual(observed,expected,`${mode} scalar source equation`);
    rows.push({mode,input,observed,instructions:m.steps});
  }
  // Source initial-velocity body: direction * source muzzle speed + caller vector.
  const m=machine([[0x3cb3e0,0x3cb408],[0x3d27c0,0x3d27c8],[0x309180,0x3091a8],[0x309240,0x309274]]);
  const direction=[0.6,0,0.8],inherited=[10,0,-15];
  m.set64(17,BigInt(projectile+256));m.set64(19,BigInt(weapon));m.set64(21,BigInt(projectile));
  vec(m,projectile+256,direction);vec(m,projectile+272,inherited);put(m,weapon+68,9210);
  m.store(stack+2048+172,4,BigInt(projectile+272));m.run(0x3cb3e0,{returnAddress:0x3cb408});
  assert.deepEqual(readvec(m,projectile+96),add(scale(direction,9210),inherited));
  // Actual candidate selection is STRICT dist² < currentRange², despite the
  // 1.1 padded broad-phase segment. Exact equality and padding hits are rejected.
  const cutoff=[];
  for(const distance of [0,999.9,1000,1050,1100]){
    const c=machine([[0x3c9ce8,0x3c9d40]]),sp=stack+2048;
    c.set64(22,BigInt(sp+0xd4));c.set64(23,BigInt(sp+0xd8));
    c.set64(17,BigInt(projectile+256));c.set64(20,0n);
    vec(c,sp+0xd0,[distance,0,0]);c.setFloat(20,F(1000*1000));c.setFloat(21,0);c.setFloat(23,0);
    c.run(0x3c9ce8,{returnAddress:0x3c9d40});
    const selected=c.u(20)!==0n;assert.equal(selected,distance>0&&F(F(distance)*F(distance))<F(1000*1000));
    cutoff.push({distance,range:1000,selected});
  }
  return{source_sha256:hash,category_cases:categoryCases,category_names:categories.map(([lo,hi,name])=>({lo,hi_exclusive:hi,name,direct:direct(lo)})),trajectory_cases:rows,initial_velocity:'PASS',range_candidate_cutoff:cutoff,limitations:['IEEE float32 fixture arithmetic is not bit-exact PS2 EE denormal/rounding emulation. Only finite normal fixtures are claimed.','No collision-world, impact response, networking, damage or Godot integration is exercised.','Positions/range/speed here remain original module world units; SI conversion is not inferred by these fixtures.']};
}
if(require.main===module){
  assert(process.argv[2],'usage: node tools/source_projectile_equation_regression.cjs FTSCore.bin [FRESH_REPORT.json]');
  const result=fixtures(process.argv[2]);
  if(process.argv[3])fs.writeFileSync(process.argv[3],JSON.stringify(result,null,2)+'\n',{flag:'wx'});
  else console.log(JSON.stringify(result,null,2));
  console.log('PASS original classifier 256 cases; normal/one-frame 12 instruction fixtures; initial velocity; strict max-range cutoff 5 cases');
}
module.exports={fixtures,normal,oneFrame,category,direct,categories,SOURCE_HASH};
