'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict');
function grassPoints(file){const b=fs.readFileSync(file),len=b.readUInt32LE(12),j=JSON.parse(b.toString('utf8',20,20+len)),bin=b.subarray(28+len),points=[];
 const read=id=>{const a=j.accessors[id],v=j.bufferViews[a.bufferView],n=a.type==='VEC3'?3:1;assert(!v.byteStride);return Array.from({length:a.count},(_,i)=>Array.from({length:n},(_,k)=>a.componentType===5126?bin.readFloatLE((v.byteOffset||0)+(a.byteOffset||0)+(i*n+k)*4):bin.readUInt32LE((v.byteOffset||0)+(a.byteOffset||0)+(i*n+k)*4)));};
 const triangles=[];for(const m of j.meshes)for(const p of m.primitives){if(j.materials[p.material].name!=='ground_grassy.tif')continue;const v=read(p.attributes.POSITION),idx=read(p.indices).flat();for(let i=0;i<idx.length;i+=3)triangles.push(idx.slice(i,i+3).map(n=>v[n]));}
 for(let x=12;x<170;x+=3.5)for(let z=0;z<160;z+=3.5){for(const [a,b,c] of triangles){const den=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2]);if(Math.abs(den)<.01)continue;const u=((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/den,v=((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/den,w=1-u-v;if(Math.min(u,v,w)<.12)continue;const y=u*a[1]+v*b[1]+w*c[1];if([[80,78],[90,78],[100,78]].some(p=>Math.hypot(x-p[0],z-p[1])<12))continue;points.push([x,+y.toFixed(3),z]);break;}}
 return points;}
module.exports={grassPoints};if(require.main===module)console.log(JSON.stringify(grassPoints(process.argv[2])));
