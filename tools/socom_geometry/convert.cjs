'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {archive}=require('./archive.cjs'),{packets,bindings}=require('./mesh.cjs'),{glb}=require('./glb.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function convert(mapDir,out,options={}){
  assert(!fs.existsSync(out),'choose a fresh output directory');
  const raw=path.join(mapDir,'raw'),files=fs.readdirSync(raw),find=suffix=>{const f=files.filter(f=>f.endsWith(suffix));assert.equal(f.length,1,'ambiguous source '+suffix);return fs.readFileSync(path.join(raw,f[0]));};
  const mapId=path.basename(mapDir),config=find('--'+mapId+'.ZED'),keys=archive(config).entries,scaleEntry=keys.find(e=>e.name==='MetersPerUnit');assert(scaleEntry&&scaleEntry.size===4,'missing source scale');const scale=config.readFloatLE(scaleEntry.offset);assert(scale>0&&scale<10,'invalid meters per unit');
  const texturePaths=new Map();for(const file of fs.readdirSync(path.join(mapDir,'png'))){let name=file.replace(/^\d+--/,'').replace(/\.png$/,'');let full=path.join(mapDir,'png',file);if(texturePaths.has(name))assert.equal(sha(fs.readFileSync(full)),sha(fs.readFileSync(texturePaths.get(name))),'ambiguous decoded texture '+name);texturePaths.set(name,full);}
  const model=find('--'+mapId+'_MDL.ZED'),geo=find('--'+mapId+'_GEO.ZED'),modelKeys=archive(model).entries,geoKeys=archive(geo).entries;
  if(options.textureDirectory)for(const f of fs.readdirSync(options.textureDirectory).filter(f=>f.endsWith('.png')))texturePaths.set(f.slice(0,-4),path.join(options.textureDirectory,f));
  const report={map_id:mapId,meters_per_unit:scale,source_sha256:{model:sha(model),geometry:sha(geo),config:sha(config)},scope:'Static source meshes only. Original textures/UVs; source coordinates converted to meters. No original instancing, transparency, lightmaps or complete map reconstruction claimed.',converted:[],deferred:[]};
  if(options.alphaTextures)report.scope='Static source meshes with source RGBA32 palette-alpha cutouts. Original textures/UVs; source coordinates converted to meters. No original instancing, blended-material parity, lightmaps or complete map reconstruction claimed.';
  fs.mkdirSync(out,{recursive:true});
  for(const e of modelKeys.filter(e=>e.parent===0&&e.size)){
    if(options.modelFilter&&!options.modelFilter.test(e.name))continue;
    try{
      assert(/^[\w-]+$/.test(e.name),'unsafe output model name');
      const d=model.subarray(e.offset,e.offset+e.size),p=packets(d,scale),refs=modelKeys.filter(r=>r.parent===e.index).map(r=>{assert.equal(r.size,4);return model.readUInt32LE(r.offset);}),bound=bindings(d,refs);
      assert.equal(bound.size,p.length,'unbound source geometry');for(const pkt of p){pkt.texture=bound.get(pkt.start);assert(texturePaths.has(pkt.texture),'texture not yet decoded: '+pkt.texture);}
      const sourceNode=geoKeys.find(k=>k.name===e.name&&geoKeys[k.parent]?.name==='models');assert(sourceNode,'missing model bounds');const bounds=geoKeys.find(k=>k.parent===sourceNode.index&&k.name==='nparams');assert(bounds&&bounds.size===96,'missing nparams');
      const min=[64,68,72].map(k=>geo.readFloatLE(bounds.offset+k)*scale),max=[76,80,84].map(k=>geo.readFloatLE(bounds.offset+k)*scale);
      const actualMin=[Infinity,Infinity,Infinity],actualMax=[-Infinity,-Infinity,-Infinity];for(const pkt of p)for(const v of pkt.positions)for(let k=0;k<3;k++){actualMin[k]=Math.min(actualMin[k],v[k]);actualMax[k]=Math.max(actualMax[k],v[k]);}
      // Quantized vertices must agree with independently stored source bounds.
      for(let k=0;k<3;k++)assert(actualMin[k]>=min[k]-scale/16-.00001&&actualMax[k]<=max[k]+scale/16+.00001,'decoded positions outside source bbox');
      const file=mapId.toLowerCase()+'_'+e.name+'.glb',asset={name:e.name,file,vertices:p.reduce((s,p)=>s+p.vertices,0),triangles:p.reduce((s,p)=>s+p.faces,0),packets:p.length,source_bounds:{min,max},decoded_bounds:{min:actualMin,max:actualMax},textures:[...new Set(p.map(p=>p.texture))],source_entry:{offset:e.offset,size:e.size,sha256:sha(d)}};
      const bytes=glb(e.name,p,texturePaths,{source:asset,local_research_only:true},options.alphaTextures);fs.writeFileSync(path.join(out,file),bytes,{flag:'wx'});report.converted.push({...asset,sha256:sha(bytes)});
    }catch(err){report.deferred.push({name:e.name,reason:err.message});}
  }
  fs.writeFileSync(path.join(out,'conversion.json'),JSON.stringify(report,null,2),{flag:'wx'});console.log(JSON.stringify(report,null,2));return report;
}
if(require.main===module)convert(process.argv[2],process.argv[3]);module.exports={convert};
