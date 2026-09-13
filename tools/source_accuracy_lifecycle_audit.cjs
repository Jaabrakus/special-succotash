'use strict';
// Observer only: original instruction fixtures, no runtime/profile mutation.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {moduleImage,disasm,equation:fireEquation}=require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine}=require('./source_mips_float_fixture.cjs');
const ROOT=path.resolve(__dirname,'..'),F=Math.fround;
const CTRL=0x10000000,BODY=0x10002000,PROXY=0x10004000,STANCE=0x10006000,INPUT=0x10007000;
const bitsFloat=bits=>{const b=Buffer.alloc(4);b.writeUInt32LE(bits);return b.readFloatLE();};
const LINEAR=bitsFloat(0x3c7c0fc1),ANGULAR=bitsFloat(0x40a947ae);
function slice(m,start,stops){m.pc=start;m.nextPC=start+4;m.inDelaySlot=false;m.steps=0;m.lastPCs=[];
  while(!stops.includes(m.pc))m.step();return{steps:m.steps,stop:'0x'+m.pc.toString(16)};}
function machine(){const m=new FloatFixtureMachine({maxSteps:2000});
  for(const name of ['FTSCore.bin','ZSealEtc.bin']){const i=moduleImage(name);m.map(i.base,i.bytes,{name,execute:true});}
  const regions={};for(const [name,address,size]of[['ctrl',CTRL,4096],['body',BODY,6000],['proxy',PROXY,4096],['stance',STANCE,256],['input',INPUT,512]])
    regions[name]=m.map(address,Buffer.alloc(size),{name:'synthetic '+name,write:true});
  regions.ctrl.writeUInt32LE(BODY,2096);regions.body.writeUInt32LE(INPUT,192);
  m.set64(17,BigInt(STANCE));m.set64(18,BigInt(CTRL));
  return{m,...regions};}
function trigger(old,down){assert([0,1,2,3].includes(old));return down?(old===0||old===3?2:1):(old===1||old===2?3:0);}
function normSq(v){return F(F(F(v[0]*v[0])+F(v[1]*v[1]))+F(v[2]*v[2]));}
function movementGoal(v){let goal=F(F(LINEAR*normSq(v.linear))*v.multiplier);
  goal=F(goal+F(30*F(ANGULAR*normSq(v.angular))));
  goal=F(goal+F(30*F(ANGULAR*F(v.extra*v.extra))));
  if(v.special)goal=F(goal+F(LINEAR*normSq(v.specialVector)));
  // Preserve the redundant source subtraction+addition, including float32 rounding.
  const preliminaryMax=F(v.minimum+F(v.maximum-v.minimum));
  if(goal>preliminaryMax)goal=preliminaryMax;
  return goal<v.minimum?v.minimum:goal>v.maximum?v.maximum:goal;}
function recover(v){const prior=Math.max(v.prior,v.minimum);
  const amount=F(v.constrict*v.delta);
  const next=prior<v.goal?Math.min(F(prior+v.expand),v.goal):prior>v.goal?Math.max(F(prior-amount),v.goal):prior;
  return{prior,next};}
function recoilReturn(value,rate,delta){const amount=F(rate*delta);return value>0?Math.max(F(value-amount),0):value<0?Math.min(F(value+amount),0):value;}
function setVec(buffer,offset,values){for(let i=0;i<3;i++)buffer.writeFloatLE(values[i],offset+i*4);}
function audit(){const core=moduleImage('FTSCore.bin'),seal=moduleImage('ZSealEtc.bin');const triggers=[];
  for(const old of[0,1,2,3])for(const down of[false,true]){const{m,input}=machine();input[280]=old;
    const result=m.run(0x597790,{args:[INPUT,Number(down)]});const next=input[280];assert.equal(next,trigger(old,down));
    triggers.push({old,down,next,steps:result.steps});}
  const resets=[];for(const state of[0,1,2,3]){const{m,ctrl,input}=machine();input[280]=state;ctrl.writeInt32LE(7,2072);m.set64(19,BigInt(CTRL));
    const run=slice(m,0x5c0b48,[0x5c0b60,0x5c0bc0,0x5c0c10]);const count=ctrl.readInt32LE(2072);
    assert.equal(count,state===0||state===3?0:7);resets.push({state,count,...run});}
  const movementCases=[
    {name:'stationary',linear:[0,0,0],angular:[0,0,0],extra:0,multiplier:13,minimum:1,maximum:26},
    {name:'linear original units 5',linear:[5,0,0],angular:[0,0,0],extra:0,multiplier:13,minimum:1,maximum:26},
    {name:'linear original units 10',linear:[0,0,10],angular:[0,0,0],extra:0,multiplier:13,minimum:1,maximum:26},
    {name:'angular original units .1',linear:[0,0,0],angular:[0,F(.1),0],extra:0,multiplier:13,minimum:1,maximum:26},
    {name:'field96 contribution .2',linear:[0,0,0],angular:[0,0,0],extra:F(.2),multiplier:13,minimum:1,maximum:26},
    {name:'combined',linear:[3,4,1],angular:[F(.03),F(.05),F(.07)],extra:F(.11),multiplier:13,minimum:1,maximum:26},
    {name:'upper clamp',linear:[0,40,0],angular:[0,1,0],extra:0,multiplier:13,minimum:1,maximum:26},
    {name:'proxy and special contribution',linear:[5,0,0],angular:[0,0,0],extra:0,multiplier:13,minimum:1,maximum:26,proxy:true,special:true,specialVector:[10,0,0]},
  ];
  const movement=movementCases.map(v=>{const{m,ctrl,body,proxy,stance}=machine();const selected=v.proxy?proxy:body;
    body.writeUInt32LE(v.proxy?PROXY:0,3768);setVec(selected,44,v.linear);setVec(selected,68,v.angular);selected.writeFloatLE(v.extra,96);
    if(v.special){body[4190]=0x20;setVec(body,4944,v.specialVector);}stance.writeFloatLE(v.multiplier,40);
    ctrl.writeFloatLE(v.minimum,2164);ctrl.writeFloatLE(v.maximum,2160);const execution=slice(m,0x5c2870,[0x5c29c0]);
    const expected=movementGoal(v),actual=ctrl.readFloatLE(2156);assert.equal(actual,expected,v.name);return{...v,expected,actual,execution};});
  const base={prior:10,minimum:1,goal:1,expand:1,constrict:50,delta:F(1/30)};
  const recoveryCases=[{name:'recovery 30Hz input',...base},{name:'recovery 60Hz input',...base,delta:F(1/60)},
    {name:'recovery zero elapsed',...base,delta:0},{name:'recovery stop at goal',...base,prior:2},
    {name:'expand 30Hz input',...base,prior:1,goal:20},{name:'expand 60Hz input',...base,prior:1,goal:20,delta:F(1/60)},
    {name:'expand zero elapsed',...base,prior:1,goal:20,delta:0},{name:'expand stop at goal',...base,prior:19.5,goal:20},
    {name:'stable',...base,prior:1},{name:'new minimum preclamp',...base,prior:0},
    {name:'crouch recovery',...base,constrict:55},{name:'stance lower max is not instantaneous cap',...base,prior:26,goal:25}];
  const recovery=recoveryCases.map(v=>{const{m,ctrl,stance}=machine();ctrl.writeFloatLE(v.prior,2124);ctrl.writeFloatLE(-100,2128);
    ctrl.writeFloatLE(v.minimum,2164);ctrl.writeFloatLE(v.goal,2156);stance.writeFloatLE(v.expand,36);stance.writeFloatLE(v.constrict,48);m.setFloat(20,v.delta);
    slice(m,0x5c2790,[0x5c27a8]);m.set64(4,BigInt(STANCE));const execution=slice(m,0x5c29d8,[0x5c2a60]);
    const expected=recover(v),actual={prior:ctrl.readFloatLE(2128),next:ctrl.readFloatLE(2124)};assert.deepEqual(actual,expected,v.name);return{...v,expected,actual,execution};});
  const recoil=[];for(const delta of[0,F(1/30),F(1/60)])for(const pair of[[10,-10],[F(.01),F(-.01)],[0,0]]){
    const{m,ctrl,stance}=machine();stance.writeFloatLE(12,4);ctrl.writeFloatLE(pair[0],32);ctrl.writeFloatLE(pair[1],36);m.setFloat(20,delta);
    const execution=slice(m,0x5c27a8,[0x5c2870]);const expected=pair.map(x=>recoilReturn(x,12,delta));const actual=[ctrl.readFloatLE(32),ctrl.readFloatLE(36)];
    assert.deepEqual(actual,expected);recoil.push({delta,rate:12,input:pair,expected,actual,execution});}
  const indexing=[];for(const before of[0,1,2,3,4,7]){const{m,ctrl}=machine();ctrl.writeInt32LE(before,2072);m.set64(21,BigInt(CTRL));
    const execution=slice(m,0x5bf228,[0x5bf23c]);const callbackCount=ctrl.readInt32LE(2072);assert.equal(callbackCount,before+1);
    const sourceFire=fireEquation({countMin:4,countMax:7,scalarMin:0,scalarMax:F(.03),shotCount:callbackCount,fire:7,prior:1,minimum:1,maximum:26});
    indexing.push({before,callbackCount,equationCount:callbackCount+1,burst:sourceFire.burst,execution});}
  const pitch=[];for(const [old,next,delta]of[[0,F(.1),F(1/30)],[0,F(-.1),F(1/30)],[F(.5),F(.5),F(1/60)],[F(.5),F(.51),F(1/60)]]){
    const{m,body,input}=machine();m.set64(17,BigInt(BODY));m.set64(18,BigInt(INPUT));m.setFloat(20,old);m.setFloat(24,delta);input.writeFloatLE(next,304);
    const execution=slice(m,0x594b2c,[0x594b3c]);const actual=body.readFloatLE(96),expected=F(F(old-next)/delta);assert.equal(actual,expected);
    pitch.push({old,next,delta,expected,actual,execution});}
  const clock=[];for(const frequency of[15734,15550,31468])for(const ticks of[262,525]){
    const{m}=machine();const globals=m.map(0x49e000,Buffer.alloc(0x8000),{name:'synthetic original clock globals',write:true});
    // The selected video-mode float-to-integer rounding occurs upstream; fixture input
    // is that original integer denominator, not a claimed full hardware emulation.
    const coefficient=m.run(0x34f178,{args:[frequency]});const reciprocal=globals.readFloatLE(0x2d8);assert.equal(reciprocal,F(1/F(frequency)));
    globals.writeUInt32LE(ticks,0x6538);const execution=slice(m,0x3b00d0,[0x3b0148]);const actual=globals.readFloatLE(0x649c),expected=F(F(ticks)*reciprocal);
    assert.equal(actual,expected);assert.equal(globals.readBigUInt64LE(0x6490),1n);clock.push({frequency,ticks,reciprocal,expected,actual,coefficient_steps:coefficient.steps,execution});}
  return{schema_version:1,status:'PASS',mode:'offline observer; no runtime changes',sources:[core,seal].map(i=>({file:i.name,sha256:i.metadata.decodedSha256,base:i.metadata.base})),
    original_execution:{domain:'finite-normal host IEEE float32 instruction interpreter, not complete R5900 FPU',unknown_call_stubs:0},
    trigger_states:{0:'idle/up',1:'held/down',2:'new press/falling edge',3:'released/rising edge'},triggers,resets,movement,recovery,recoil,indexing,pitch,clock,
    equations:{movement:'clamp((float3(entity+44).norm_squared/65)*stance+40 + 30*5.29*(float3(entity+68).norm_squared + float(entity+96)^2) + optional float3(seal+4944).norm_squared/65,min,max); exact float32 order in observer',
      recovery:'if current < goal: min(current + TargetDilateUponMovement, goal); else max(current - TargetConstrict*delta,goal)',
      counter:'reset on input 0 or 3; ordinary firearm admitted attempt increments before muzzle validation and pellet loop; on-fire equation reads that count + 1'},
    source_ranges:{trigger:disasm(seal,0x597790,0x597808),reset:disasm(seal,0x5c0b48,0x5c0c10),movement:disasm(seal,0x5c2870,0x5c29c0),
      recovery:disasm(seal,0x5c29d8,0x5c2a60),minimum:disasm(seal,0x5c2790,0x5c27a8),indexing:disasm(seal,0x5bf228,0x5bf244),
      update_order:disasm(seal,0x5c1040,0x5c1058),projection_caller:disasm(seal,0x596438,0x596454),pitch_writer:disasm(seal,0x594b20,0x594b3c),
      local_velocity_writer:disasm(seal,0x57ab08,0x57ab94),velocity_displacement:disasm(seal,0x54dd10,0x54dd68),yaw_rate_writer:disasm(seal,0x551a30,0x551a48),
      clock_conversion:disasm(core,0x3b00d0,0x3b0148),clock_coefficient:disasm(core,0x34f178,0x34f1dc),application_loop:disasm(core,0x1e70d0,0x1e70f4)},
    limitations:['Local velocity and pitch-rate writers are identified; source-to-Godot metre scale and all special movement paths remain separate calibration work',
      'Original elapsed clock is verified; fixed source update cadence is not established because source updates use sampled elapsed time',
      'Source counter can increment before a failed muzzle validation; accepted-shot-only counting is an adaptation',
      'Projection is cached separately; firing dilation does not imply an immediate spread refresh between shotgun pellets',
      'Reload, equip and special weapon paths can bypass trigger evaluation; not all counter writes are trigger-release resets']};}
if(require.main===module){const report=audit();if(process.argv[2]){const output=path.resolve(process.argv[2]);assert(output===path.join(ROOT,'config/reference/socom2_accuracy_lifecycle_vectors.json')||output.startsWith('/private/tmp/'),'new reference or temporary report only');fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});}
  console.log('SOURCE_ACCURACY_LIFECYCLE PASS trigger='+report.triggers.length+' reset='+report.resets.length+' movement='+report.movement.length+' recovery='+report.recovery.length+' recoil='+report.recoil.length+' indexing='+report.indexing.length+' pitch='+report.pitch.length+' clock='+report.clock.length+' unknown_stubs=0');}
module.exports={audit,trigger,movementGoal,recover,recoilReturn};
