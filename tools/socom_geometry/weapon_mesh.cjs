'use strict';
// Translation card: reproduce supplied weapon geometry without changing gameplay.
// Owner: this pure offline decoder. Preserve ISO, assets, profiles and runtime.
// Proof: every draw key, vertex/face count, packet and source-node AABB agrees.
// MERGE normalized weapon decoding; do not change the fixed-point map decoder.
// New-data delta: scope nodes can contain BOTH detail masks. Split by node AND
// the raw visual word, not just by node, so no export stacks separate LODs.
const assert = require('node:assert/strict');
const {archive} = require('./archive.cjs');
const {packets, bindings} = require('./mesh.cjs');

const identity = () => [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1];
const multiply = (a,b) => Array.from({length:16}, (_,i) =>
  [0,1,2,3].reduce((s,k) => s + a[k*4+i%4]*b[Math.floor(i/4)*4+k], 0));
const transform = (m,v) => [0,1,2].map(i => m[i]*v[0]+m[4+i]*v[1]+m[8+i]*v[2]+m[12+i]);
const cross = (a,b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
function normalTransform(matrix) {
  const a=matrix.slice(0,3), b=matrix.slice(4,7), c=matrix.slice(8,11);
  const cofactors=[cross(b,c),cross(c,a),cross(a,b)];
  const det=a.reduce((sum,x,i) => sum+x*cofactors[0][i],0);
  assert(Number.isFinite(det) && Math.abs(det)>1e-12, 'Singular geometry transform');
  return {det, apply: n => {
    const out=[0,1,2].map(i => cofactors.reduce((s,v,k) => s+v[i]*n[k],0)/det);
    const length=Math.hypot(...out);
    assert(Number.isFinite(length) && length>1e-12, 'Invalid transformed normal');
    return out.map(v => v/length);
  }};
}
function bounds(points) {
  assert(points.length, 'Empty geometry bounds');
  const min=[Infinity,Infinity,Infinity], max=[-Infinity,-Infinity,-Infinity];
  for (const p of points) for (let j=0;j<3;j++) {
    assert(Number.isFinite(p[j]), 'Nonfinite weapon vertex');
    min[j]=Math.min(min[j],p[j]); max[j]=Math.max(max[j],p[j]);
  }
  return {min,max};
}
function tree(entries) {
  const byParent=new Map();
  for (const e of entries) {
    if (!byParent.has(e.parent)) byParent.set(e.parent,[]);
    byParent.get(e.parent).push(e);
  }
  const kids=e => byParent.get(e.index)||[];
  const child=(e,name) => {
    const hits=kids(e).filter(x => x.name===name);
    assert(hits.length<=1, 'Ambiguous geometry field '+name);
    return hits[0];
  };
  return {kids,child};
}
function parameters(bytes,entry,child) {
  const p=child(entry,'nparams');
  assert(p && p.size===96, 'Unsupported geometry nparams: '+entry.name);
  const matrix=Array.from({length:16},(_,i) => bytes.readFloatLE(p.offset+i*4));
  assert(matrix.every(Number.isFinite), 'Nonfinite geometry transform');
  assert([3,7,11].every(i => Math.abs(matrix[i])<1e-7) && Math.abs(matrix[15]-1)<1e-7,
    'Unsupported non-affine geometry transform');
  const sourceBounds={min:[0,1,2].map(i => bytes.readFloatLE(p.offset+64+i*4)),
    max:[0,1,2].map(i => bytes.readFloatLE(p.offset+76+i*4))};
  assert(sourceBounds.min.every((v,i) => Number.isFinite(v) && Number.isFinite(sourceBounds.max[i]) && v<=sourceBounds.max[i]),
    'Invalid source geometry bounds');
  return {matrix,source_bounds:sourceBounds,nparams_offset:p.offset,
    node_type_word:bytes.readUInt32LE(p.offset+88),node_flags:bytes.readUInt32LE(p.offset+92)};
}

function decodeModels(modelBuffer,geometryBuffer,metersPerUnit) {
  assert(Buffer.isBuffer(modelBuffer) && Buffer.isBuffer(geometryBuffer), 'Expected archive buffers');
  assert(Number.isFinite(metersPerUnit) && metersPerUnit>0 && metersPerUnit<1, 'Invalid source world scale');
  const modelEntries=archive(modelBuffer).entries, geometryEntries=archive(geometryBuffer).entries;
  const mt=tree(modelEntries), gt=tree(geometryEntries);
  const modelRoot=geometryEntries.find(e => e.name==='models');
  assert(modelRoot, 'Missing geometry model library');
  const models=[];
  for (const model of mt.kids(modelEntries[0])) {
    const candidates=gt.kids(modelRoot).filter(e => e.name===model.name);
    assert.equal(candidates.length,1,'Missing/ambiguous geometry model '+model.name);
    const data=modelBuffer.subarray(model.offset,model.offset+model.size);
    const all=packets(data,1), byOffset=new Map(all.map(p => [p.start,p]));
    const refs=mt.kids(model), refsByName=new Map();
    for (const ref of refs) {
      assert(/^N\d{3}_\d{3}$/.test(ref.name) && ref.size===4, 'Unsupported weapon draw key');
      assert(!refsByName.has(ref.name),'Duplicate weapon draw key'); refsByName.set(ref.name,ref);
    }
    const usedRefs=new Set(), usedPackets=new Set();
    const result={name:model.name,source_model_entry:model.index,source_model_offset:model.offset,
      source_model_size:model.size,source_geometry_entry:candidates[0].index,
      coordinate_space:'Source model axes; matrices baked; positions in metres. No held-weapon axis remap.',
      position_decode:'(packed_i16 * packet_radius / 32767 + packet_origin), then node hierarchy matrix, then MetersPerUnit',
      packet_count:all.length,draw_key_count:refs.length,node_hierarchy:[],markers:[],parts:[]};
    let ordinal=-1;
    function walk(node,parentMatrix,parentPath) {
      const params=parameters(geometryBuffer,node,gt.child), matrix=multiply(parentMatrix,params.matrix);
      const nodePath=[...parentPath,node.name], visualArray=gt.child(node,'visuals');
      const visuals=visualArray?gt.kids(visualArray):[];
      const branch=gt.child(node,'children');
      const nodeRecord={name:node.name,path:nodePath.join('/'),entry:node.index,
        ...params,matrix_model_source:matrix,
        position_model_meters:transform(matrix,[0,0,0]).map(x => x*metersPerUnit),
        visual_count:visuals.length};
      result.node_hierarchy.push(nodeRecord);
      if (!visuals.length && !branch && !gt.child(node,'di')) result.markers.push(nodeRecord);
      if (visuals.length) ordinal++;
      const groups=new Map(), normal=normalTransform(matrix);
      for (let visualIndex=0;visualIndex<visuals.length;visualIndex++) {
        const visual=visuals[visualIndex], vp=gt.child(visual,'vparams');
        assert(vp && vp.size===24, 'Unsupported weapon visual parameters');
        const key=`N${String(ordinal).padStart(3,'0')}_${String(visualIndex).padStart(3,'0')}`;
        const ref=refsByName.get(key); assert(ref,'Missing weapon draw key '+model.name+'/'+key);
        assert(!usedRefs.has(key),'Draw key reused'); usedRefs.add(key);
        const word=geometryBuffer.readUInt32LE(vp.offset+4);
        if (!groups.has(word)) groups.set(word,{
          name:`N${String(ordinal).padStart(3,'0')}_${node.name}_v${word.toString(16).padStart(4,'0')}`,
          source_node:node.name,source_node_path:nodeRecord.path,source_node_index:node.index,
          visual_owner_ordinal:ordinal,visual_word:word,
          visual_word_note:'Raw source selection word. 0x100/0x200 correlate with high/low detail; runtime selection not implemented.',
          matrix_local_source:params.matrix,matrix_model_source:matrix,
          source_node_bounds:params.source_bounds,node_type_word:params.node_type_word,node_flags:params.node_flags,
          visuals:[],packets:[],vertices:0,triangles:0,max_source_bound_overrun:0,
          max_position_quantum_source_units:0,_local:[]});
        const group=groups.get(word);
        let vertexCount=0,faceCount=0;
        const packetOffsets=[];
        const drawOffset=modelBuffer.readUInt32LE(ref.offset);
        for (const [offset,texture] of bindings(data,[drawOffset])) {
          const packet=byOffset.get(offset); assert(packet,'Unresolved weapon packet');
          assert(!usedPackets.has(offset),'Weapon packet shared by multiple visual records');
          usedPackets.add(offset);packetOffsets.push(offset);
          const radius=data.readFloatLE(offset+68);
          const origin=[0,1,2].map(i => data.readFloatLE(offset+56+i*4));
          assert(Number.isFinite(radius) && radius>0 && origin.every(Number.isFinite), 'Invalid normalized weapon packet');
          // mesh.cjs has already divided packed positions by 16. Undo that once.
          // /32767 matches original M4/AK positive bbox extrema exactly; /32768
          // remains one quantization step smaller. This is a checked data decode,
          // not a claim that the missing PS2 VU implementation was reconstructed.
          const quantum=radius/32767;
          const local=packet.positions.map(v => v.map((x,i) => x*16*quantum+origin[i]));
          const tolerance=quantum+1e-6;
          let overrun=0;
          for (const v of local) for (let j=0;j<3;j++) {
            overrun=Math.max(overrun,params.source_bounds.min[j]-v[j],v[j]-params.source_bounds.max[j]);
            assert(v[j]>=params.source_bounds.min[j]-tolerance && v[j]<=params.source_bounds.max[j]+tolerance,
              `Weapon packet outside independent source node bounds: ${model.name}/${key}/${offset}`);
          }
          const indices=packet.indices.slice();
          if (normal.det<0) for (let i=0;i<indices.length;i+=3) [indices[i+1],indices[i+2]]=[indices[i+2],indices[i+1]];
          const positions=local.map(v => transform(matrix,v).map(x => x*metersPerUnit));
          group.packets.push({...packet,texture,positions,normals:packet.normals.map(normal.apply),indices,
            source_origin:origin,source_radius:radius,draw_key:key,visual_word:word});
          group._local.push(...local);
          group.max_source_bound_overrun=Math.max(group.max_source_bound_overrun,overrun);
          group.max_position_quantum_source_units=Math.max(group.max_position_quantum_source_units,quantum);
          vertexCount+=packet.vertices;faceCount+=packet.faces;
        }
        assert.equal(faceCount,geometryBuffer.readUInt16LE(vp.offset+8),'Independent visual face count '+model.name+'/'+key);
        assert.equal(vertexCount,geometryBuffer.readUInt16LE(vp.offset+10),'Independent visual vertex count '+model.name+'/'+key);
        assert(packetOffsets.length,'Empty weapon visual draw list');
        group.visuals.push({draw_key:key,draw_list_offset:drawOffset,vparams_offset:vp.offset,
          vparams_hex:geometryBuffer.subarray(vp.offset,vp.offset+vp.size).toString('hex'),
          faces:faceCount,vertices:vertexCount,packet_offsets:packetOffsets});
        group.vertices+=vertexCount;group.triangles+=faceCount;
      }
      for (const part of groups.values()) {
        assert(/^[\w.-]+$/.test(part.name), 'Unsafe generated weapon part name');
        part.decoded_local_bounds_source=bounds(part._local);
        part.decoded_model_bounds_meters=bounds(part.packets.flatMap(p => p.positions));
        part.packet_count=part.packets.length;
        part.exported_vertex_count=part.vertices;
        part.exported_index_count=part.triangles*3;
        part.textures=[...new Set(part.packets.map(p => p.texture))];
        part.material_count=part.textures.length;
        delete part._local; result.parts.push(part);
      }
      if (branch) for (const next of gt.kids(branch)) walk(next,matrix,nodePath);
    }
    walk(candidates[0],identity(),[]);
    assert.equal(usedRefs.size,refs.length,'Unmatched weapon draw keys: '+model.name);
    assert.equal(usedPackets.size,all.length,'Unmatched weapon geometry packets: '+model.name);
    assert(result.parts.length,'Model has no supported visuals: '+model.name);
    result.populated_visual_nodes=ordinal+1;
    models.push(result);
  }
  assert(models.length,'No weapon models decoded');
  return {models,deferred:[]};
}
module.exports={decodeModels};
