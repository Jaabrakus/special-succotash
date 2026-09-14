'use strict';
// Read-only original code observer; no runtime, source-asset or profile writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {moduleImage, disasm} = require('./source_fire_spread_analysis.cjs');
const {image} = require('./source_loader_analysis.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const ISO = '/Users/kiwimango/Downloads/SOCOM II - U.S. Navy SEALs (USA)/SOCOM II - U.S. Navy SEALs (USA).iso';
const B = 0x10000000, SP = B + 0x7000, LIST = B + 0x100, NODES = B + 0x200, POOL = B + 0x400, ITEMS = B + 0x1000;
const HASHES = {
  boot: '0172dc0bec19c83d1fe2d0fec0a290f41cc5d32efa14ed6859ca92773c05346c',
  core: 'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',
  seal: 'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'
};
function sha(b) { return crypto.createHash('sha256').update(b).digest('hex'); }
function slice(m, first, stop) {
  m.pc = first; m.nextPC = first + 4; m.inDelaySlot = false; m.steps = 0; m.lastPCs = [];
  while (m.pc !== stop) m.step();
  return m.steps;
}
function audit() {
  const boot = image(ISO), core = moduleImage('FTSCore.bin'), seal = moduleImage('ZSealEtc.bin');
  for (const [name, im] of Object.entries({boot, core, seal})) assert.equal(sha(im.bytes), HASHES[name]);
  function machine() {
    const m = new FloatFixtureMachine({maxSteps: 20000});
    for (const [lo, hi] of [[0x1ae000, 0x1b4000], [0x1d0000, 0x1d4000]])
      m.map(lo, boot.bytes.subarray(boot.offset(lo), boot.offset(hi)), {execute:true, name:'original boot math'});
    m.map(core.base, core.bytes, {execute:true, name:'original FTSCore'});
    const output = 0x64fc80, outputOffset = seal.offset(output);
    m.map(seal.base, seal.bytes.subarray(0,outputOffset), {execute:true, name:'original ZSealEtc before scalar'});
    const scalar = m.map(output, seal.bytes.subarray(outputOffset,outputOffset+4), {write:true, name:'original output scalar'});
    m.map(output+4, seal.bytes.subarray(outputOffset+4), {execute:true, name:'original ZSealEtc after scalar'});
    const b = m.map(B, Buffer.alloc(0x8000), {write:true, name:'disclosed synthetic weights/stack'});
    return {m, b, scalar};
  }
  const angular = [];
  for (const [lateral, longitudinal] of [[0,0], [0,1], [1,0], [1,1], [.5,1], [.2,1], [1,.2], [-.5,1], [.5,-1], [-.5,-1], [.01,.02], [.02,.01], [0,-1], [-1,0], [.25,.5], [.5,.25], [2,1], [.25,1], [1,.25]]) {
    const {m,b,scalar} = machine();
    m.setFloat(12,lateral); m.setFloat(13,longitudinal);
    const result = m.run(0x583350,{args:[0,B,B+4],stackPointer:SP});
    const x = Math.fround(lateral), y = Math.abs(Math.fround(longitudinal)) <= Math.fround(.03) ? 0 : Math.fround(longitudinal);
    const magnitude = Math.sqrt(x*x+y*y);
    const expected = magnitude > 0 ? Math.asin(Math.min(1,Math.abs(x)/magnitude))*2/Math.PI : 0;
    const actual = b.readFloatLE(0), forward = b.readFloatLE(4);
    assert(Math.abs(actual-expected)<1e-6, 'angular direction weight');
    assert(Math.abs(actual+forward-1)<1e-6, 'complementary weight');
    assert(Math.abs(m.float(0)-Math.min(magnitude,1))<1e-6,'returned analog magnitude');
    const normalizer = scalar.readFloatLE(0);
    assert(Math.abs(normalizer-1/Math.sqrt(actual*actual+forward*forward))<1e-6,'separate movement normalizer');
    angular.push({lateral,longitudinal,source_lateral_weight:actual,source_longitudinal_weight:forward,
      source_magnitude:m.float(0),source_movement_normalizer:normalizer,host_asin_reference:expected,old_l1_weight:Math.abs(x)+Math.abs(y)>0?Math.abs(x)/(Math.abs(x)+Math.abs(y)):0,steps:result.steps});
  }
  const overlaps = [];
  for (const count of [1,2,3,4]) for (const factor of [1,.25]) for (const value of [-.1,0,.25,.5,.75,1,1.1]) {
    const {m,b} = machine(), at = a=>a-B;
    b.writeUInt32LE(4,at(LIST)); b.writeUInt32LE(NODES,at(LIST)+16);
    b.writeUInt32LE(B+0x500,at(POOL)); b.writeUInt32LE(4,at(POOL)+20);
    b.writeUInt32LE(LIST,at(SP)+252);
    for(let i=0;i<4;i++) { b.writeUInt32LE(ITEMS+i*64,at(SP)+256+i*4); b.writeFloatLE(-99,at(ITEMS)+i*64+8); }
    m.set64(29,BigInt(SP)); m.set64(19,BigInt(count)); m.set64(23,BigInt(POOL));
    m.setFloat(20,value); m.setFloat(23,0); m.setFloat(24,1); m.setFloat(26,factor);
    const steps = slice(m,0x58c180,0x58c250);
    const weights=[];let link=b.readUInt32LE(at(LIST)+4);
    while(link){const item=b.readUInt32LE(at(link)+4);weights.push({index:(item-ITEMS)/64,weight:b.readFloatLE(at(item)+8)});link=b.readUInt32LE(at(link)+8);assert(weights.length<=4);}
    const expected=count===2 ? (value<=0?[{index:0,weight:factor}]:value>=1?[{index:1,weight:factor}]:[{index:0,weight:Math.fround(Math.fround(1-Math.fround(value))*factor)},{index:1,weight:Math.fround(Math.fround(value)*factor)}]) : [{index:0,weight:factor}];
    assert.deepEqual(weights,expected,'original two-band overlap/other-count rule');
    overlaps.push({active_band_count:count,overlap_coordinate:value,directional_factor:factor,weights,steps});
  }
  return {schema_version:1,status:'PASS',source_hashes:HASHES,unknown_stubs:0,angular,overlaps,
    original_ranges:{direction:disasm(seal,0x583350,0x5834f4),direction_caller:disasm(seal,0x583078,0x5831f0),movement_normalizer_consumer:disasm(seal,0x57ab40,0x57ab94),vector_scale:disasm(core,0x309180,0x3091a8),selected_bands:disasm(seal,0x58bee8,0x58c058),outside_bands:disasm(seal,0x58c058,0x58c158),weighting:disasm(seal,0x58c158,0x58c258)},
    limitations:['Finite-normal IEEE float32 execution, not bit-exact PS2 hardware.','Band fixtures enter after original band selection and inject overlap endpoints/count. Full actor and allocation/controller are not executed.','Original outside-all-bands paths are statically decoded, not executed in the fixtures.','Source recipe population/order and actual-to-source speed input mapping remain unproven; no all-direction tier integration is justified by this report.','Source raw .03 axis gate is not interchangeable with an already-normalized modern presentation direction.','No Godot runtime changes or rendered parity claim.']};
}
if(require.main===module){const r=audit(),arg=process.argv.find(x=>x.startsWith('--output='));if(arg){const p=path.resolve(arg.slice(9));const evidenceRoot=path.resolve(__dirname,'../art_source/source_gait_weight_audit_20260913');assert(p.startsWith('/private/tmp/')||path.dirname(p)===evidenceRoot);fs.writeFileSync(p,JSON.stringify(r,null,2)+'\n',{flag:'wx'});}console.log(`SOURCE_GAIT_WEIGHT PASS angular=${r.angular.length} overlap=${r.overlaps.length} unknown_stubs=0`);}
module.exports={audit};
