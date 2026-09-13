'use strict';
// Read-only original material/continuation audit. Never opens a game or writes files.
const assert = require('node:assert/strict');
const {images, sourceData, originalPenetration, penetrationReference} = require('./source_damage_equation_audit.cjs');
const {FloatFixtureMachine} = require('./source_mips_float_fixture.cjs');
const READER_HASH = 'a8eedb496a3bfa308d53e7157e665b48e97ce2c96354f03ed4fc1194dabc80ef';
const ARCHIVE_HASH = '1b7df1c9732d4d9be0c9ce49de342cd9b552f0d41269dc486be0075e62db9123';
const hex = x => '0x' + (x >>> 0).toString(16);

function span(m, im, start, end) {
  m.map(start, im.bytes.subarray(im.offset(start), im.offset(end)), {execute:true, name:'pinned original instructions'});
}
function uint32(x) { assert(Number.isInteger(x) && x >= 0 && x <= 0xffffffff, 'uint32 fixture'); return x; }
function machine() { return new FloatFixtureMachine({maxSteps:100, maxMappedBytes:8192}); }
function originalMaterialId(im, word, defaultId, nullMetadata = false) {
  uint32(word); uint32(defaultId);
  const m = machine(); span(m, im, 0x2dc1d0, 0x2dc208);
  const record = Buffer.alloc(256);
  record.writeUInt32LE(nullMetadata ? 0 : 0x110080, 12);
  record.writeUInt32LE(word, 136);
  m.map(0x110000, record, {name:'synthetic hit and metadata'});
  const global = Buffer.alloc(4); global.writeUInt32LE(defaultId);
  m.map(0x44f310, global, {name:'synthetic default soil ID'});
  const result = m.run(0x2dc1d0, {args:[0x110000]});
  assert.equal(result.writes, 0);
  return Number(result.value);
}
function originalTablePointer(im, id, count) {
  uint32(id); assert(Number.isInteger(count) && count > 0 && count < 256);
  const m = machine(); span(m, im, 0x3c8988, 0x3c89bc);
  const global = Buffer.alloc(12); global.writeUInt32LE(count, 4); global.writeUInt32LE(0x110000, 8);
  m.map(0x44f350, global, {name:'synthetic original material table globals'});
  const table = Buffer.alloc(count * 4);
  for (let index=0; index<count; index++) table.writeUInt32LE(0x120000 + index*64, index*4);
  m.map(0x110000, table, {name:'synthetic material pointers'});
  m.set64(2, BigInt(id));
  const result = m.run(0x3c8988, {returnAddress:0x3c89bc});
  assert.equal(result.writes, 0);
  return Number(m.u(16));
}
function verifyPins(im) {
  for (const [pc, tag] of [[0x3f36b0,'SOILS'], [0x3f3728,'PENETRATION'], [0x3f3800,'UNKNOWN'], [0x3f3810,'PARTICLE_SYSTEM']]) {
    const p = im.offset(pc); assert.equal(im.bytes.toString('ascii', p, im.bytes.indexOf(0,p)), tag);
  }
  for (const [pc, word] of [[0x2de11c,0xe6000024], [0x2de52c,0xae000024],
    [0x2de640,0xae020024], [0x3c8cdc,0xc6160024], [0x3c9d98,0xc4410024],
    [0x3c9dac,0x46010032], [0x3c9db0,0x4501005f], [0x3c9e94,0x4600ab46],
    [0x3c8ed8,0x46160002], [0x3c8ee8,0xe6a00094]]) {
    assert.equal(im.bytes.readUInt32LE(im.offset(pc)), word, 'source opcode '+hex(pc));
  }
}
function audit(iso) {
  assert(typeof iso === 'string' && iso.length > 0, 'explicit original ISO path required');
  const im = images().FTSCore; verifyPins(im);
  const source = sourceData(iso);
  assert.equal(source.archive_sha256, ARCHIVE_HASH);
  assert.equal(source.material_reader.sha256, READER_HASH);
  const rows = source.material_rows;
  assert.equal(rows.length,44); assert.equal(new Set(rows.map(x=>x.name)).size,44);
  for (const row of rows) assert(Number.isFinite(row.PENETRATION) && row.PENETRATION >= 0 && row.PENETRATION <= 1);
  let getterCases=0, tableCases=0, equationCases=0;
  for (const word of [0,1,1023,1024,2048,0x3fc00,0xffffffff,...Array.from({length:256},(_,n)=>n*1024)]) {
    for (const defaultId of [0,19]) {
      assert.equal(originalMaterialId(im,word,defaultId), ((word>>>10)&255)||defaultId);
      getterCases++;
    }
  }
  assert.equal(originalMaterialId(im,0xffffffff,19,true),0); getterCases++;
  for (const id of [...Array.from({length:256},(_,i)=>i),0xffffffff]) {
    assert.equal(originalTablePointer(im,id,46),0x120000+(id<46?id:0)*64);
    tableCases++;
  }
  for (const row of rows) for (const piercing of [0,1,3,10]) for (const distanceSquared of [100,10000,250000]) {
    const v={range:1000,piercing,penetration:row.PENETRATION,distanceSquared};
    assert.deepEqual(originalPenetration(im,v),penetrationReference(v)); equationCases++;
  }
  const boundaries=[];
  for (const distanceSquared of [105624,105625,105626]) {
    const v={range:1000,piercing:3,penetration:.25,distanceSquared};
    const result=originalPenetration(im,v); assert.deepEqual(result,penetrationReference(v));
    assert.equal(result.range,325); assert.equal(result.resultCode,distanceSquared<=105625?2:4);
    boundaries.push({input:v,output:result}); equationCases++;
  }
  const first=originalPenetration(im,{range:1000,piercing:3,penetration:.25,distanceSquared:100});
  const second=originalPenetration(im,{range:first.range,piercing:3,penetration:.25,distanceSquared:400});
  assert.equal(second.range,105.625); assert.equal(second.resultCode,2); equationCases+=2;
  assert.throws(()=>originalMaterialId(im,-1,0),/uint32/);
  assert.throws(()=>originalMaterialId(im,0,NaN),/uint32/);
  assert.throws(()=>originalTablePointer(im,0,0));
  return {status:'PASS',getter_cases:getterCases,table_cases:tableCases,equation_cases:equationCases,
    malformed_cases:3,material_rows:rows,
    source:{archive:source.archive,archive_sha256:source.archive_sha256,reader:source.material_reader},
    collision_id:'metadata = hit[12]; metadata ? ((metadata.word8 >> 10) & 255) || globalDefaultId : 0',
    table_fallback:'ID outside table -> index 0; UNKNOWN P=0; authored rows follow two built-ins',
    boundaries,limitations:['Read-only offline finite float32 instruction fixtures; not complete R5900 FPU.',
      'Does not execute collision detection or world material instantiation.',
      'Global default material and imported triangle mapping require explicit source provenance.',
      'No live runtime/profile changes or proof of source-matched Godot collision traversal.']};
}
if (require.main === module) {
  const result=audit(process.argv[2]);
  if(process.argv.includes('--json')) console.log(JSON.stringify(result,null,2));
  else console.log('SOURCE_MATERIAL_PENETRATION_AUDIT PASS getter='+result.getter_cases+
    ' table='+result.table_cases+' equation='+result.equation_cases+' malformed='+result.malformed_cases+' materials='+result.material_rows.length);
}
module.exports={audit,originalMaterialId,originalTablePointer};
