'use strict';
// Offline data transforms only. No game/ISO instructions are executed.
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {image}=require('./source_loader_analysis.cjs');
const {openIso}=require('./extract_iso_camera_reference.cjs');
const {zdbEntries}=require('./source_runtime_module_inventory.cjs');
const rol=(v,n)=>((v<<(n&31))|(v>>>((32-n)&31)))>>>0;
const ror=(v,n)=>((v>>>(n&31))|(v<<((32-n)&31)))>>>0;
function rc6Schedule(key) {
  assert([16,24,32].includes(key.length));
  const L=Array.from({length:key.length/4},(_,i)=>key.readUInt32LE(i*4));
  const S=Array.from({length:44},(_,i)=>(0xb7e15163+Math.imul(i,0x9e3779b9))>>>0);
  let A=0,B=0,i=0,j=0;
  for(let k=0;k<3*Math.max(44,L.length);k++) {
    A=S[i]=rol((S[i]+A+B)>>>0,3);
    B=L[j]=rol((L[j]+A+B)>>>0,(A+B)>>>0);
    i=(i+1)%S.length;j=(j+1)%L.length;
  }
  return S;
}
function rc6DecryptBlock(block,S) {
  let [A,B,C,D]=Array.from({length:4},(_,i)=>block.readUInt32LE(i*4));
  C=(C-S[43])>>>0;A=(A-S[42])>>>0;
  for(let i=20;i>=1;i--) {
    [A,B,C,D]=[D,A,B,C];
    const u=rol(Math.imul(D,(D*2+1)>>>0),5),t=rol(Math.imul(B,(B*2+1)>>>0),5);
    C=(ror((C-S[2*i+1])>>>0,t)^u)>>>0;
    A=(ror((A-S[2*i])>>>0,u)^t)>>>0;
  }
  D=(D-S[1])>>>0;B=(B-S[0])>>>0;
  const out=Buffer.alloc(16);[A,B,C,D].forEach((v,i)=>out.writeUInt32LE(v,i*4));return out;
}
function rc6Cbc(cipher,key,iv) {
  assert(cipher.length%16===0&&iv.length===16&&cipher.length<=8*1024*1024);
  const out=Buffer.alloc(cipher.length),S=rc6Schedule(key);let prev=iv;
  for(let at=0;at<cipher.length;at+=16){const cur=cipher.subarray(at,at+16),b=rc6DecryptBlock(cur,S);for(let j=0;j<16;j++)out[at+j]=b[j]^prev[j];prev=cur;}
  return out;
}
function sourceSha1(data) {
  // 0x53f278 uses 48 (not SHA-1's usual 56) as the final tail threshold.
  // Preserve this source quirk; it is necessary for ftscore's 48-byte tail.
  assert(data.length<=8*1024*1024);
  const rem=data.length%64,extra=rem>=48?128-rem:64-rem;
  const padded=Buffer.alloc(data.length+extra);data.copy(padded);padded[data.length]=128;
  padded.writeUInt32BE((data.length*8)>>>0,padded.length-4);
  let h=[0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0];
  for(let at=0;at<padded.length;at+=64) {
    const w=Array(80);for(let i=0;i<16;i++)w[i]=padded.readUInt32BE(at+i*4);
    for(let i=16;i<80;i++)w[i]=rol(w[i-3]^w[i-8]^w[i-14]^w[i-16],1);
    let[a,b,c,d,e]=h;
    for(let i=0;i<80;i++) {
      const f=i<20?(b&c)|(~b&d):i<40?b^c^d:i<60?(b&c)|(b&d)|(c&d):b^c^d;
      const k=i<20?0x5a827999:i<40?0x6ed9eba1:i<60?0x8f1bbcdc:0xca62c1d6;
      const t=(rol(a,5)+f+e+k+w[i])>>>0;e=d;d=c;c=rol(b,30);b=a;a=t;
    }
    h=h.map((v,i)=>(v+[a,b,c,d,e][i])>>>0);
  }
  const out=Buffer.alloc(20);h.forEach((v,i)=>out.writeUInt32BE(v,i*4));return out;
}
function context(isoPath) {
  const img=image(isoPath,'OVERLAY/REL/DNAS.BIN'),cache=new Map();
  assert.equal(crypto.createHash('sha256').update(img.bytes).digest('hex'),
    'b205b68251723e554bc34a6afe5ef5cb37df2a688b0bcdd660c4f3f2845edafd',
    'decoder is scoped to the audited .75 overlay build');
  function key(id) {
    assert(Number.isInteger(id)&&id>=70&&id<100,'source key selector range');
    if(cache.has(id))return cache.get(id);
    const at=img.offset(0x560a20+(id-70)*200),r=img.bytes.subarray(at,at+200);
    // Exact DES-CBC key record transform at 0x53f768. Triplicate DES key
    // through supported 3DES primitive is mathematically single DES.
    const d=crypto.createDecipheriv('des-ede3-cbc',Buffer.concat([r.subarray(0,8),r.subarray(0,8),r.subarray(0,8)]),r.subarray(8,16));
    d.setAutoPadding(false);const clear=Buffer.concat([d.update(r.subarray(16)),d.final()]);
    const length=clear.readUInt32BE(4);assert(length>0&&length<=176);
    const result=crypto.createPublicKey({key:clear.subarray(8,8+length),type:'spki',format:'der'});cache.set(id,result);return result;
  }
  function rsa(block,id) { assert.equal(block.length,128);return crypto.publicDecrypt({key:key(id),padding:crypto.constants.RSA_PKCS1_PADDING},block); }
  function payloads(){const iso=openIso(isoPath);try{const z=iso.find('RUN/RAW/APACHE00.ZDB').bytes;return zdbEntries(z).map(e=>({...e,bytes:Buffer.from(z.subarray(e.offset,e.offset+e.size))}));}finally{iso.close();}}
  function firstHeader(bytes) {
    assert(bytes.length>=1536);
    const rsa0=rsa(bytes.subarray(768,896),83);
    assert(rsa0.subarray(32,48).equals(Buffer.from('791253d95296b82c')),'first fixed RSA marker');
    const header=rc6Cbc(bytes.subarray(1280,1408),rsa0.subarray(0,16),rsa0.subarray(16,32));
    assert(header.subarray(10,26).equals(Buffer.from('cd218709bfd73b9f')),'first RC6 header marker');
    const meta=rsa(bytes.subarray(640,768),header[4]);
    assert(meta.subarray(11,27).equals(Buffer.from('97c03eeb23cb1287')),'first metadata RSA marker');
    const type=rsa(bytes.subarray(0,128),header[5]);
    assert(type.subarray(4,20).equals(Buffer.from('1d9195a07aa9969f')),'first type RSA marker');
    return{header,meta,type,rsa0};
  }
  function outerClear(bytes) {
    const h=firstHeader(bytes),size=h.meta.readUInt32LE(0),prefix=h.meta[8]*16;
    const length=Math.ceil((size+prefix+16)/16)*16;
    assert(size>0&&size<=8*1024*1024&&1408+length+128<=bytes.length);
    const k=rsa(bytes.subarray(256,384),h.header[0]);
    assert(k.subarray(32,48).equals(Buffer.from('8284720a54628c26')),'outer body key marker');
    const cipher=bytes.subarray(1408,1408+length);
    const trailer=rsa(bytes.subarray(1408+length,1536+length),h.header[2]);
    assert(trailer.subarray(20,36).equals(Buffer.from('25d07bb35f4043df')),'outer signed hash marker');
    assert(sourceSha1(cipher).equals(trailer.subarray(0,20)),'source-padded SHA1 ciphertext checksum');
    const clear=rc6Cbc(cipher,k.subarray(0,16),k.subarray(16,32));
    assert(clear.subarray(prefix+size,prefix+size+16).equals(Buffer.from('e01c39bb7e705e7f')),'outer cleartext suffix');
    return{...h,body:Buffer.from(clear.subarray(prefix,prefix+size)),clear,cipher,size,prefix,length,verifiedSourceChecksum:true};
  }
  return{img,key,rsa,payloads,firstHeader,outerClear};
}
if(require.main===module){const c=context(process.argv[2]);for(const p of c.payloads()){const h=c.outerClear(p.bytes);console.log(p.name,JSON.stringify({keyIds:[h.header[4],h.header[5]],metadataSize:h.size,prefixBytes:h.prefix,type:h.type.readUInt32LE(0),verifiedSourceChecksum:h.verifiedSourceChecksum,bodyHash:crypto.createHash('sha256').update(h.body).digest('hex')}));}}
module.exports={context,rc6Schedule,rc6DecryptBlock,rc6Cbc,sourceSha1,rol,ror};
