'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {archive}=require('./archive.cjs'),{packets}=require('./mesh.cjs');
assert.throws(()=>archive(Buffer.alloc(99)));
assert.throws(()=>packets(Buffer.from('010100010080046c','hex'),.1));
let files=0,triangles=0;
for(const dir of process.argv.slice(2))for(const name of fs.readdirSync(dir).filter(n=>n.endsWith('.glb')&&n!=='overview.glb')){
 const b=fs.readFileSync(path.join(dir,name));assert.equal(b.readUInt32LE(0),0x46546c67);assert.equal(b.readUInt32LE(4),2);assert.equal(b.readUInt32LE(8),b.length);
 const len=b.readUInt32LE(12),doc=JSON.parse(b.toString('utf8',20,20+len)),bin=b.subarray(28+len);
 for(const mesh of doc.meshes){assert(mesh.primitives.length<256);for(const p of mesh.primitives){const a=doc.accessors[p.indices],v=doc.bufferViews[a.bufferView],count=doc.accessors[p.attributes.POSITION].count;assert.equal(a.count%3,0);for(let i=0;i<a.count;i++)assert(bin.readUInt32LE(v.byteOffset+i*4)<count);triangles+=a.count/3;}}
 for(const a of doc.accessors){const v=doc.bufferViews[a.bufferView];assert(v.byteOffset+v.byteLength<=bin.length);if(a.componentType===5126)for(let i=0;i<v.byteLength;i+=4)assert(Number.isFinite(bin.readFloatLE(v.byteOffset+i)));}
 files++;
}
assert.equal(files,98);assert.equal(triangles,18060);
console.log('SOCOM_GEOMETRY_BINARY PASS: malformed input rejected, 98 GLBs, 18060 triangles, bounded finite buffers and indices');
