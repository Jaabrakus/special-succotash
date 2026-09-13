'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {moduleImage,disasm}=require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const {image}=require('./source_loader_analysis.cjs');
const ROOT=path.resolve(__dirname,'..'),F=Math.fround;
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const CROSS_WORDS=[0xd8a40000,0xd8c50000,0x4bc522fe,0x4bc429ae,0x4a2631ac,0x03e00008,0xf8860000];
// Only the exact original seven-word helper is supported here. No VU fallback.
class CrossFixtureMachine extends FloatFixtureMachine {
  constructor(){super({maxSteps:3000});this.vectors=Array.from({length:32},()=>[0,0,0,0]);this.accVector=[0,0,0];}
  step(){
    const pc=this.pc,w=Number(this.load(pc,4,false,'execute')),op=w>>>26;
    if(![18,54,62].includes(op))return super.step();
    assert(pc>=0x1bfc78&&pc<=0x1bfc90&&w===CROSS_WORDS[(pc-0x1bfc78)/4],
      'unsupported vector instruction outside exact audited cross helper');
    assert(this.steps<this.maxSteps,'instruction step cap');
    const next=this.nextPC;this.pc=next;this.nextPC=next+4;this.steps++;this.inDelaySlot=false;
    const scratch=Buffer.alloc(4),readFloat=a=>{scratch.writeUInt32LE(Number(this.load(a,4)));const v=scratch.readFloatLE();
      assert(Number.isFinite(v)&&(v===0||Math.abs(v)>=2**-126),'finite-normal vector input');return v;};
    if(op===54){const rs=w>>>21&31,ft=w>>>16&31,a=this.address(rs,(w<<16)>>16);this.aligned(a,16);
      this.vectors[ft]=[0,1,2,3].map(i=>readFloat(a+4*i));return;}
    if(op===62){const rs=w>>>21&31,ft=w>>>16&31,a=this.address(rs,(w<<16)>>16);this.aligned(a,16);
      for(let i=0;i<4;i++){scratch.writeFloatLE(this.vectors[ft][i]);this.store(a+4*i,4,BigInt(scratch.readUInt32LE()));}return;}
    if(w===0x4bc522fe){const a=this.vectors[4],b=this.vectors[5];this.accVector=[F(a[1]*b[2]),F(a[2]*b[0]),F(a[0]*b[1])];return;}
    if(w===0x4bc429ae){const a=this.vectors[5],b=this.vectors[4];this.vectors[6]=[
      F(this.accVector[0]-F(a[1]*b[2])),F(this.accVector[1]-F(a[2]*b[0])),F(this.accVector[2]-F(a[0]*b[1])),0];return;}
    assert.equal(w,0x4a2631ac);this.vectors[6][3]=F(this.vectors[6][3]-this.vectors[6][3]);
  }
}
const cross=(a,b)=>[F(F(a[1]*b[2])-F(a[2]*b[1])),F(F(a[2]*b[0])-F(a[0]*b[2])),F(F(a[0]*b[1])-F(a[1]*b[0]))];
function signedDraw(raw){assert(Number.isInteger(raw)&&raw>=0&&raw<=0x7fffffff);
  const u=F(F((raw+0xc0000001)|0)*2**-30),square=F(u*u);return{u,signed_square:u<0?F(-square):square};}
function equation(v){
  const dx=signedDraw(v.raw[0]),dy=signedDraw(v.raw[1]),right=cross(v.direction,[0,1,0]),up=cross(right,v.direction);
  const x=F(v.accuracy[0]+F(v.accuracy[2]*dx.signed_square)),y=F(v.accuracy[1]+F(v.accuracy[2]*dy.signed_square));
  const output=v.direction.map((d,i)=>F(F(d+F(right[i]*x))+F(up[i]*y)));
  const length=Math.hypot(...output);
  return{draws:[dx,dy],basis:{right,up},axis_offsets:[x,y],raw_direction:output,
    normalized_direction_for_adapted_consumer:output.map(d=>d/length)};
}
function cases(){const rows=[];
  for(const direction of [[0,0,-1],[0,F(.6),F(-.8)],[1,0,0]])for(const [x,y]of[[0x3fffffff,0x3fffffff],[0,0],[0x7fffffff,0x7fffffff],[0x1fffffff,0x5fffffff]])
    rows.push({direction,raw:[x,y],accuracy:[0,0,F(.1)]});
  rows.push({direction:[0,0,-1],raw:[0x3fffffff,0x3fffffff],accuracy:[F(.02),F(-.03),F(.1)]});
  rows.push({direction:[0,1,0],raw:[0,0x7fffffff],accuracy:[0,0,F(.1)]});
  return rows;
}
function execute(v,core,seal,boot){
  const m=new CrossFixtureMachine(),BASE=0x10000000,STACK=0x10100000,SP=STACK+0x8000;
  m.map(core.base,core.bytes,{execute:true,name:'original core'});m.map(seal.base,seal.bytes,{execute:true,name:'original seal'});
  m.map(0x1bfc78,boot.bytes.subarray(boot.offset(0x1bfc78),boot.offset(0x1bfc90)+4),{execute:true,name:'original cross helper'});
  const record=m.map(BASE,Buffer.alloc(256),{write:true,name:'synthetic vector/accuracy inputs'});
  const stack=m.map(STACK,Buffer.alloc(65536),{write:true,name:'synthetic source call stack'});
  const vec=(at,value)=>value.forEach((n,i)=>record.writeFloatLE(n,at-BASE+4*i));
  vec(BASE,v.direction);vec(BASE+16,[0,1,0]);vec(BASE+64,v.accuracy);
  m.run(0x592400,{args:[BASE,BASE+16,BASE+32,0],stackPointer:SP});
  m.run(0x592400,{args:[BASE+32,BASE,BASE+48,0],stackPointer:SP});
  const actualRight=[0,1,2].map(i=>record.readFloatLE(32+i*4)),actualUp=[0,1,2].map(i=>record.readFloatLE(48+i*4));
  actualRight.forEach((n,i)=>stack.writeFloatLE(n,SP-STACK+128+4*i));actualUp.forEach((n,i)=>stack.writeFloatLE(n,SP-STACK+112+4*i));
  m.set64(16,BigInt(BASE+64));m.set64(17,BigInt(BASE));m.set64(29,BigInt(SP));
  const slice=(entry,stop)=>{m.pc=entry;m.nextPC=entry+4;m.steps=0;m.inDelaySlot=false;m.writes=0;
    while(m.pc!==stop)m.step();return{entry:'0x'+entry.toString(16),stop:'0x'+stop.toString(16),steps:m.steps};};
  // Explicit fixture boundary is immediately AFTER each original RNG call.
  m.set32(2,BigInt(v.raw[0]));const sx=slice(0x5922d4,0x557e10),x=m.float(12);
  const xVector=slice(0x557e10,0x592348);
  m.set32(2,BigInt(v.raw[1]));const sy=slice(0x592350,0x557e10),y=m.float(12);
  const final=slice(0x557e10,0x5923ec);
  const actual=[0,1,2].map(i=>record.readFloatLE(i*4)),expected=equation(v);
  assert.deepEqual(actualRight,expected.basis.right,'original unnormalized right cross');
  assert.deepEqual(actualUp,expected.basis.up,'original unnormalized up cross');
  assert.deepEqual([x,y],expected.axis_offsets,'original signed square offsets');
  assert.deepEqual(actual,expected.raw_direction,'original final direction operations');
  return{...v,expected,original_execution:{axis_offsets:[x,y],raw_direction:actual,slices:[sx,xVector,sy,final]}};
}
function audit(iso){const core=moduleImage('FTSCore.bin'),seal=moduleImage('ZSealEtc.bin'),boot=image(iso);
  CROSS_WORDS.forEach((word,i)=>assert.equal(boot.bytes.readUInt32LE(boot.offset(0x1bfc78+4*i)),word,'exact original cross helper'));
  assert.equal(seal.bytes.readUInt32LE(seal.offset(0x669524)),0x592260,'owner vtable slot116');
  assert.equal(core.bytes.readUInt32LE(core.offset(0x4083bc)),0x3d2d70,'weapon vtable slot12');
  const fixtures=cases().map(v=>execute(v,core,seal,boot));
  return{schema_version:1,status:'PASS',original_rng_calls_executed:false,external_stubs:0,
    inputs:[core,seal].map(m=>({file:m.name,sha256:hash(m.bytes)})).concat([{file:boot.boot,sha256:hash(boot.bytes)}]),
    fixtures,source_ranges:{distribution:disasm(seal,0x592260,0x592400),call_slot:disasm(seal,0x5bf530,0x5bf59c),
      direction_saved:disasm(seal,0x5c5378,0x5c538c),weapon_dispatch:disasm(seal,0x5c63c4,0x5c63f4),
      projectile_forward:disasm(core,0x3d2fb8,0x3d2fe4)},
    limitations:['Explicit supplied 31-bit RNG draws; original global RNG state/lifetime not executed',
      'Only exact original VU cross helper, not general VU emulation','Finite-normal float32 fixture domain',
      'Original direction is not normalized here; normalized report field is labeled adapted']};}
if(require.main===module){const[iso,output]=process.argv.slice(2);assert(iso,'ISO input required');const report=audit(iso);
  if(output){const p=path.resolve(output);assert(path.isAbsolute(output)&&(p.startsWith('/private/tmp/')||p===path.join(ROOT,'config/reference/socom2_fire_direction_vectors.json')),'new reference/temp report only');fs.writeFileSync(p,JSON.stringify(report,null,2)+'\n',{flag:'wx'});}
  console.log('SOURCE_FIRE_DIRECTION_AUDIT PASS vectors='+report.fixtures.length+' original_rng_draws=supplied external_stubs=0');}
module.exports={signedDraw,equation,cases,audit,CrossFixtureMachine};
