'use strict';
// Offline original-instruction audit only. No live profile, asset or runtime writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const F = Math.fround;
const BASE = 0x10000000, ACTOR = BASE, CLIP = BASE + 0x2000;
const STATE = BASE + 0x3000, INSTANCE = BASE + 0x3100, LINK = BASE + 0x3200;
const POSE = BASE + 0x4000, TABLE = BASE + 0x4200, STACK = BASE + 0x7800;
const HASHES = {
  'FTSCore.bin': 'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
  'ZSealEtc.bin': 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'
};
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const at = address => address - BASE;
function easeRemaining(x) {
  x = F(x);
  if (x <= .5) return F(F(2 * x) * x);
  const twice = F(2 * F(x - 1));
  return F(1 - F(F(.5 * twice) * twice));
}
function slice(m, start, stop) {
  m.pc = start; m.nextPC = start + 4; m.inDelaySlot = false;
  m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function audit() {
  const core = moduleImage('FTSCore.bin'), seal = moduleImage('ZSealEtc.bin');
  for (const im of [core, seal]) assert.equal(sha(im.bytes), HASHES[im.name]);
  const m = new FloatFixtureMachine({maxSteps: 8000});
  for (const im of [core, seal]) m.map(im.base, im.bytes, {execute: true, name: 'pinned original ' + im.name});
  const b = m.map(BASE, Buffer.alloc(0x8000), {write: true, name: 'disclosed synthetic actor, clips, pose and stack'});
  function setup() { m.set64(29, BigInt(STACK)); }
  const curve = [];
  for (const input of [0, .001, .1, .25, .499, .5, .501, .75, .9, .999, 1]) {
    m.setFloat(12, input);
    const r = m.run(0x2874f0);
    assert.equal(m.float(0), easeRemaining(input));
    curve.push({remaining_fraction: F(input), old_pose_weight: m.float(0), new_pose_weight: F(1 - m.float(0)), steps: r.steps});
  }
  const timers = [];
  for (const [remaining, duration, delta] of [[.5,.5,0],[.5,.5,1/60],[.5,.5,.125],
    [.5,.5,.25],[.5,.5,.375],[.5,.5,.5],[.5,.5,.75],[.03,.4,.016],[.03,.4,.1]]) {
    b.writeFloatLE(remaining, 376); b.writeFloatLE(duration, 380); b.writeFloatLE(delta, 736);
    m.set64(17, BigInt(ACTOR)); m.setFloat(2, 0); setup();
    const steps = slice(m, 0x576898, 0x5768d4);
    const expected = Math.max(0, F(F(remaining) - F(delta)));
    assert.equal(b.readFloatLE(376), expected);
    assert.equal(m.float(0), easeRemaining(F(expected / F(duration))));
    timers.push({remaining: F(remaining), duration: F(duration), delta: F(delta), next_remaining: expected,
      old_pose_weight: m.float(0), steps});
  }
  const snapshots = [];
  b.writeUInt32LE(2, 368 + 96); b.writeUInt32LE(TABLE, 368 + 100);
  b.writeUInt32LE(POSE, at(TABLE)); b.writeUInt32LE(0, at(TABLE) + 4);
  const first = [1,2,3], quaternion = [.1,.2,.3,.9].map(F);
  first.forEach((v,i) => b.writeFloatLE(v, at(POSE) + i * 4));
  quaternion.forEach((v,i) => b.writeFloatLE(v, at(POSE) + 32 + i * 4));
  let r = m.run(0x28e3e0, {args: [ACTOR + 368]});
  const read = (offset,n) => Array.from({length:n},(_,i)=>b.readFloatLE(at(POSE)+offset+i*4));
  assert.deepEqual(read(16,3), first); assert.deepEqual(read(48,4), quaternion);
  snapshots.push({event:'transition start', steps:r.steps, frozen_position:read(16,3), frozen_quaternion:read(48,4)});
  [7,8,9].forEach((v,i) => b.writeFloatLE(v,at(POSE)+i*4));
  assert.deepEqual(read(16,3),first, 'evaluated incoming pose cannot advance outgoing snapshot');
  r = m.run(0x28e3e0, {args:[ACTOR+368]});
  assert.deepEqual(read(16,3),[7,8,9]);
  snapshots.push({event:'interrupted transition snapshots current result again', steps:r.steps, frozen_position:read(16,3)});

  const manifestFile = path.resolve(__dirname, '../assets/animations/seal_reference/manifest.json');
  const manifestBytes = fs.readFileSync(manifestFile), manifest = JSON.parse(manifestBytes);
  const periods = [];
  for (const name of ['seal_stand','seal_stand_alert01','seal_stand_alert02','seal_crouch','seal_prone',
    'seal_p_stand','seal_p_crouch','seal_run','seal_walk','seal_jog','seal_p_run','seal_p_mv_reload',
    'seal_dive2prone','seal_runningjump']) {
    const row = manifest.clips.find(x => x.name === name);
    if (!row) {periods.push({name,status:'not in retained manifest'});continue;}
    const settings = row.settings;
    assert(settings && Number.isFinite(settings.playback) && settings.playback > 0, name + ' playback field');
    const loop = Boolean(settings.looped), disabledVelocity = settings.max_velocity < 0;
    b.fill(0,at(CLIP),at(CLIP)+128);
    b[at(CLIP)+73] = (loop ? 64 : 0) | (disabledVelocity ? 128 : 0);
    b.writeFloatLE(row.duration,at(CLIP)+16);
    b.writeUInt32LE(CLIP,at(STACK)+264); b[at(STACK)+271]=loop?1:0;
    b.writeFloatLE(settings.playback,at(STACK)+256);
    setup(); m.set64(3,BigInt(loop?1:0)); m.setFloat(1,1);
    const steps = slice(m,0x2879a8,0x287a08);
    const period = loop && !disabledVelocity ? F(F(row.duration)/F(settings.playback)) : F(settings.playback);
    assert.equal(b.readFloatLE(at(CLIP)+16),period,name+' original reader period');
    b.writeUInt16LE(row.source_frames,at(CLIP)+4);
    const factor = m.run(0x28ada0,{args:[CLIP]});
    const expectedFactor = loop || row.source_frames < 2 ? 1 : F(F(row.source_frames-1)/F(row.source_frames));
    assert.equal(m.float(0),expectedFactor,name+' original span factor');
    periods.push({name,status:'PASS',source_frames:row.source_frames,raw_duration:F(row.duration),
      source_settings:settings,period_field_16:period,terminal_span_factor:m.float(0),
      phase_denominator:F(period*m.float(0)),original_steps:{reader:steps,span:factor.steps},
      godot_unmodified_clip_rate_for_original_loop:loop?F(F(row.duration)/period):null});
  }
  assert.equal(periods.find(x=>x.name==='seal_stand').period_field_16,6);
  assert.equal(periods.find(x=>x.name==='seal_run').period_field_16,F(.633333325386047));

  // Execute the complete original clock function with a single real list entry.
  // No external calls are stubbed. Clip values are disclosed synthetic records.
  b.writeUInt32LE(1,at(STATE)+48); b.writeUInt32LE(LINK,at(STATE)+52);
  b.writeUInt32LE(INSTANCE,at(LINK)+4); b.writeUInt32LE(0,at(LINK)+8);
  b.writeUInt32LE(CLIP,at(INSTANCE)+4); b.writeFloatLE(1,at(INSTANCE)+8);
  b.writeFloatLE(1,at(INSTANCE)+24); b.writeFloatLE(1,at(INSTANCE)+36);
  b.writeFloatLE(1,at(STATE)+12);
  const clocks = [];
  for (const [period,loop,phase,delta,speed] of [[6,true,0,1,1],[6,true,.9,1,1],
    [.5,true,.75,.125,1],[.5,true,.75,.25,1],[.5,true,.1,.2,-1],
    [.5,false,.9,.2,1],[.5,false,.1,.2,-1],[2,true,.1,.2,2]]) {
    b.writeFloatLE(period,at(CLIP)+16);b.writeUInt16LE(16,at(CLIP)+4);b[at(CLIP)+73]=loop?64:0;
    b.writeFloatLE(phase,at(STATE)+28);b.writeUInt16LE(loop?64:0,at(STATE)+40);
    b.writeFloatLE(speed,at(INSTANCE)+36);m.setFloat(12,delta);
    const run=m.run(0x28c4f0,{args:[STATE,1],stackPointer:STACK});
    const span=loop?1:F(15/16),increment=F(F(F(delta)*F(speed))/F(F(period)*span));
    let expected=F(increment+F(phase));
    if(loop){while(expected>1)expected=F(expected-1);while(expected<0)expected=F(expected+1);}
    else expected=Math.max(0,Math.min(1,expected));
    assert.equal(m.float(0),expected);assert.equal(b.readFloatLE(at(STATE)+28),expected);
    clocks.push({period,loop,previous_phase:F(phase),delta:F(delta),speed,phase:expected,steps:run.steps});
  }
  const weightedClocks = [];
  // Source accumulates weighted frequencies, not an arithmetic mean of periods.
  // All per-entry time-scale fields are 1 here; velocity writers are not inferred.
  const clip2=CLIP+128, instance2=INSTANCE+64, link2=LINK+32;
  b.writeUInt32LE(link2,at(LINK)+8);b.writeUInt32LE(instance2,at(link2)+4);b.writeUInt32LE(0,at(link2)+8);
  b.writeUInt32LE(clip2,at(instance2)+4);b.writeFloatLE(1,at(instance2)+24);b.writeFloatLE(1,at(instance2)+36);
  b.writeUInt16LE(16,at(clip2)+4);b[at(clip2)+73]=64;
  for(const [a,z,wa,delta] of [[.5,1,.5,.1],[.633333325,.833333313,.5,1/60],[.6,.9,.25,.2]]){
    const weights=[F(wa),F(1-wa)],periods=[F(a),F(z)];
    b.writeFloatLE(a,at(CLIP)+16);b[at(CLIP)+73]=64;b.writeFloatLE(z,at(clip2)+16);
    b.writeFloatLE(weights[0],at(INSTANCE)+8);b.writeFloatLE(weights[1],at(instance2)+8);
    b.writeFloatLE(1,at(INSTANCE)+36);b.writeFloatLE(0,at(STATE)+28);b.writeUInt16LE(64,at(STATE)+40);
    m.setFloat(12,delta);const run=m.run(0x28c4f0,{args:[STATE,1],stackPointer:STACK});
    const expected=F(F(F(F(delta)*weights[0])/periods[0])+F(F(F(delta)*weights[1])/periods[1]));
    assert.equal(m.float(0),expected);
    weightedClocks.push({periods,weights,delta:F(delta),phase_increment:expected,steps:run.steps,
      arithmetic_mean_period_phase_increment:F(F(delta)/F(F(periods[0]*weights[0])+F(periods[1]*weights[1])))});
  }
  const restartPolicy = [];
  for(const oldLoop of [false,true]) for(const newLoop of [false,true]){
    b.writeFloatLE(0,at(STATE)+28);b.writeUInt16LE(newLoop?64:0,at(STATE)+40);
    m.set64(18,BigInt(STATE));m.set64(19,oldLoop?1n:0n);m.setFloat(20,.375);
    const steps=slice(m,0x28def0,0x28df40);
    const phase=b.readFloatLE(at(STATE)+28),flags=b.readUInt16LE(at(STATE)+40);
    assert.equal(phase,oldLoop&&newLoop?.375:0);assert.equal(Boolean(flags&8),!newLoop);
    restartPolicy.push({old_loop:oldLoop,new_loop:newLoop,old_phase:.375,new_phase:phase,
      skip_first_clock_advance:Boolean(flags&8),steps});
  }
  // The new nonloop flag0x8 is consumed once, before any time increment.
  b.writeUInt32LE(0,at(LINK)+8);b.writeFloatLE(1,at(INSTANCE)+8);
  b.writeFloatLE(1,at(INSTANCE)+36);b.writeFloatLE(.5,at(CLIP)+16);b[at(CLIP)+73]=0;
  b.writeFloatLE(0,at(STATE)+28);b.writeUInt16LE(8,at(STATE)+40);m.setFloat(12,.1);
  const pause=m.run(0x28c4f0,{args:[STATE,1],stackPointer:STACK});
  assert.equal(m.float(0),0);assert.equal(b.readUInt16LE(at(STATE)+40)&8,0);
  const directSnapshotCalls={};
  for(const im of [core,seal]){
    const calls=[];
    for(let offset=64;offset<im.bytes.length-4;offset+=4){const w=im.bytes.readUInt32LE(offset);
      if((w>>>26)===3&&(w&0x3ffffff)*4===0x28e3e0)calls.push('0x'+(im.base+offset).toString(16));}
    directSnapshotCalls[im.name]=calls;
  }
  return {schema_version:1,status:'PASS',source_hashes:HASHES,manifest:{file:manifestFile,sha256:sha(manifestBytes)},
    counts:{curve:curve.length,timers:timers.length,snapshots:snapshots.length,periods:periods.filter(x=>x.status==='PASS').length,clocks:clocks.length,weighted_clocks:weightedClocks.length,restart_policy:restartPolicy.length,first_frame_pause:1},
    unknown_stubs:0,curve,timers,snapshots,periods,clocks,weighted_clocks:weightedClocks,restart_policy:restartPolicy,
    first_frame_pause:{steps:pause.steps,phase:0,skip_flag_cleared:true},direct_snapshot_calls:directSnapshotCalls,
    source_ranges:{ordinary_transition:disasm(seal,0x576860,0x576908),curve:disasm(core,0x2874f0,0x287550),
      snapshot:disasm(core,0x28e3e0,0x28e480),blend_application:disasm(core,0x28e0d0,0x28e1b0),
      blend_time_reader:disasm(core,0x287f28,0x287fd0),playback_reader:disasm(core,0x287820,0x287a08),
      clock:disasm(core,0x28c4f0,0x28c6e0),span:disasm(core,0x28ada0,0x28ae38),
      preserve_loop_phase_and_first_frame:disasm(core,0x28ded8,0x28df40),
      quaternion_blend:disasm(core,0x306ae0,0x306d34)},
    limitations:['Finite-normal IEEE float32 interpreter; not bitwise complete R5900/VU parity.',
      'Original vector/quaternion blend calls statically identified but VU helper not executed by this scalar fixture.',
      'Single/multiple-entry clock fixtures and action-switch slice do not prove every controller path or velocity input meaning.',
      'Actor +4304 special transition branch excluded; ordinary +376/+380 path only.',
      'Nonloop action timing must not override authoritative gameplay clocks without separate source/owner mapping.',
      'No canonical runtime activation or rendered fidelity claimed by this offline audit.']};
}
if(require.main===module){const r=audit(),arg=process.argv.find(x=>x.startsWith('--output='));if(arg){
  const file=path.resolve(arg.slice(9));assert(file.startsWith('/private/tmp/'),'new temporary report only');
  fs.writeFileSync(file,JSON.stringify(r,null,2)+'\n',{flag:'wx'});}
  console.log('SOURCE_BLEND_RUNTIME PASS '+JSON.stringify(r.counts)+' unknown_stubs=0');}
module.exports={audit,easeRemaining};
