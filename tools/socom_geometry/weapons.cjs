'use strict';
// Offline asset conversion only: verified disc bytes, fresh output directory,
// separate native visual nodes. Never changes weapon profiles or live gameplay.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const {archive} = require('./archive.cjs');
const {decode, png} = require('./textures.cjs');
const {glb} = require('./glb.cjs');
const {openIso} = require('../extract_iso_camera_reference.cjs');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function sourceFiles(isoPath, libraryPath) {
  const manifest = JSON.parse(fs.readFileSync(path.join(libraryPath, 'manifest.json'), 'utf8'));
  assert.equal(manifest.id, 'MP1');
  const iso = openIso(isoPath);
  let source;
  try { source = iso.find(manifest.source).bytes; } finally { iso.close(); }
  assert.equal(sha(source), manifest.source_sha256, 'Original ISO/container mismatch');
  const hashes = {};
  const read = suffix => {
    const matches = manifest.assets.filter(e => e.file.endsWith('--' + suffix));
    assert.equal(matches.length, 1, 'Missing/ambiguous source archive ' + suffix);
    const e = matches[0];
    assert(e.offset >= 0 && e.size > 0 && e.offset + e.size <= source.length);
    const bytes = source.subarray(e.offset, e.offset + e.size);
    assert.equal(sha(bytes), e.sha256, 'Source entry checksum mismatch');
    hashes[suffix] = e.sha256;
    return bytes;
  };
  return {manifest, read, hashes};
}

function paletteMap(bytes) {
  const keys = archive(bytes).entries, result = new Map();
  for (const e of keys.filter(e => e.name === 'par')) {
    const p = bytes.subarray(e.offset, e.offset + e.size);
    const b = keys.find(k => k.parent === e.parent && k.name === 'buf');
    assert(p.length === 8 && b && p.readUInt16LE(4) === b.size, 'Invalid palette record');
    const id = p.readUInt32LE(0);
    assert(!result.has(id), 'Ambiguous palette id');
    result.set(id, {format: p[6], buf: bytes.subarray(b.offset, b.offset + b.size)});
  }
  return result;
}

function decodeTexture(raw, palettes) {
  if (raw.length < 32 || raw[12] !== 16) return {...decode(raw, palettes), encoding: 'PSMT8 palette'};
  // MP1/JUNK's original null_xmas.bmp uses direct PSMCT16, not a palette.
  // Bound this path to opaque RGB5551. Do not invent TEXA alpha behavior.
  const w=raw.readUInt16LE(0), h=raw.readUInt16LE(2), size=raw.readUInt32LE(4);
  assert(w>0 && h>0 && w<=2048 && h<=2048 && size===w*h*2 && 32+size<=raw.length,
    'Unsupported direct texture dimensions/payload');
  assert((raw[15]&3)===0, 'Unsupported direct texture flags');
  let tex0=null;
  for (let at=32+size;at+16<=raw.length;at+=16) if (raw.readBigUInt64LE(at+8)===6n) {
    assert.equal(tex0,null,'Multiple direct texture TEX0 records'); tex0=raw.readBigUInt64LE(at);
  }
  assert(tex0!==null && Number(tex0>>20n&63n)===2, 'Direct texture is not GS PSMCT16');
  assert(2**Number(tex0>>26n&15n)===w && 2**Number(tex0>>30n&15n)===h,
    'Direct texture TEX0 dimensions mismatch');
  const rgba=Buffer.alloc(w*h*4), five=n => (n<<3)|(n>>2);
  for (let i=0;i<w*h;i++) {
    const value=raw.readUInt16LE(32+i*2);
    assert(value&0x8000,'Direct texture alpha/TEXA requires further investigation');
    rgba.set([five(value&31),five(value>>5&31),five(value>>10&31),255],i*4);
  }
  return {w,h,rgba,alpha:false,encoding:'PSMCT16 opaque RGB5551'};
}

function preflightTextures(source, models) {
  const required=new Set(models.flatMap(m => m.parts.flatMap(p => p.packets.map(x => x.texture))));
  const records=new Map(), archiveCache=new Map(), paletteCache=new Map();
  const index=name => {
    if (archiveCache.has(name)) return archiveCache.get(name);
    const bytes=source.read(name), keys=archive(bytes).entries;
    const found=keys.filter(e => e.name==='texdat').map(e => ({name:keys[e.parent].name,
      texture_archive:name,raw:bytes.subarray(e.offset,e.offset+e.size),source_texture_offset:e.offset}));
    assert(new Set(found.map(e => e.name)).size===found.length,'Duplicate texture in '+name);
    archiveCache.set(name,found);return found;
  };
  // Retain the complete 51-texture shared WEAP library, then exact dependencies.
  for (const item of index('WEAP_TXR.ZED')) records.set(item.name,item);
  const missing=[...required].filter(name => !records.has(name)), matches=new Map(missing.map(n => [n,[]]));
  if (missing.length) for (const entry of source.manifest.assets) {
    const name=path.basename(entry.file).split('--')[1];
    if (!name?.endsWith('_TXR.ZED') || name==='WEAP_TXR.ZED') continue;
    for (const item of index(name)) if (matches.has(item.name)) matches.get(item.name).push(item);
  }
  const unresolved=missing.filter(n => matches.get(n).length===0);
  assert.equal(unresolved.length,0,'Missing original textures within MP1: '+unresolved.join(', '));
  for (const name of missing) {
    const candidates=matches.get(name);
    assert.equal(candidates.length,1,'Ambiguous original texture within MP1: '+name);
    records.set(name,candidates[0]);
  }
  const prepared=[];
  for (const item of records.values()) {
    assert(/^[\w. -]+$/.test(item.name),'Unsafe source texture name');
    const paletteName=item.texture_archive.replace('_TXR.','_PAL.');
    const hasPalette=source.manifest.assets.some(e => e.file.endsWith('--'+paletteName));
    if (hasPalette && !paletteCache.has(paletteName)) paletteCache.set(paletteName,paletteMap(source.read(paletteName)));
    const decoded=decodeTexture(item.raw,hasPalette?paletteCache.get(paletteName):new Map());
    const bytes=png(decoded.w,decoded.h,decoded.rgba),file=item.name+'.png';
    prepared.push({bytes,report:{name:item.name,file,width:decoded.w,height:decoded.h,
      alpha:decoded.alpha,encoding:decoded.encoding,texture_archive:item.texture_archive,
      palette_archive:hasPalette?paletteName:null,source_texture_offset:item.source_texture_offset,
      source_sha256:sha(item.raw),rgba_sha256:sha(decoded.rgba),png_sha256:sha(bytes)}});
  }
  assert([...required].every(n => prepared.some(t => t.report.name===n)),'Material preflight incomplete');
  return {prepared,required_count:required.size,dependency_names:missing};
}

function writeTextures(preflight, out) {
  const paths=new Map(),alpha=new Set(),report=[];
  fs.mkdirSync(out);
  for (const item of preflight.prepared) {
    const row=item.report;
    fs.writeFileSync(path.join(out,row.file),item.bytes,{flag:'wx'});
    paths.set(row.name,path.join(out,row.file));
    if (row.alpha) alpha.add(row.name);
    report.push(row);
  }
  return {paths,alpha,report};
}

function extract(isoPath, libraryPath, out) {
  assert(isoPath && libraryPath && out, 'Usage: weapons.cjs ISO MP1_LIBRARY FRESH_OUTPUT');
  assert(!fs.existsSync(out), 'Choose a fresh output; no overwriting source or prior exports');
  const source = sourceFiles(isoPath, libraryPath);
  const config = source.read('MP1.ZED');
  const scaleRecord = archive(config).entries.find(e => e.name === 'MetersPerUnit');
  assert(scaleRecord && scaleRecord.size === 4);
  const scale = config.readFloatLE(scaleRecord.offset);
  assert(scale > 0 && scale < 1 && Number.isFinite(scale));
  const model = source.read('WEAP_MDL.ZED'), geometry = source.read('WEAP_GEO.ZED');
  // Decoder must prove geometry/bounds before producing any model files.
  const {decodeModels} = require('./weapon_mesh.cjs');
  const decoded = decodeModels(model, geometry, scale);
  // Resolve and decode EVERY exact material before even creating the output.
  const preflight = preflightTextures(source, decoded.models);
  fs.mkdirSync(out, {recursive: true});
  const tex = writeTextures(preflight, path.join(out, 'textures'));
  const report = {schema_version: 1, source: {archive: source.manifest.source,
    archive_sha256: source.manifest.source_sha256, entries: source.hashes},
    meters_per_unit: scale, status: 'Source asset conversion; runtime mounts not integrated',
    limitations: ['Not original PS2 material/lighting parity.',
      'LOD and visual nodes stay separate; original selection logic is not implemented.',
      'Gun assets are not executable shot/trajectory logic.',
      'Source markers do not establish the missing held-weapon parent transform.'],
    material_preflight:{required:preflight.required_count,dependency_names:preflight.dependency_names,
      scope:'Exact names from source-hash-verified MP1 TXR/PAL archives only'},
    textures: tex.report, models: [], deferred: decoded.deferred || []};
  fs.mkdirSync(path.join(out, 'models'));
  for (const entry of decoded.models) {
    assert(/^[\w.-]+$/.test(entry.name));
    const record = {...entry, parts: []};
    for (const part of entry.parts) {
      assert(/^[\w.-]+$/.test(part.name));
      for (const p of part.packets) assert(tex.paths.has(p.texture), 'Missing source texture: ' + p.texture);
      const file = entry.name + '__' + part.name + '.glb';
      const {packets, ...metadata} = part;
      const bytes = glb(part.name, packets, tex.paths, {source_model: entry.name,
        source_node: metadata, original_source_sha256: source.hashes['WEAP_MDL.ZED']}, tex.alpha);
      fs.writeFileSync(path.join(out, 'models', file), bytes, {flag: 'wx'});
      record.parts.push({...metadata, file, sha256: sha(bytes)});
    }
    report.models.push(record);
  }
  fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  console.log(JSON.stringify({output: out, models: report.models.length,
    parts: report.models.reduce((n,m) => n + m.parts.length, 0),
    textures: report.textures.length, deferred: report.deferred}));
  return report;
}

function verifyMaterials(isoPath, libraryPath) {
  const source=sourceFiles(isoPath,libraryPath);
  const {decodeModels}=require('./weapon_mesh.cjs');
  const models=decodeModels(source.read('WEAP_MDL.ZED'),source.read('WEAP_GEO.ZED'),.1).models;
  const material=preflightTextures(source,models);
  assert.equal(material.required_count,54);assert.equal(material.prepared.length,54);
  const missingName='__missing_source_regression__.tif';
  const mkdir=fs.mkdirSync,write=fs.writeFileSync;
  let writeAttempts=0;
  try {
    fs.mkdirSync=fs.writeFileSync=() => {writeAttempts++;throw new Error('Material preflight wrote output');};
    assert.throws(() => preflightTextures(source,[{parts:[{packets:[{texture:missingName}]}]}]),
      /Missing original textures within MP1: __missing_source_regression__\.tif/);
  } finally {fs.mkdirSync=mkdir;fs.writeFileSync=write;}
  assert.equal(writeAttempts,0);
  const junk=source.read('JUNK_TXR.ZED'),entries=archive(junk).entries;
  const entry=entries.find(e => e.name==='texdat' && entries[e.parent].name==='null_xmas.bmp');
  const raw=junk.subarray(entry.offset,entry.offset+entry.size);
  const direct=decodeTexture(raw,new Map());
  assert.deepEqual([direct.w,direct.h,direct.alpha],[8,8,false]);
  assert.equal(sha(direct.rgba),'ccfc14a18f0fe0d2dbc01a5f37530b835afc82b424898edd07858e5f7b11811e');
  const alpha=Buffer.from(raw);alpha.writeUInt16LE(alpha.readUInt16LE(32)&0x7fff,32);
  assert.throws(() => decodeTexture(alpha,new Map()),/alpha\/TEXA requires further investigation/);
  const short=Buffer.from(raw.subarray(0,80));
  assert.throws(() => decodeTexture(short,new Map()),/dimensions\/payload/);
  const report={passed:true,required_textures:54,decoded_textures:54,
    dependencies:material.dependency_names,missing_material_write_attempts:writeAttempts,
    direct_rgb5551_exact_rgba_hash:true,unsupported_alpha_rejected:true,truncated_direct_texture_rejected:true};
  console.log(JSON.stringify(report));return report;
}
if (require.main === module) {
  const args=process.argv.slice(2);
  if (args[0]==='--verify-materials') verifyMaterials(...args.slice(1));
  else extract(...args);
}
module.exports = {extract, sourceFiles, paletteMap, decodeTexture, preflightTextures, verifyMaterials};
