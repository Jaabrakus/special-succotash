'use strict';
// Explicit local-only source asset variant. Every raw input is checked against
// the supplied ISO before decoding. No source files are part of the repository.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {openIso}=require('../extract_iso_camera_reference.cjs');
const {extract:geometry}=require('./desert_glory.cjs');
const {extract:textures}=require('./textures.cjs');
const {convert}=require('./convert.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function build(isoFile,library,out,enhancementFile) {
  assert(!fs.existsSync(out),'Fresh output directory required');
  const manifest=JSON.parse(fs.readFileSync(path.join(library,'manifest.json')));
  assert.equal(manifest.id,'MP6');
  const iso=openIso(isoFile);let disc;
  try {disc=iso.find('RUN/MP6.ZDB').bytes;} finally {iso.close();}
  assert.equal(sha(disc),manifest.source_sha256);
  for(const suffix of ['--MP6.ZED','--MP6_GEO.ZED','--MP6_MDL.ZED','--MP6_TXR.ZED','--MP6_PAL.ZED','--WORL_MDL.ZED']) {
    const entries=manifest.assets.filter(e=>e.file.endsWith(suffix));assert.equal(entries.length,1);
    const e=entries[0], raw=path.join(library,'raw',path.basename(e.file));
    assert.equal(sha(disc.subarray(e.offset,e.offset+e.size)),e.sha256);
    assert.equal(sha(fs.readFileSync(raw)),e.sha256,'Raw file mismatch '+suffix);
  }
  fs.mkdirSync(out,{recursive:true});
  const textureDir=path.join(out,'textures'), decoded=textures(library,textureDir);
  const paths=new Map(decoded.decoded.map(t=>[t.name,path.join(textureDir,t.name+'.png')]));
  const enhancements=enhancementFile?JSON.parse(fs.readFileSync(enhancementFile)):[];
  assert(Array.isArray(enhancements));
  for(const e of enhancements) {
    assert(paths.has(e.texture),'Enhancement has no decoded source');
    assert(!decoded.decoded.find(t=>t.name===e.texture).alpha,'Alpha textures require separate mask validation');
    assert.equal(sha(fs.readFileSync(paths.get(e.texture))),e.original_sha256);
    const image=path.resolve(path.dirname(enhancementFile),e.file),bytes=fs.readFileSync(image);
    assert.equal(sha(bytes),e.enhanced_sha256);
    assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
    assert(bytes.readUInt32BE(16)<=4096 && bytes.readUInt32BE(20)<=4096,'Texture budget exceeded');
    // Preserve decoder output; the explicit override is separate and hashed.
    paths.set(e.texture,image);
  }
  const geometryDir=path.join(out,'geometry');
  const report=geometry(isoFile,library,geometryDir,{sourceTextures:paths});
  const propDir=path.join(geometryDir,'props');
  const props=convert(library,propDir,{packetOrigins:true,textureDirectory:textureDir,alphaTextures:new Set(decoded.decoded.filter(t=>t.alpha).map(t=>t.name))});
  report.texture_mode='source_enhanced';
  report.scope='Local source architecture, original UVs and decoded textures; explicit AI texture overrides. Supported static source props only. Not source lighting, dynamics or release rights.';
  report.enhancements=enhancements;
  report.source_props=props.converted;
  report.deferred_props=props.deferred;
  report.texture_decode=decoded;
  fs.writeFileSync(path.join(geometryDir,'desert_glory.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({source_output:geometryDir,sectors:report.chunks.length,source_props:props.converted.length,deferred_props:props.deferred.length,enhanced:enhancements.length}));
  return report;
}
if(require.main===module)build(...process.argv.slice(2));
module.exports={build};
