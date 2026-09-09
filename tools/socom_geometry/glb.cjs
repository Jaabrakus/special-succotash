'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict');
function glb(name,packets,texturePaths,extras={},alphaTextures=new Set()){
  // Batch source packets by material to stay below Godot's per-mesh surface limit.
  const groups=new Map();
  for(const packet of packets){if(!groups.has(packet.texture))groups.set(packet.texture,{texture:packet.texture,positions:[],normals:[],uv:[],indices:[]});const g=groups.get(packet.texture),offset=g.positions.length;g.positions.push(...packet.positions);g.normals.push(...packet.normals);g.uv.push(...packet.uv);g.indices.push(...packet.indices.map(i=>i+offset));}
  packets=[...groups.values()];
  const doc={asset:{version:'2.0',generator:'SOCOM local static mesh research converter'},scene:0,scenes:[{nodes:[0]}],nodes:[{name,mesh:0}],meshes:[{name,primitives:[]}],materials:[],textures:[],images:[],samplers:[{magFilter:9728,minFilter:9987,wrapS:10497,wrapT:10497}],bufferViews:[],accessors:[],buffers:[],extras};
  const chunks=[];let bytes=0;
  function view(data,target){const p=Buffer.alloc((4-data.length%4)%4);let id=doc.bufferViews.length;doc.bufferViews.push({buffer:0,byteOffset:bytes,byteLength:data.length,...(target?{target}:{})});chunks.push(data,p);bytes+=data.length+p.length;return id;}
  function accessor(values,components,type=5126,bounds=false){let b=Buffer.alloc(values.length*4);values.forEach((v,i)=>{assert(Number.isFinite(v),'nonfinite mesh data');type===5126?b.writeFloatLE(v,i*4):b.writeUInt32LE(v,i*4);});const a={bufferView:view(b,type===5126?34962:34963),componentType:type,count:values.length/components,type:components===1?'SCALAR':'VEC'+components};if(bounds){a.min=Array(components).fill(Infinity);a.max=Array(components).fill(-Infinity);values.forEach((v,i)=>{let k=i%components;a.min[k]=Math.min(a.min[k],v);a.max[k]=Math.max(a.max[k],v);});}doc.accessors.push(a);return doc.accessors.length-1;}
  const materials=new Map();
  for(const packet of packets){const texture=packet.texture;assert(texturePaths.has(texture),'missing decoded texture '+texture);if(!materials.has(texture)){const img=doc.images.length;doc.images.push({name:texture,bufferView:view(fs.readFileSync(texturePaths.get(texture))),mimeType:'image/png'});doc.textures.push({source:img,sampler:0});materials.set(texture,doc.materials.length);doc.materials.push({name:texture,doubleSided:true,pbrMetallicRoughness:{baseColorTexture:{index:img},metallicFactor:0,roughnessFactor:1}});}
    if(alphaTextures.has(texture))Object.assign(doc.materials[materials.get(texture)],{alphaMode:'MASK',alphaCutoff:0.5});
    doc.meshes[0].primitives.push({attributes:{POSITION:accessor(packet.positions.flat(),3,5126,true),NORMAL:accessor(packet.normals.flat(),3),TEXCOORD_0:accessor(packet.uv.flat(),2)},indices:accessor(packet.indices,1,5125),material:materials.get(texture),mode:4});}
  assert(packets.length>0,'empty mesh');doc.buffers=[{byteLength:bytes}];let j=Buffer.from(JSON.stringify(doc));j=Buffer.concat([j,Buffer.alloc((4-j.length%4)%4,32)]);const bin=Buffer.concat(chunks),h=Buffer.alloc(12),jh=Buffer.alloc(8),bh=Buffer.alloc(8);h.writeUInt32LE(0x46546c67);h.writeUInt32LE(2,4);h.writeUInt32LE(28+j.length+bin.length,8);jh.writeUInt32LE(j.length);jh.writeUInt32LE(0x4e4f534a,4);bh.writeUInt32LE(bin.length);bh.writeUInt32LE(0x004e4942,4);return Buffer.concat([h,jh,j,bh,bin]);
}
module.exports={glb};
