'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{decode}=require('./textures.cjs');
// Synthetic source-format fixture tests alpha independently of copyrighted data.
const b=Buffer.alloc(176),pal=Buffer.alloc(1024);b.writeUInt16LE(4);b.writeUInt16LE(4,2);b.writeUInt32LE(16,4);b[12]=8;b[15]=3;for(let i=0;i<16;i++)b[32+i]=i%3;
for(let i=0;i<3;i++){pal[i*4]=50;pal[i*4+1]=100;pal[i*4+2]=150;pal[i*4+3]=i*64;}
b.writeBigUInt64LE(19n<<20n,48);b.writeBigUInt64LE(6n,56);const palettes=new Map([[0,{format:0,buf:pal}]]);
const d=decode(b,palettes);assert.deepEqual([d.rgba[3],d.rgba[7],d.rgba[11]],[0,128,255]);b[15]=2;assert.equal(decode(b,palettes).transparent,0);assert.throws(()=>decode(b.subarray(0,40),palettes));
const dir=process.argv[2],r=JSON.parse(fs.readFileSync(path.join(dir,'conversion.json')));assert.equal(r.converted.length,29);assert.equal(r.deferred.length,0);let masks=0;
for(const a of r.converted){const b=fs.readFileSync(path.join(dir,a.file)),len=b.readUInt32LE(12),j=JSON.parse(b.toString('utf8',20,20+len)),bin=b.subarray(28+len);for(const m of j.materials)if(m.alphaMode==='MASK'){assert.equal(m.alphaCutoff,.5);masks++;}for(const m of j.meshes)for(const p of m.primitives){const a=j.accessors[p.indices],v=j.bufferViews[a.bufferView],count=j.accessors[p.attributes.POSITION].count;for(let i=0;i<a.count;i++)assert(bin.readUInt32LE(v.byteOffset+i*4)<count);}}
assert(masks>=29);console.log('JUNGLE_BINARY PASS: source alpha fixture, opaque compatibility, malformed input, 29 source-bound meshes and '+masks+' cutout materials');
