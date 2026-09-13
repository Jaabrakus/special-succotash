'use strict';
// Offline exact-reference index; see docs/SOURCE_WEAPON_CATALOG_LINKS.md.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function named(rows) {
  const map = new Map();
  for (const row of rows) {
    assert(typeof row.name === 'string', 'Record must have a name');
    if (!map.has(row.name)) map.set(row.name, []);
    map.get(row.name).push(row);
  }
  return map;
}
function resolve(name, map) {
  const matches = typeof name === 'string' ? map.get(name) || [] : [];
  return {name, status: matches.length === 1 ? 'exact' : matches.length > 1 ? 'ambiguous' : 'unresolved', matches};
}
function ammoNames(values) {
  const names = [];
  // Only explicit NAME/list pairs inside AMMO_TYPES. Preserve duplicates.
  function visit(row) {
    for (let i = 0; i < row.length; i++) {
      if (row[i] === 'NAME' && Array.isArray(row[i + 1])) {
        names.push(...row[i + 1]);
        i++;
      } else if (Array.isArray(row[i])) visit(row[i]);
    }
  }
  visit(values);
  return names;
}
function join(reader, assets) {
  assert(Array.isArray(reader.weapons) && Array.isArray(reader.ammunition));
  assert(Array.isArray(assets.models) && Array.isArray(assets.deferred));
  assert.equal(assets.deferred.length, 0, 'Only join complete asset manifests');
  const models = named(assets.models), ammunition = named(reader.ammunition);
  const weapons = reader.weapons.map(w => {
    assert(Array.isArray(w.fields));
    const modelFields = w.fields.filter(f => f.tag === 'ModelName');
    const ammoFields = w.fields.filter(f => f.tag === 'AMMO_TYPES');
    return {name: w.name, source_record_index: w.index, source_context: w.context,
      // All fields retained in original order, not merely ballistic scalars.
      source_fields: w.fields,
      model_field_present: modelFields.length > 0,
      models: modelFields.flatMap(f => f.values.map(name => {
        const r = resolve(name, models);
        return {name, status: r.status, source_field_index: f.index,
          matches: r.matches.map(m => ({name: m.name, source_geometry_entry: m.source_geometry_entry,
            markers: m.markers, parts: m.parts.map(p => ({file: 'models/' + p.file, sha256: p.sha256,
              source_node: p.source_node, visual_word: p.visual_word, textures: p.textures}))}))};
      })),
      ammo_field_present: ammoFields.length > 0,
      ammunition: ammoFields.flatMap(f => ammoNames(f.values).map(name => {
        const r = resolve(name, ammunition);
        return {name, status: r.status, source_field_index: f.index,
          matches: r.matches.map(a => ({source_record_index: a.index, source_context: a.context,
            source_fields: a.fields}))};
      }))};
  });
  const all = kind => weapons.flatMap(w => w[kind]);
  const counts = kind => Object.fromEntries(['exact','unresolved','ambiguous'].map(s => [s, all(kind).filter(r => r.status === s).length]));
  return {schema_version: 1,
    status: 'Offline exact-name reference only; no live equipment or original trajectory implementation',
    limitations: ['Raw source fields do not establish units, defaults or executable equations.',
      'Model and ammunition names are joined exactly; missing and ambiguous references stay unresolved.',
      'Includes gear, turret and effect records, not only player-selectable firearms.',
      'Source visual/LOD words and markers are preserved without inventing selection or held-parent semantics.'],
    counts: {weapon_records: weapons.length, ammunition_records: reader.ammunition.length,
      converted_models: assets.models.length, model_references: counts('models'), ammo_references: counts('ammunition')},
    weapons};
}
function selfTest() {
  const f = (tag, values, index=0) => ({tag, values, index});
  const input = {weapons: [{name:'Test',index:0,context:'ZWEAPON[0]',fields:[
    f('ModelName',['m4']),f('ModelName',['M4']), f('ModelName',['twice']),
    f('AMMO_TYPES', [['NAME',['ammo']],['NAME',['ammo']],['NAME',['missing']]])]}],
    ammunition:[{name:'ammo',index:0,context:'ZAMMO[0]',fields:[f('ImpactDamage',[2.5])]}]};
  const assets = {models:[{name:'m4',parts:[],markers:[]},{name:'twice',parts:[]},{name:'twice',parts:[]}],deferred:[]};
  const r=join(input,assets);
  assert.deepEqual(r.counts.model_references,{exact:1,unresolved:1,ambiguous:1});
  assert.deepEqual(r.counts.ammo_references,{exact:2,unresolved:1,ambiguous:0});
  assert.deepEqual(r.weapons[0].source_fields,input.weapons[0].fields);
  assert.throws(()=>join(input,{...assets,deferred:['missing']}));
  console.log('SOURCE_WEAPON_CATALOG_JOIN_SELF_TEST PASS');
}
function extract(readerPath, manifestPath, output) {
  assert(readerPath && manifestPath && output, 'Usage: source_weapon_catalog_join.cjs READER.json MANIFEST.json NEW_OUTPUT.json');
  assert(!fs.existsSync(output), 'Refuse to overwrite any output');
  const readerBytes=fs.readFileSync(readerPath), assetBytes=fs.readFileSync(manifestPath);
  const reader=JSON.parse(readerBytes), assets=JSON.parse(assetBytes);
  // Verify every linked export against its manifest before any output write.
  const base=path.dirname(path.resolve(manifestPath));
  for (const m of assets.models) for (const p of m.parts) {
    assert(/^[\w.-]+\.glb$/.test(p.file), 'Unsafe asset basename');
    assert.equal(sha(fs.readFileSync(path.join(base,'models',p.file))),p.sha256,'GLB checksum mismatch');
  }
  const report=join(reader,assets);
  report.inputs={weapon_reader:{path:path.resolve(readerPath),sha256:sha(readerBytes),source:reader.source},
    asset_manifest:{path:path.resolve(manifestPath),sha256:sha(assetBytes),source:assets.source}};
  fs.mkdirSync(path.dirname(path.resolve(output)),{recursive:true});
  fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log('SOURCE_WEAPON_CATALOG_JOIN PASS '+JSON.stringify({...report.counts,output}));
  return report;
}
if(require.main===module) {
  if(process.argv[2]==='--self-test') selfTest(); else extract(...process.argv.slice(2));
}
module.exports={join,ammoNames,extract};
