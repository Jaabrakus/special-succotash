'use strict';
// Local disc study. Default uses project textures; explicit source variant keeps UVs.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {archive} = require('./archive.cjs');
const {packets, bindings} = require('./mesh.cjs');
const {glb} = require('./glb.cjs');
const {openIso} = require('../extract_iso_camera_reference.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const identity = () => [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1];
function multiply(a,b) { return Array.from({length:16},(_,i) => [0,1,2,3].reduce((s,k)=>s+a[k*4+i%4]*b[Math.floor(i/4)*4+k],0)); }
function transform(m,v,w=1) { return [0,1,2].map(i=>m[i]*v[0]+m[4+i]*v[1]+m[8+i]*v[2]+m[12+i]*w); }
function bounds(positions) {
  const min=[Infinity,Infinity,Infinity], max=[-Infinity,-Infinity,-Infinity];
  for(const v of positions) for(let j=0;j<3;j++) { assert(Number.isFinite(v[j])); min[j]=Math.min(min[j],v[j]); max[j]=Math.max(max[j],v[j]); }
  return {min,max};
}
function finish(bytes) {
  // Tune only this generated study's materials. Shared converter defaults stay intact.
  const jsonBytes=bytes.readUInt32LE(12), doc=JSON.parse(bytes.toString('utf8',20,20+jsonBytes));
  doc.samplers[0].magFilter=9729;
  for(const m of doc.materials) {
    m.pbrMetallicRoughness.baseColorFactor=m.name==='masonry'?[.70,.68,.62,1]:[.85,.83,.78,1];
  }
  let json=Buffer.from(JSON.stringify(doc)); json=Buffer.concat([json,Buffer.alloc((4-json.length%4)%4,32)]);
  const tail=bytes.subarray(20+jsonBytes), header=Buffer.from(bytes.subarray(0,20));
  header.writeUInt32LE(20+json.length+tail.length,8);header.writeUInt32LE(json.length,12);
  return Buffer.concat([header,json,tail]);
}
function extract(isoFile, library, out, options = {}) {
  const verifyOnly=out==='--verify';
  assert(verifyOnly || !fs.existsSync(out),'Choose a fresh output directory; never overwrite a study.');
  const manifest=JSON.parse(fs.readFileSync(path.join(library,'manifest.json'),'utf8'));
  assert.equal(manifest.id,'MP6');
  const iso=openIso(isoFile); let source;
  try { source=iso.find('RUN/MP6.ZDB'); } finally { iso.close(); }
  assert.equal(sha(source.bytes),manifest.source_sha256,'Library differs from supplied disc');
  const hashes={};
  function read(suffix) {
    const matches=manifest.assets.filter(e=>e.file.endsWith(suffix)); assert.equal(matches.length,1);
    const e=matches[0]; assert(e.offset>=0 && e.offset+e.size<=source.bytes.length);
    const b=source.bytes.subarray(e.offset,e.offset+e.size);
    assert.equal(sha(b),e.sha256,'Disc entry checksum mismatch'); hashes[suffix]=e.sha256; return b;
  }
  const cfg=read('--MP6.ZED'), ck=archive(cfg).entries.find(e=>e.name==='MetersPerUnit');
  const scale=cfg.readFloatLE(ck.offset); assert(Math.abs(scale-.1)<1e-7);
  const geo=read('--MP6_GEO.ZED'), entries=archive(geo).entries;
  const children=new Map(); for(const e of entries) { if(!children.has(e.parent)) children.set(e.parent,[]); children.get(e.parent).push(e); }
  const kids=e=>children.get(e.index)||[];
  const child=(e,name)=>kids(e).find(x=>x.name===name);
  function params(e) {
    const p=child(e,'nparams'); assert(p&&p.size===96,'Unsupported node parameters');
    const matrix=Array.from({length:16},(_,i)=>geo.readFloatLE(p.offset+i*4));
    assert(matrix.every(Number.isFinite)); assert(Math.abs(matrix[15]-1)<.0001);
    const min=[0,1,2].map(i=>geo.readFloatLE(p.offset+64+i*4)), max=[0,1,2].map(i=>geo.readFloatLE(p.offset+76+i*4));
    return {matrix,min,max,type:geo.readUInt32LE(p.offset+88)};
  }
  const model=read('--WORL_MDL.ZED'), ma=archive(model).entries, world=ma.find(e=>e.name==='worldmodel');
  const data=model.subarray(world.offset,world.offset+world.size), refs=ma.filter(e=>e.parent===world.index);
  const all=packets(data,1), byOffset=new Map(all.map(p=>[p.start,p]));
  const materialDirectory=path.resolve(__dirname,'../../assets/textures/environment/original_materials');
  const texturePaths=options.sourceTextures || new Map(Object.entries({masonry:'warm_masonry',rock:'rough_rock',earth:'packed_earth',metal:'dark_concrete',wood:'pine_bark'}).map(([key,file])=>[key,path.join(materialDirectory,file+'_albedo_v1.png')]));
  function material(texture) {
    // Audited opaque wall_bullets and stepstain images are structural surfaces,
    // NOT decals. Do not infer transparency from a suggestive filename.
    if(/cloud|null_xmas|bomb_glow|shadow|oilstain|truck_exhaust|sign_stayout|balcony_rail/.test(texture)) return null;
    if(/wood/.test(texture)) return 'wood';
    if(/metal|beam_|fueltank/.test(texture)) return 'metal';
    if(/rock1/.test(texture)) return 'rock';
    if(/floor_dirty|rubble/.test(texture)) return 'earth';
    return 'masonry';
  }
  const report={schema_version:1,map_id:'desert_glory_local',name:'Desert Glory — local recreation',local_research_only:true,
    source:{archive:'RUN/MP6.ZDB',sha256:manifest.source_sha256,entry_sha256:hashes},meters_per_unit:scale,
    scope:'Source architecture with project-owned surface textures and replacement props. No original textures, game code, AI, hostage mode or exact PS2 renderer parity.',
    chunks:[],instances:[],omitted:[],source_packets:all.length,validated_packets:0,matched_draw_keys:0,packet_origins:0};
  let ordinal=-1; const used=new Set(), output=[], sectors=new Map();
  function walk(e,parent) {
    const p=params(e), matrix=multiply(parent,p.matrix);
    if(p.type===2) {
      const key=child(e,'model_name');
      if(key) {
        const name=geo.toString('ascii',key.offset,key.offset+key.size).replace(/\0.*$/s,'');
        const prototype=entries.find(x=>x.name===name && entries[x.parent]?.name==='models');
        report.instances.push({name:e.name,model:name,matrix,source_bounds:prototype?params(prototype):null});
      }
      return;
    }
    const visual=child(e,'visuals'), vs=visual?kids(visual):[];
    // This MP6 export numbers populated visual arrays; empty visual flags are stale.
    // Fail closed if the complete draw-key census/bounds no longer agrees.
    if(vs.length) ordinal++;
    for(let i=0;i<vs.length;i++) {
      const key=`N${String(ordinal).padStart(3,'0')}_${String(i).padStart(3,'0')}`;
      const ref=refs.find(r=>r.name===key); assert(ref,'Unresolved draw key '+key); report.matched_draw_keys++;
      const accepted=[];
      for(const [offset,texture] of bindings(data,[model.readUInt32LE(ref.offset)])) {
        const packet=byOffset.get(offset); assert(packet && !used.has(offset),'Missing/duplicate world packet'); used.add(offset);
        const origin=[0,1,2].map(j=>data.readFloatLE(offset+56+j*4));
        assert(origin.every(Number.isFinite)); if(origin.some(x=>x!==0)) report.packet_origins++;
        const local=packet.positions.map(v=>v.map((x,j)=>x+origin[j]));
        assert(local.every(v=>v.every((x,j)=>x>=p.min[j]-.2 && x<=p.max[j]+.2)),key+' outside source node bounds'); report.validated_packets++;
        const surface=material(texture) ? (options.sourceTextures ? texture : material(texture)) : null;
        if(!surface) {report.omitted.push({key,node:e.name,texture,triangles:packet.faces,reason:'Original sky/effect/decal or alpha-card requires replacement, not opaque collision'});continue;}
        const positions=local.map(v=>transform(matrix,v).map(x=>x*scale));
        const normals=packet.normals.map(v=>{const n=transform(matrix,v,0),len=Math.hypot(...n);assert(len>.01);return n.map(x=>x/len);});
        if(options.sourceTextures) {
          assert(texturePaths.has(texture), 'Missing verified source texture '+texture);
          accepted.push({...packet,positions,normals,texture});
          continue;
        }
        // Planar metre-based UVs per triangle: new materials do not inherit atlas seams.
        const flat={positions:[],normals:[],uv:[],indices:[],faces:packet.faces,texture:surface};
        for(let t=0;t<packet.indices.length;t+=3) {
          const idx=packet.indices.slice(t,t+3), v=idx.map(i=>positions[i]);
          const u=v[1].map((x,j)=>x-v[0][j]),w=v[2].map((x,j)=>x-v[0][j]);
          const n=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]].map(Math.abs);
          const axis=n.indexOf(Math.max(...n)), axes=axis===1?[0,2]:(axis===0?[2,1]:[0,1]);
          for(const k of idx) {flat.indices.push(flat.positions.length);flat.positions.push(positions[k]);flat.normals.push(normals[k]);flat.uv.push(axes.map(j=>positions[k][j]/3));}
        }
        accepted.push(flat);
      }
      if(accepted.length) {
        const bb=bounds(accepted.flatMap(p=>p.positions)),origin=[(bb.min[0]+bb.max[0])/2,bb.min[1],(bb.min[2]+bb.max[2])/2];
        const sector=`${Math.floor(origin[0]/64)}_${Math.floor(origin[2]/64)}`;
        if(!sectors.has(sector)) sectors.set(sector,[]);
        sectors.get(sector).push(...accepted);
        report.chunks.push({key,node:e.name,origin,bounds:bb,triangles:accepted.reduce((s,p)=>s+p.faces,0)});
      }
    }
    const branch=child(e,'children'); if(branch) for(const next of kids(branch)) walk(next,matrix);
  }
  walk(entries.find(e=>e.name==='worldmodel'),identity());
  assert.equal(report.matched_draw_keys,refs.length); assert.equal(used.size,all.length); assert.equal(all.length,581);
  assert(!report.omitted.some(p=>/wall_bullets|stepstain/.test(p.texture)), 'Opaque wall/stair regression');
  report.bounds=bounds(report.chunks.flatMap(c=>[c.bounds.min,c.bounds.max]));
  report.triangles=report.chunks.reduce((s,c)=>s+c.triangles,0);
  assert.equal(report.triangles,13217,'Unexpected structural triangle census');
  assert.equal(report.triangles+report.omitted.reduce((s,p)=>s+p.triangles,0),13900,'Every source triangle accounted for');
  report.source_chunks=report.chunks; report.chunks=[];
  // Batch by spatial sector, not by source packet: avoid hundreds of duplicate
  // embedded high-resolution texture sets and draw calls in the playable map.
  for(const [key,accepted] of sectors) {
    const bb=bounds(accepted.flatMap(p=>p.positions)),origin=[(bb.min[0]+bb.max[0])/2,bb.min[1],(bb.min[2]+bb.max[2])/2];
    const file=(options.sourceTextures?'desert_glory_source_sector_':'desert_glory_sector_')+key+'.glb';
    const bytes=glb('DesertGlorySector'+key,accepted.map(p=>({...p,positions:p.positions.map(v=>v.map((x,j)=>x-origin[j]))})),texturePaths,{local_research_only:true,source_archive_sha256:manifest.source_sha256});
    output.push([file,options.sourceTextures?bytes:finish(bytes)]);
    report.chunks.push({key,node:'Architecture sector '+key,file,origin,bounds:bb,triangles:accepted.reduce((s,p)=>s+p.faces,0)});
  }
  if(!verifyOnly) {
    fs.mkdirSync(out,{recursive:true}); for(const [name,bytes] of output) fs.writeFileSync(path.join(out,name),bytes,{flag:'wx'});
    fs.writeFileSync(path.join(out,'desert_glory.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  }
  console.log(JSON.stringify({output:out,chunks:report.chunks.length,triangles:report.triangles,draw_keys:report.matched_draw_keys,validated_packets:report.validated_packets,packet_origins:report.packet_origins,instances:report.instances.length,bounds:report.bounds}));
  return report;
}
if(require.main===module) extract(...process.argv.slice(2));
module.exports={extract,multiply,transform,bounds};
