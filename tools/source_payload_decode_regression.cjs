'use strict';
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {decode}=require('./source_loader_analysis.cjs');
const {untransform}=require('./source_overlay_untransform.cjs');
const {context,rc6Schedule,rc6DecryptBlock,rc6Cbc,sourceSha1}=require('./source_payload_decode.cjs');

// Primitive controls: zero-key RC6 block, standard SHA1 tails, and fail-closed
// bounds. Actual ISO tests below verify cryptographic structure, signatures,
// source checksums, cleartext markers, byte counts and exact stable hashes.
assert.equal(rc6DecryptBlock(Buffer.from('8fc3a53656b1f778c129df4e9848a41e','hex'),rc6Schedule(Buffer.alloc(16))).toString('hex'),'00000000000000000000000000000000');
for(const length of[0,1,3,16,47,56,63,64,80,128,256]) {
  const bytes=Buffer.alloc(length,0x61);
  assert(sourceSha1(bytes).equals(crypto.createHash('sha1').update(bytes).digest()));
}
assert(!sourceSha1(Buffer.alloc(48)).equals(crypto.createHash('sha1').update(Buffer.alloc(48)).digest()),'preserve source 48-byte tail quirk');
assert.throws(()=>rc6Cbc(Buffer.alloc(17),Buffer.alloc(16),Buffer.alloc(16)));
assert.throws(()=>rc6Cbc(Buffer.alloc(16),Buffer.alloc(12),Buffer.alloc(16)));
assert.equal(decode(0x00721807,0),'srav v1,s2,v1','variable shifts use rt as value, rs as shift');
console.log('PASS primitive, bounds and static-disassembler controls');

if(process.argv[2]) {
  const c=context(process.argv[2]);
  assert.throws(()=>c.key(69));assert.throws(()=>c.key(100));
  const expected={
    ftscore:{size:852832,prefix:1408,hash:'f707f2f76df3103d9699cd6485e8225eef08da76a64509bcdc2f08cdc9dfc4e1'},
    zsealetc:{size:687232,prefix:2880,hash:'8e6a5766d1f272b26fec35e5187dcbd707b89e5aec445cbd89566a917df58b7c'},
  };
  for(const p of c.payloads()) {
    const original=Buffer.from(p.bytes),r=c.outerClear(p.bytes),e=expected[p.name];assert(e);
    assert.equal(r.size,e.size);assert.equal(r.prefix,e.prefix);
    assert.equal(crypto.createHash('sha256').update(r.body).digest('hex'),e.hash);
    assert(r.verifiedSourceChecksum);assert(original.equals(p.bytes),'no source mutation');
    const corrupt=Buffer.from(p.bytes);corrupt[1408+123]^=1;
    assert.throws(()=>c.outerClear(corrupt),/checksum/,'tampered body rejected');
    assert.throws(()=>c.outerClear(p.bytes.subarray(0,1408)),/Assertion/,'truncated input rejected');
    const again=c.outerClear(p.bytes);assert(r.body.equals(again.body),'deterministic repeat');
    console.log(`PASS ${p.name}: authenticated outer transform, checksum, suffix, bounds, no mutation and repeatability`);
  }
  const result=untransform(process.argv[2]);
  assert.equal(result.blocks.filter(b=>b.id!=='0x0').length,30);
  assert.equal(result.img.bytes.readUInt32LE(result.img.offset(0x536f98)),0x24050053);
  assert.equal(result.img.bytes.readUInt32LE(result.img.offset(0x536fc0)),0x3c050056,'relocation-bearing instruction preserved');
  assert.equal(result.img.bytes.readUInt32LE(result.img.offset(0x5374cc)),0x3c020002,'id=0 forward block transformed');
  console.log('PASS statically unpacked code controls: 30 table-backed blocks plus bounded id=0 stubs');
}
