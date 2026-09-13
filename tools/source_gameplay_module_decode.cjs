'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const zlib=require('node:zlib');
const {context,rc6Cbc,rc6Schedule,rol}=require('./source_payload_decode.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function rc6EncryptBlock(block,S){
  let [A,B,C,D]=Array.from({length:4},(_,i)=>block.readUInt32LE(i*4));
  B=(B+S[0])>>>0;D=(D+S[1])>>>0;
  for(let i=1;i<=20;i++){
    const t=rol(Math.imul(B,(B*2+1)>>>0),5),u=rol(Math.imul(D,(D*2+1)>>>0),5);
    A=(rol((A^t)>>>0,u)+S[2*i])>>>0;C=(rol((C^u)>>>0,t)+S[2*i+1])>>>0;
    [A,B,C,D]=[B,C,D,A];
  }
  A=(A+S[42])>>>0;C=(C+S[43])>>>0;
  const out=Buffer.alloc(16);[A,B,C,D].forEach((v,i)=>out.writeUInt32LE(v,i*4));return out;
}
function rc6EncryptCbc(bytes,key,iv){
  assert(bytes.length%16===0&&bytes.length<=8*1024*1024&&iv.length===16);
  const out=Buffer.alloc(bytes.length),S=rc6Schedule(key);let previous=iv;
  for(let at=0;at<bytes.length;at+=16){const b=Buffer.alloc(16);for(let i=0;i<16;i++)b[i]=bytes[at+i]^previous[i];previous=rc6EncryptBlock(b,S);previous.copy(out,at);}return out;
}
function decodeModule(c,payload){
  assert(payload.bytes.length>=1536&&payload.bytes.length<=8*1024*1024,'payload bound');
  const outer=c.outerClear(payload.bytes),h=outer.header;
  const record=(offset,id,marker,at)=>{const b=c.rsa(payload.bytes.subarray(offset,offset+128),id);assert(b.subarray(at,at+16).equals(Buffer.from(marker)),`RSA marker at ${offset}`);return b;};
  const key=record(384,h[1],'64527f0d82e813f6',32).subarray(0,32);
  const left=record(896,h[7],'595cc40b6f133f06',64).subarray(0,64);
  const right=record(1152,h[8],'d47ef2f749057f66',64).subarray(0,64);
  const derived=rc6EncryptCbc(Buffer.concat([left,right]),key.subarray(0,16),key.subarray(16,32));
  const clear=rc6Cbc(outer.body,key.subarray(0,16),derived.subarray(112,128));
  const start=outer.meta[9]*16,length=outer.meta.readUInt32LE(4);
  assert(length>0&&length<=8*1024*1024&&start+length+16<=clear.length,'inner output bounds');
  assert(clear.subarray(start+length,start+length+16).equals(Buffer.from('e3e4f8efccd56d07')),'inner end marker');
  const compressed=clear.subarray(start,start+length);
  const expanded=zlib.inflateSync(compressed,{maxOutputLength:8*1024*1024,info:true});
  assert(expanded.engine.bytesWritten===compressed.length,'trailing compressed bytes');
  const bytes=expanded.buffer;
  assert(bytes.length>=64&&bytes.toString('ascii',0,4)==='MWo3','MWo3 magic');
  const declaredEnd=64+bytes.readUInt32LE(12)+bytes.readUInt32LE(16);
  assert(declaredEnd<=bytes.length&&bytes.length-declaredEnd<=4096,'MWo3 declared spans/trailing-data bound');
  const end=bytes.indexOf(0,32);assert(end>32&&end<64,'MWo3 name bounds');
  const name=bytes.toString('ascii',32,end),base=bytes.readUInt32LE(8);
  assert((payload.name==='ftscore'&&name==='FTSCore.bin'&&base===0x1e7000)||(payload.name==='zsealetc'&&name==='ZSealEtc.bin'&&base===0x4c5380),'module identity/base');
  const metadata={name,archiveEntry:payload.name,sourceSha256:sha(payload.bytes),compressedBytes:length,compressedSha256:sha(compressed),decodedBytes:bytes.length,decodedSha256:sha(bytes),base:'0x'+base.toString(16),textBytes:bytes.readUInt32LE(12),dataBytes:bytes.readUInt32LE(16),bssBytes:bytes.readUInt32LE(20),trailingBytesBeyondUnalignedSpans:bytes.length-declaredEnd,layoutNote:'Header spans are bounded; exact trailing metadata/alignment and runtime load mapping require loader verification.',outerSourceChecksumVerified:outer.verifiedSourceChecksum,innerMarkersVerified:true,zlibChecksumVerified:true};
  return {bytes,metadata};
}
function selfTest(iso){
  const k=Buffer.alloc(16),p=Buffer.alloc(16);
  // RC6-32/20/16 published zero-key/zero-plaintext known-answer vector.
  const encrypted=rc6EncryptBlock(p,rc6Schedule(k));assert.equal(encrypted.toString('hex'),'8fc3a53656b1f778c129df4e9848a41e');
  for(const len of [16,24,32])for(const count of [1,8]){const key=Buffer.from(Array.from({length:len},(_,i)=>i*7&255)),iv=Buffer.alloc(16,23),plain=Buffer.from(Array.from({length:16*count},(_,i)=>i*13&255));assert.deepEqual(rc6Cbc(rc6EncryptCbc(plain,key,iv),key,iv),plain);}
  assert.throws(()=>rc6EncryptCbc(Buffer.alloc(15),k,p));
  console.log('PASS inner cipher known-answer, CBC multi-block/key-size roundtrips and bounds');
  if(iso){
    const c=context(iso),expected={ftscore:'cf09a7fabaf59a1d68f01411bd1db9e859af054df1f2fbc4775d8c221785f836',zsealetc:'cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1'};
    for(const p of c.payloads()){
      const before=sha(p.bytes),r=decodeModule(c,p);assert.equal(r.metadata.decodedSha256,expected[p.name]);assert.equal(sha(p.bytes),before,'source unchanged');
      assert(decodeModule(c,p).bytes.equals(r.bytes),'repeatability');
      const bad={...p,bytes:Buffer.from(p.bytes)};bad.bytes[384]^=1;assert.throws(()=>decodeModule(c,bad),'invalid inner key rejected');
      const altered={...c,outerClear:b=>{const x=c.outerClear(b);x.meta=Buffer.from(x.meta);x.meta.writeUInt32LE(0xffffffff,4);return x;}};assert.throws(()=>decodeModule(altered,p),/inner output bounds/);
      console.log(`PASS ${p.name}: exact module hash, no mutation, repeatability, inner corruption and bounds rejection`);
    }
  }
}
if(require.main===module){
  if(process.argv[2]==='--self-test')selfTest(process.argv[3]);
  else{
    const [iso,dir]=process.argv.slice(2);assert(iso&&dir,'usage: local.iso NEW_OUTPUT_DIRECTORY');assert(!fs.existsSync(dir),'fresh output directory required');
    const c=context(iso),results=c.payloads().map(p=>decodeModule(c,p));
    fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'.gdignore'),'# Original executable research; never export.\n',{flag:'wx'});
    fs.writeFileSync(path.join(dir,'.gitignore'),'# Keep original executable bytes local. Reproduce them from the authorized ISO.\n*.bin\n',{flag:'wx'});
    for(const r of results)fs.writeFileSync(path.join(dir,r.metadata.name),r.bytes,{flag:'wx'});
    fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify({schemaVersion:1,status:'Decoded original modules; gameplay equations not yet promoted',modules:results.map(r=>r.metadata)},null,2)+'\n',{flag:'wx'});
    console.log(JSON.stringify(results.map(r=>r.metadata),null,2));
  }
}
module.exports={decodeModule,rc6EncryptBlock,rc6EncryptCbc,selfTest};
