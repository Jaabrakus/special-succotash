'use strict';
// Focused read-only test of the supplied MP1 weapon library. No exports, runtime
// settings, profile writes or source mutations. Copies used for corrupt inputs.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {archive}=require('./archive.cjs');
const {decodeModels}=require('./weapon_mesh.cjs');

function regression(rawDirectory) {
  assert(rawDirectory,'Usage: weapon_mesh_regression.cjs MP1_RAW_DIRECTORY');
  function load(suffix) {
    const names=fs.readdirSync(rawDirectory).filter(n => n.endsWith('--'+suffix));
    assert.equal(names.length,1,'Missing/ambiguous source archive');
    return fs.readFileSync(path.join(rawDirectory,names[0]));
  }
  const mdl=load('WEAP_MDL.ZED'),geo=load('WEAP_GEO.ZED'),cfg=load('MP1.ZED');
  const scaleEntry=archive(cfg).entries.find(e => e.name==='MetersPerUnit');
  assert(scaleEntry && scaleEntry.size===4);
  const scale=cfg.readFloatLE(scaleEntry.offset);
  assert(Math.abs(scale-.1)<1e-7,'Unexpected supplied source world scale');
  const decoded=decodeModels(mdl,geo,scale),models=decoded.models,parts=models.flatMap(m => m.parts);
  assert.equal(models.length,59);assert.equal(parts.length,112);
  assert.equal(models.reduce((n,m) => n+m.packet_count,0),645);
  assert.equal(models.reduce((n,m) => n+m.draw_key_count,0),212);
  assert.equal(models.reduce((n,m) => n+m.populated_visual_nodes,0),102);
  assert.deepEqual(decoded.deferred,[]);
  for (const p of parts) {
    assert.equal(p.vertices,p.packets.reduce((n,x) => n+x.positions.length,0));
    assert.equal(p.triangles*3,p.packets.reduce((n,x) => n+x.indices.length,0));
    assert.equal(p.material_count,new Set(p.packets.map(x => x.texture)).size);
    assert.equal(p.exported_vertex_count,p.vertices);
    assert.equal(p.exported_index_count,p.triangles*3);
    assert(p.visuals.every(v => Number.parseInt(v.vparams_hex.slice(8,16).match(/../g).reverse().join(''),16)===p.visual_word),
      'Separate source visual selection words were combined');
    assert(p.max_source_bound_overrun<=p.max_position_quantum_source_units+1e-6);
    assert(p.packets.every(packet => packet.normals.every(n => Math.abs(Math.hypot(...n)-1)<1e-8)));
  }
  for (const name of ['m4Acarbine','ak47']) {
    const high=models.find(m => m.name===name).parts.find(p => p.visual_word===0x100);
    assert(Math.abs(high.decoded_model_bounds_meters.max[0]-high.source_node_bounds.max[0]*scale)<1e-12,
      'Positive source extrema must retain normalized 32767 scale');
  }
  const mark23=models.find(m => m.name==='a_mark23');
  assert.equal(mark23.parts.length,2);
  assert(mark23.parts[0].decoded_model_bounds_meters.max[0]<.15);
  assert(mark23.markers.find(m => m.name==='aimpoint').position_model_meters[0]<-.5,
    'Source aim marker is not the visual model AABB');
  const barrett=models.find(m => m.name==='barretm82A1');
  assert.equal(barrett.parts.length,6);
  assert.deepEqual(barrett.parts.filter(p => p.source_node==='thermal_scope').map(p => p.visual_word),[0x100,0x200]);
  const rpg=models.find(m => m.name==='RPG7');
  const projectile=rpg.parts.find(p => p.source_node==='projectile');
  assert(projectile.matrix_model_source[12]>5);
  assert(Math.abs(projectile.decoded_model_bounds_meters.min[0]/scale-projectile.decoded_local_bounds_source.min[0]-projectile.matrix_model_source[12])<1e-10,
    'Child translation must be applied exactly once');

  const me=archive(mdl).entries, ge=archive(geo).entries;
  const markModel=me.find(e => e.name==='a_mark23' && e.parent===0);
  const highNode=ge.find(e => e.name==='mark23_high');
  const highParams=ge.find(e => e.parent===highNode.index && e.name==='nparams');
  const visualGroup=ge.find(e => e.parent===highNode.index && e.name==='visuals');
  const visual=ge.find(e => e.parent===visualGroup.index);
  const vp=ge.find(e => e.parent===visual.index && e.name==='vparams');
  const negative=[];
  const fails=(name,fn,pattern) => { assert.throws(fn,pattern);negative.push(name); };
  fails('NaN source scale',() => decodeModels(mdl,geo,NaN),/Invalid source world scale/);
  fails('zero source scale',() => decodeModels(mdl,geo,0),/Invalid source world scale/);
  const invalidRadius=Buffer.from(mdl); invalidRadius.writeFloatLE(NaN,markModel.offset+68);
  fails('nonfinite packet normalization',() => decodeModels(invalidRadius,geo,scale),/Invalid normalized weapon packet/);
  const wrongRadius=Buffer.from(mdl);wrongRadius.writeFloatLE(100,markModel.offset+68);
  fails('wrong packet normalization',() => decodeModels(wrongRadius,geo,scale),/outside independent source node bounds/);
  const wrongCount=Buffer.from(geo);wrongCount.writeUInt16LE(999,vp.offset+8);
  fails('independent face count mismatch',() => decodeModels(mdl,wrongCount,scale),/Independent visual face count/);
  const wrongBounds=Buffer.from(geo);wrongBounds.writeFloatLE(-.5,highParams.offset+76);
  fails('independent node bounds mismatch',() => decodeModels(mdl,wrongBounds,scale),/outside independent source node bounds/);
  const report={passed:true,models:models.length,visual_nodes:102,parts:parts.length,
    draw_keys:212,packets:645,meters_per_unit:scale,
    max_bound_overrun_source_units:Math.max(...parts.map(p => p.max_source_bound_overrun)),
    negative_checks:negative,
    limitations:'Source byte/geometry test only; no rendered fidelity or equipped-runtime attachment proof.'};
  console.log(JSON.stringify(report));
  return report;
}
if(require.main===module)regression(process.argv[2]);
module.exports={regression};
