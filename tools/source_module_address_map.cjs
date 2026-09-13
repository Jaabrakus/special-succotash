'use strict';
// Read-only mapping proof for the two already-decoded .75 modules. No execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {image} = require('./source_loader_analysis.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const hex = v => '0x' + v.toString(16);
const audited = {
  'FTSCore.bin': {base:0x1e7000, bytes:2233472, sha:'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836'},
  'ZSealEtc.bin': {base:0x4c5380, bytes:1723520, sha:'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'},
};
function mapping(bytes) {
  assert(Buffer.isBuffer(bytes) && bytes.length >= 64 && bytes.length <= 8*1024*1024, 'bounded module');
  assert.equal(bytes.toString('ascii',0,4),'MWo3','module magic');
  const base=bytes.readUInt32LE(8), end=base+bytes.length, bss=bytes.readUInt32LE(20);
  assert(base%4===0 && end+bss<=0x100000000,'virtual range');
  const offset=(address,size=4)=>{
    assert(Number.isSafeInteger(address) && Number.isSafeInteger(size) && size>0 && address>=base && address+size<=end,'unmapped source address');
    return address-base;
  };
  const initStart=bytes.readUInt32LE(24),initEnd=bytes.readUInt32LE(28);
  assert(initStart%4===0 && initEnd%4===0 && initEnd>=initStart && initEnd-initStart<=65536,'initializer table bounds');
  offset(initStart,Math.max(4,initEnd-initStart));
  const functions=[];
  for(let a=initStart;a<initEnd;a+=4){const target=bytes.readUInt32LE(offset(a));assert(target%4===0 && target>=base+64,'initializer target');offset(target);functions.push(target);}
  const declaredText=bytes.readUInt32LE(12),declaredData=bytes.readUInt32LE(16),unaligned=64+declaredText+declaredData;
  assert(unaligned<=bytes.length,'declared sizes exceed file');
  return {base,end,bss,offset,functions,report:{base:hex(base),fileBytes:bytes.length,fileEndExclusive:hex(end),bssBytes:bss,bssEndExclusive:hex(end+bss),
    declaredTextBytes:declaredText,declaredDataBytes:declaredData,declaredTextLimitNotCodeBoundary:hex(base+64+declaredText),
    extraBytesBeyondUnalignedSum:bytes.length-unaligned,extraNonzeroBytes:bytes.subarray(unaligned).filter(v=>v!==0).length,
    initializerTable:[hex(initStart),hex(initEnd)],initializerCount:functions.length,
    initializerFunctionRange:functions.length?[hex(Math.min(...functions)),hex(Math.max(...functions))]:null,
    mapping:'runtime VA = base + file offset; whole file retained; section partition not established'}};
}
function inspect(directory,isoPath) {
  const modules=[];
  for(const [name,want] of Object.entries(audited)){
    const b=fs.readFileSync(path.join(directory,name));
    assert.equal(b.length,want.bytes,name+' byte count');assert.equal(sha(b),want.sha,name+' source hash');
    const m=mapping(b);assert.equal(m.base,want.base);
    const word=a=>b.readUInt32LE(m.offset(a));
    if(name==='FTSCore.bin'){
      assert.equal(word(0x1e7048),0x0c07aaf4);assert.equal(word(0x1eabd0),0x27bdffd0);
      assert.equal(word(0x1e70a4),0x3c05003e);assert.equal(word(0x1e70ac),0x24a517c8);
      assert.equal(b.toString('ascii',m.offset(0x3e17c8,15),m.offset(0x3e17c8,15)+15),'VERSION_STRING\0');
      assert.equal(m.functions.length,125);
    }else{
      assert.equal(word(0x4c53c0),0x08079c10);assert.equal(word(0x4c5400),0x27bdffc0);
      assert.equal(word(0x64f798),0x4c5400);assert.equal(m.functions.length,16);
    }
    modules.push({name,sha256:sha(b),...m.report});
  }
  let boot=null;
  if(isoPath){
    const img=image(isoPath);
    const expected=new Map([
      [0x1d52a4,0x4c5380],[0x1d52a8,0x1e7000],
      [0x1c59e0,0x8c3152a4],[0x1c59e8,0x8c3052a8],
      [0x1c5aac,0x0200282d],[0x1c5ac8,0x0220282d],
      [0x1c5e60,0x0260202d],[0x1c5e64,0x0c0728a8],[0x1c5e74,0xdfa20060],
      [0x1c5e80,0x0260202d],[0x1c5e84,0x0c060760],
      [0x181da4,0x8c900014],[0x181db8,0x02539021],[0x181dc4,0x0c06566e],
      [0x181dd0,0x8e240018],[0x181dd4,0x8e25001c],[0x181ddc,0x0c060a10],
      [0x182860,0x8e020000],[0x182864,0x0040f809],[0x18286c,0x26100004],
      [0x1c598c,0x0c1314f0],
    ]);
    for(const [address,word] of expected)assert.equal(img.bytes.readUInt32LE(img.offset(address)),word,'audited boot instruction '+hex(address));
    boot={name:img.boot,sha256:sha(img.bytes),verifiedInstructionAndGlobalWords:expected.size};
  }
  return {schemaVersion:1,status:'Static whole-file mapping verified; section partition and initializer side effects not inferred',boot,modules};
}
function selfTest(){
  const b=Buffer.alloc(128);b.write('MWo3');b.writeUInt32LE(0x1000,8);b.writeUInt32LE(32,12);b.writeUInt32LE(32,16);b.writeUInt32LE(16,20);b.writeUInt32LE(0x1070,24);b.writeUInt32LE(0x1074,28);b.writeUInt32LE(0x1040,112);
  const m=mapping(b);assert.equal(m.offset(0x1040),64);assert.equal(m.end,0x1080);assert.equal(m.bss,16);assert.deepEqual(m.functions,[0x1040]);
  assert.throws(()=>m.offset(0x1080),/unmapped/);assert.throws(()=>m.offset(0x1040,-1),/unmapped/);
  let bad=Buffer.from(b);bad[0]=0;assert.throws(()=>mapping(bad),/magic/);
  bad=Buffer.from(b);bad.writeUInt32LE(0x2000,28);assert.throws(()=>mapping(bad),/unmapped/);
  bad=Buffer.from(b);bad.writeUInt32LE(0x2000,112);assert.throws(()=>mapping(bad),/unmapped/);
  bad=Buffer.from(b);bad.writeUInt32LE(256,12);assert.throws(()=>mapping(bad),/declared sizes/);
  console.log('SOURCE_MODULE_ADDRESS_MAP PASS synthetic mapping and malformed bounds fixtures');
}
if(require.main===module){if(process.argv[2]==='--self-test')selfTest();else{assert(process.argv[2],'usage: DECODED_DIRECTORY [ISO] | --self-test');console.log(JSON.stringify(inspect(process.argv[2],process.argv[3]),null,2));}}
module.exports={mapping,inspect,selfTest};
