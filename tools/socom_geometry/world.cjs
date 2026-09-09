'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {archive}=require('./archive.cjs'),{packets,bindings}=require('./mesh.cjs'),{glb}=require('./glb.cjs');
function world(mapDir,out){
  assert(!fs.existsSync(out),'choose a fresh output directory');
  const raw=path.join(mapDir,'raw'),names=fs.readdirSync(raw),read=s=>{let n=names.filter(n=>n.endsWith(s));assert.equal(n.length,1);return fs.readFileSync(path.join(raw,n[0]));};
  const cfg=read('--MP51.ZED'),ck=archive(cfg).entries.find(e=>e.name==='MetersPerUnit'),scale=cfg.readFloatLE(ck.offset);
  const b=read('--WORL_MDL.ZED'),a=archive(b),e=a.entries.find(e=>e.name==='worldmodel'),d=b.subarray(e.offset,e.offset+e.size),refs=a.entries.filter(r=>r.parent===e.index),all=packets(d,scale),byOffset=new Map(all.map(p=>[p.start,p]));
  const textures=new Map();for(const f of fs.readdirSync(path.join(mapDir,'png')))textures.set(f.replace(/^\d+--/,'').replace(/\.png$/,''),path.join(mapDir,'png',f));
  fs.mkdirSync(out,{recursive:true});const report={scope:'Original world chunks. Missing texture packets omitted explicitly; sky separated from architecture; no props/lighting/mission logic reconstruction.',chunks:[],omitted:[],excludedSky:[]};const overview=[];
  for(const ref of refs){
    const map=bindings(d,[b.readUInt32LE(ref.offset)]),accepted=[];
    for(const [offset,texture]of map){const packet=byOffset.get(offset);assert(packet,'unresolved world geometry');if(texture==='gen_cloud_n_sun_256x256.tif'){report.excludedSky.push({chunk:ref.name,offset,texture,triangles:packet.faces});continue;}if(textures.has(texture)){accepted.push({...packet,texture});}else report.omitted.push({chunk:ref.name,offset,texture,triangles:packet.faces});}
    if(!accepted.length)continue;
    assert(/^N\d+_\d+$/.test(ref.name),'invalid chunk name');
    const file='mp51_world_'+ref.name+'.glb';
    const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];for(const p of accepted)for(const v of p.positions)for(let axis=0;axis<3;axis++){min[axis]=Math.min(min[axis],v[axis]);max[axis]=Math.max(max[axis],v[axis]);}
    const origin=[(min[0]+max[0])/2,min[1],(min[2]+max[2])/2];
    const centered=accepted.map(p=>({...p,positions:p.positions.map(v=>v.map((n,i)=>n-origin[i]))}));
    fs.writeFileSync(path.join(out,file),glb(ref.name,centered,textures,{local_research_only:true,source_draw_key:ref.name}),{flag:'wx'});
    report.chunks.push({name:ref.name,file,origin,bounds:{min,max},triangles:accepted.reduce((s,p)=>s+p.faces,0),packets:accepted.length});overview.push(...accepted);
  }
  fs.writeFileSync(path.join(out,'overview.glb'),glb('MP51 World — partial materials',overview,textures,{local_research_only:true,omitted:report.omitted}),{flag:'wx'});
  fs.writeFileSync(path.join(out,'world.json'),JSON.stringify(report,null,2),{flag:'wx'});
  console.log(JSON.stringify({chunks:report.chunks.length,triangles:overview.reduce((s,p)=>s+p.faces,0),omitted_packets:report.omitted.length,missing_textures:[...new Set(report.omitted.map(p=>p.texture))]}));return report;
}
if(require.main===module)world(process.argv[2],process.argv[3]);module.exports={world};
