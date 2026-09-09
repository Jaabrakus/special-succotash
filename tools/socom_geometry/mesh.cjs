'use strict';
const assert=require('node:assert/strict');
const MAGIC=Buffer.from('010100010080046c','hex');
function packets(data,metersPerUnit) {
  const starts=[]; for(let at=-1;(at=data.indexOf(MAGIC,at+1))>=0;)starts.push(at);
  return starts.map((start,i)=>decode(data,start,starts[i+1]??data.length,metersPerUnit));
}
function decode(b,start,end,metersPerUnit) {
  function u32(p){assert(p+4<=end,'packet truncated');return b.readUInt32LE(p);}
  const vertices=u32(start+48),faces=u32(start+52);
  assert(vertices>0 && vertices<=128 && faces>0 && faces<=256,'unsupported packet counts');
  assert.equal(u32(start+72),0x01000203,'unsupported vertex VIF cycle');
  const unpack=u32(start+76);
  assert.equal(unpack>>>24,0x6d,'expected V4-16 vertex unpack');
  assert.equal((unpack>>>16)&255,vertices*2%256,'vertex unpack length');
  const positions=[],normals=[],uv=[];
  let p=start+80;
  assert(p+vertices*16<=end,'vertex payload truncated');
  for(let v=0;v<vertices;v++,p+=16){
    positions.push([0,2,4].map(k=>b.readInt16LE(p+k)/16*metersPerUnit));
    const n=[6,12,14].map(k=>b.readInt16LE(p+k)/32767),len=Math.hypot(...n);
    assert(len<1.2,'unsupported packed normal');
    normals.push(len>0.01?n.map(x=>x/len):[0,1,0]);
    uv.push([b.readInt16LE(p+8)/4096,b.readInt16LE(p+10)/4096]);
  }
  assert.equal(u32(p),0x01000102,'unsupported triangle VIF cycle');
  const tri=u32(p+4); assert.equal(tri>>>24,0x6e,'expected V4-8 triangles');
  assert.equal((tri>>>16)&255,faces%256,'triangle unpack length');p+=8;
  assert(p+faces*4<=end,'triangle payload truncated');
  const indices=[];let positive=0,negative=0;
  for(let f=0;f<faces;f++,p+=4){
    const idx=[b[p],b[p+1],b[p+2]];
    assert(idx.every(x=>x%3===0 && x/3<vertices),'triangle references outside vertex data');
    assert([1,3].includes(b[p+3]),'unsupported triangle flags '+b[p+3]);
    const t=idx.map(x=>x/3);indices.push(...t);
    const [a,c,d]=t.map(x=>positions[x]);const u=c.map((x,k)=>x-a[k]),v=d.map((x,k)=>x-a[k]);
    const cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
    const dot=cross.reduce((s,x,k)=>s+x*normals[t[0]][k],0);
    if(dot>1e-8)positive++;else if(dot< -1e-8)negative++;
  }
  // PS2 source triangles are clockwise relative to outward normals.
  if(negative>positive)for(let i=0;i<indices.length;i+=3)[indices[i+1],indices[i+2]]=[indices[i+2],indices[i+1]];
  const tail=b.subarray(p,end).toString('latin1');
  const names=[...tail.matchAll(/[A-Za-z0-9_ .-]+\.tif\x00/g)].map(m=>m[0].slice(0,-1));
  return {start,end,vertices,faces,positions,normals,uv,indices,texture_names:[...new Set(names)],winding:{positive,negative}};
}
module.exports={packets,decode};

function bindings(data,refs) {
  const found=new Map();
  for(const offset of refs){
    assert(offset+16<=data.length,'draw table offset out of bounds');
    const count=data.readUInt32LE(offset);assert(count<10000&&offset+16+count*16<=data.length,'draw table length');
    let texture=null;
    for(let i=0;i<count;i++){
      const p=offset+16+i*16,kind=data.readUInt32LE(p)>>>16&255,ptr=data.readUInt32LE(p+4);
      if(kind===6){
        const end=data.indexOf(0,ptr);assert(ptr<data.length&&end>=ptr&&end-ptr<256,'texture name pointer');
        texture=data.toString('ascii',ptr,end);assert(/^[\w. -]+\.(tif|bmp)$/i.test(texture),'unsupported texture name');
      }else if(kind===2){
        assert(texture,'geometry without texture binding');
        assert(ptr+8<=data.length&&data.subarray(ptr,ptr+8).equals(MAGIC),'geometry reference not packet');
        if(found.has(ptr))assert.equal(found.get(ptr),texture,'inconsistent material instances');
        found.set(ptr,texture);
      }
    }
  }
  return found;
}
module.exports.bindings=bindings;
