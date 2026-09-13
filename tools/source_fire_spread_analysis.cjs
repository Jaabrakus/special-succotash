'use strict';
// Original bytes and pure finite-normal float32 equation audit. No runtime edits.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {decode}=require('./source_loader_analysis.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const ROOT=path.resolve(__dirname,'..');
const DIRECTORY=path.join(ROOT,'art_source/socom2_ballistics_reference_20260912/decoded_runtime_v1');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const hex=n=>'0x'+(n>>>0).toString(16);
const F=Math.fround;
const FIELDS=[
  {tag:'AccBurstCnt_Min',string:0x3fc9b0,reader:0x3ce3f0,setter:0x3c62b0,offset:616,type:'i32'},
  {tag:'AccBurstCnt_Max',string:0x3fc9c0,reader:0x3ce420,setter:0x3c6260,offset:620,type:'i32'},
  {tag:'AccScalar_Min',string:0x3fc9d0,reader:0x3ce450,setter:0x3c6210,offset:624,type:'f32'},
  {tag:'AccScalar_Max',string:0x3fc9e0,reader:0x3ce480,setter:0x3c61c0,offset:628,type:'f32'},
  {tag:'TargetDilateUponFire',string:0x3fc770,reader:0x3cde40,setter:0x3c6140,offset:32,type:'stance_f32'},
  {tag:'TargetMin',string:0x3fc7e0,reader:0x3cdf00,setter:0x3c60f0,offset:52,type:'stance_f32'},
  {tag:'TargetMax',string:0x3fc7f0,reader:0x3cdf30,setter:0x3c60e0,offset:56,type:'stance_f32'}
];
function moduleImage(name){
  const manifest=JSON.parse(fs.readFileSync(path.join(DIRECTORY,'manifest.json'),'utf8'));
  const metadata=manifest.modules.find(m=>m.name===name);assert(metadata,'manifest module');
  const bytes=fs.readFileSync(path.join(DIRECTORY,name));assert.equal(hash(bytes),metadata.decodedSha256,'module checksum');
  assert.equal(bytes.length,metadata.decodedBytes);assert.equal(bytes.toString('ascii',0,4),'MWo3');
  const base=bytes.readUInt32LE(8);assert.equal(hex(base),metadata.base);
  return {name,metadata,bytes,base,offset(pc){const p=pc-base;assert(p>=0&&p+4<=bytes.length,'mapped original file');return p;}};
}
function disasm(img,start,end){assert(start%4===0&&end%4===0&&end>start&&end-start<65536);
  return Array.from({length:(end-start)/4},(_,i)=>{const pc=start+i*4,w=img.bytes.readUInt32LE(img.offset(pc));return{pc:hex(pc),file_offset:pc-img.base,word:hex(w),assembly:decode(w,pc)};});}
function finite(value){assert(Number.isFinite(value),'finite scalar');const v=F(value);assert(Number.isFinite(v)&&(v===0||Math.abs(v)>=2**-126),'finite-normal f32');return v;}
function equation(v){
  for(const key of ['countMin','countMax','shotCount'])assert(Number.isInteger(v[key])&&Math.abs(v[key])<0x1000000,'exact normal i32 fixture');
  const difference=F(v.countMax-v.countMin);
  const scalarMin=finite(v.scalarMin),scalarMax=finite(v.scalarMax);
  const slope=difference===0?0:finite(F(scalarMax-scalarMin)/difference);
  const count=v.shotCount+1-v.countMin;
  // Exact source cap is countMax, not countMax-countMin. No scalarMin add here.
  const burst=count<=0?0:finite(F(Math.min(count,v.countMax))*slope);
  const fire=finite(v.fire),prior=finite(v.prior),minimum=finite(v.minimum),maximum=finite(v.maximum);
  assert(minimum<=maximum,'ordered authored fixture limits');
  const increment=finite(fire+F(fire*burst)),unclamped=finite(prior+increment);
  const next=unclamped<minimum?minimum:unclamped>maximum?maximum:unclamped;
  return {slope,burst,increment,unclamped,previous:prior,next};
}
function vectors(){
  const v={countMin:4,countMax:7,scalarMin:0,scalarMax:F(.03),shotCount:0,fire:7,prior:1,minimum:1,maximum:26};
  return [...[0,2,3,4,6,7,9,10,30].map(shotCount=>({name:'M4A1 count '+shotCount,...v,shotCount})),
    {name:'equal denominator',...v,countMax:4,shotCount:8},
    {name:'upper clamp',...v,shotCount:5,prior:24},
    {name:'lower clamp',...v,fire:-7,prior:1},
    {name:'nonzero scalar minimum not added',...v,countMin:3,countMax:8,scalarMin:F(.2),scalarMax:F(2.8),shotCount:3,fire:1,maximum:100},
    {name:'constructor default slope zero',...v,countMin:0xffffff,countMax:0xffffff,scalarMin:1,scalarMax:1,shotCount:20}];
}
function executeFixtures(fixtures,core,seal){
  const WEAPON=0x10000000,ACTOR=0x10001000;
  const runSlice=(m,start,stop)=>{
    m.pc=start;m.nextPC=start+4;m.inDelaySlot=false;m.steps=0;m.writes=0;m.lastPCs=[];
    while(m.pc!==stop)m.step();
    return {steps:m.steps,writes:m.writes};
  };
  const results=[];
  for(const v of fixtures){
    const m=new FloatFixtureMachine({maxSteps:2000});
    m.map(core.base,core.bytes,{name:'original FTSCore read only',execute:true});
    m.map(seal.base,seal.bytes,{name:'original ZSealEtc read only',execute:true});
    const weapon=m.map(WEAPON,Buffer.alloc(1024),{name:'synthetic weapon',write:true});
    const actor=m.map(ACTOR,Buffer.alloc(4096),{name:'synthetic actor',write:true});
    // Proven original constructor defaults, followed by the original reader's setter order.
    weapon.writeInt32LE(0xffffff,616);weapon.writeInt32LE(0xffffff,620);
    weapon.writeFloatLE(1,624);weapon.writeFloatLE(1,628);
    const setterResults=[];
    for(const [entry,value,isFloat]of [[0x3c62b0,v.countMin,false],[0x3c6260,v.countMax,false],
      [0x3c6210,v.scalarMin,true],[0x3c61c0,v.scalarMax,true]]){
      if(isFloat)m.setFloat(12,value);
      const result=m.run(entry,{args:isFloat?[WEAPON]:[WEAPON,value]});
      setterResults.push({entry:hex(entry),steps:result.steps,writes:result.writes});
    }
    assert.equal(weapon.readFloatLE(632),v.expected.slope,'original slope '+v.name);
    m.set64(17,BigInt(WEAPON));m.set64(18,BigInt(ACTOR));
    actor.writeInt32LE(v.shotCount,2072);
    const burst=runSlice(m,0x5c3430,0x5c3490);
    assert.equal(m.float(22),v.expected.burst,'original burst '+v.name);
    actor.writeFloatLE(v.prior,2124);actor.writeFloatLE(-123,2128);
    m.setFloat(25,v.fire);m.setFloat(24,v.minimum);m.setFloat(23,v.maximum);
    const dilation=runSlice(m,0x5c36a8,0x5c36e8);
    assert.equal(actor.readFloatLE(2124),v.expected.next,'original dilation '+v.name);
    assert.equal(actor.readFloatLE(2128),v.expected.previous,'original prior copy '+v.name);
    // The declared actor inputs and two observed output fields are the only changed actor bytes.
    const expectedActor=Buffer.alloc(4096);expectedActor.writeInt32LE(v.shotCount,2072);
    expectedActor.writeFloatLE(v.expected.next,2124);expectedActor.writeFloatLE(v.expected.previous,2128);
    assert.deepEqual(actor,expectedActor,'only declared actor state touched');
    results.push({name:v.name,setters:setterResults,burst,dilation,outputs:{slope:weapon.readFloatLE(632),
      burst:m.float(22),next:actor.readFloatLE(2124),previous:actor.readFloatLE(2128)}});
  }
  return {status:'PASS',domain:'finite-normal IEEE float32 fixture interpreter, not complete R5900 FPU',
    external_stubs:0,cases:results};
}
function audit(){
  const core=moduleImage('FTSCore.bin'),seal=moduleImage('ZSealEtc.bin');
  for(const field of FIELDS){const p=core.offset(field.string),nul=core.bytes.indexOf(0,p);assert.equal(core.bytes.toString('ascii',p,nul),field.tag,'verified source tag');
    const instructions=disasm(core,field.reader,field.reader+0x34);assert(instructions.some(r=>r.assembly==='jal '+hex(field.setter)),'named setter call');}
  // Pin the exact distinct source operations that define the pure equation.
  for(const [pc,word]of [[0x3c61f4,0x46000801],[0x3c61f8,0x46020003]])assert.equal(core.bytes.readUInt32LE(core.offset(pc)),word);
  for(const [pc,word]of [[0x5c3440,0x24630001],[0x5c3444,0x00629823],[0x5c3488,0x46000d82],
    [0x5c36a8,0x4616c802],[0x5c36b0,0x4600c840]])assert.equal(seal.bytes.readUInt32LE(seal.offset(pc)),word,'source equation opcode '+hex(pc));
  const fixtureRows=vectors().map(v=>({...v,expected:equation(v)}));
  assert.equal(fixtureRows[2].expected.burst,0);assert(fixtureRows[3].expected.burst>0);
  assert.equal(fixtureRows[7].expected.burst,fixtureRows[8].expected.burst,'raw maximum cap');
  assert.equal(fixtureRows[9].expected.slope,0);assert.equal(fixtureRows[10].expected.next,26);assert.equal(fixtureRows[11].expected.next,1);
  const execution=executeFixtures(fixtureRows,core,seal);
  return{schema_version:1,status:'original reader and equation audit; runtime not changed',
    mapping:'header-retained bases; includes file offsets so mapping remains auditable',
    inputs:[core,seal].map(i=>({file:i.name,sha256:hash(i.bytes),base:hex(i.base)})),fields:FIELDS,
    source_ranges:{slope:disasm(core,0x3c61c0,0x3c6210),burst:disasm(seal,0x5c3430,0x5c3490),
      dilation:disasm(seal,0x5c36a8,0x5c36e8)},fixtures:fixtureRows,original_instruction_execution:execution,
    limitations:['Not complete R5900 floating-point semantics','Reticle dilation units are not proven degrees',
      'Burst counter/reset ownership and downstream shot dispersion not proven here',
      'Nested AccuracyBurstCnt/AccuracyScalar tags are not the named top-level reader fields']};
}
if(require.main===module){const report=audit(),output=process.argv[2];if(output){
  const resolved=path.resolve(output),reference=path.join(ROOT,'config/reference/socom2_fire_dilation_vectors.json');
  assert(path.isAbsolute(output)&&(resolved.startsWith('/private/tmp/')||resolved===reference),'new temporary/reference report only');
  fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});}
  console.log('SOURCE_FIRE_SPREAD_AUDIT PASS fields='+report.fields.length+' vectors='+report.fixtures.length+' original_execution='+report.original_instruction_execution.status);}
module.exports={moduleImage,disasm,equation,vectors,audit,executeFixtures,FIELDS};
