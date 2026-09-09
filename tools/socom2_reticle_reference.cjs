'use strict';
// Bounded read-only ISO input. Output is a new local reference directory only.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {archive}=require('./socom_geometry/archive.cjs');
const {decode,png}=require('./socom_geometry/textures.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function zdb(b){
  assert(b.length>=160&&b.readUInt32LE(0)===252&&b.readUInt32LE(4)===1,'unsupported ZDB');
  const count=b.readUInt32LE(152),stride=b.readUInt32LE(156);
  assert(stride===92&&count<10000&&160+count*stride<=b.length,'invalid ZDB directory');
  return Array.from({length:count},(_,i)=>{
    const at=160+i*stride,end=b.indexOf(0,at+4);assert(b.readUInt32LE(at)===92&&end>=at+4&&end<at+68);
    const name=b.toString('ascii',at+4,end),offset=b.readUInt32LE(at+68),size=b.readUInt32LE(at+72);
    assert(offset>=160+count*stride&&offset+size<=b.length);return {name,offset,size};
  });
}
const NAMES=['ret_accuracy','ret_rifle_01','ret_rifle_02','ret_shotgun_01','ret_shotgun_02','ret_sidearm_01','ret_sidearm_02'];
function extract(iso){
  const fd=fs.openSync(iso,'r');let map;
  try{map=Buffer.alloc(10074112);assert.equal(fs.readSync(fd,map,0,map.length,1944771*2048),map.length);}finally{fs.closeSync(fd);}
  const entries=zdb(map),get=name=>{const found=entries.filter(e=>e.name==='RUN\\COMMON\\'+name);assert.equal(found.length,1);const e=found[0];return map.subarray(e.offset,e.offset+e.size);};
  const tx=get('HUD2_TXR.ZED'),pa=get('HUD2_PAL.ZED'),palKeys=archive(pa).entries,palettes=new Map();
  for(const e of palKeys.filter(e=>e.name==='par')){
    const p=pa.subarray(e.offset,e.offset+e.size),buf=palKeys.find(k=>k.parent===e.parent&&k.name==='buf');
    assert(p.length===8&&buf&&p.readUInt16LE(4)===buf.size);
    palettes.set(p.readUInt32LE(0),{format:p[6],buf:pa.subarray(buf.offset,buf.offset+buf.size)});
  }
  const keys=archive(tx).entries,images=[];
  for(const name of NAMES){
    const nodes=keys.filter(e=>e.name==='texdat'&&keys[e.parent]?.name===name+'.tif');assert.equal(nodes.length,1);
    const e=nodes[0],raw=tx.subarray(e.offset,e.offset+e.size),d=decode(raw,palettes),bytes=png(d.w,d.h,d.rgba);
    images.push({name,width:d.w,height:d.h,source_sha256:sha(raw),rgba_sha256:sha(d.rgba),png_sha256:sha(bytes),rgba:d.rgba,png:bytes});
  }
  return {source:{game:'SOCOM II USA',map:'RUN/MP51.ZDB',map_lba:1944771,texture_bank:'RUN/COMMON/HUD2_TXR.ZED',palette_bank:'RUN/COMMON/HUD2_PAL.ZED',texture_bank_sha256:sha(tx),palette_bank_sha256:sha(pa)},images};
}
if(require.main===module){
  const [iso,out]=process.argv.slice(2);assert(iso&&out,'usage: node tools/socom2_reticle_reference.cjs game.iso NEW_OUTPUT_DIRECTORY');assert(!fs.existsSync(out),'output must be new');
  const result=extract(iso);fs.mkdirSync(out,{recursive:true});
  for(const im of result.images)fs.writeFileSync(path.join(out,im.name+'.png'),im.png,{flag:'wx'});
  const manifest={schema_version:1,source:result.source,note:'Source pixels decoded; on-screen assembly, display scaling and timing must be verified separately.',images:result.images.map(({rgba,png,...meta})=>meta)};
  fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(manifest));
}
module.exports={extract,zdb};
