"""Read-only source preservation and independent GLB import validation."""
from pathlib import Path
import bpy
import hashlib
import json
import math

OUT=Path(__file__).resolve().parent
report=json.loads((OUT/'revision_report.json').read_text())
expected={
    OUT.parent/'pistol_batch/socom2_pistols_review.blend':'c70ce0bbb69abdac7c50532314dc833888ae01bc33948eb393fd2f8bdcb548aa',
    OUT.parent/'p9s_silenced_study.blend':'748081b0aba5994a75678f84a97e5152920570bc1b8ce1e6b2ba77f39a1d642a',
}
for path,digest in expected.items():assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,str(path)
results=[]
for item in report['items']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(OUT/item['asset']))
    meshes=[obj for obj in bpy.data.objects if obj.type=='MESH'];assert len(meshes)==1
    mesh=meshes[0].data;mesh.calc_loop_triangles()
    assert len(mesh.loop_triangles)==item['triangles']
    assert all(math.isfinite(value) for vertex in mesh.vertices for value in vertex.co)
    assert all(p.area>1e-13 for p in mesh.polygons),item['id']
    assert all(slot.material for slot in meshes[0].material_slots)
    assert len(mesh.uv_layers)>0
    textures=[n for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes
              if n.type=='TEX_IMAGE' and n.image]
    assert textures,('Missing embedded grip map',item['id'])
    results.append({'id':item['id'],'result':'PASS','triangles':len(mesh.loop_triangles),
                    'materials':len(meshes[0].material_slots),'embedded_texture_nodes':len(textures)})
bpy.ops.wm.open_mainfile(filepath=str(OUT/'photo_matched_pistols_v2.blend'))
roots=[obj for obj in bpy.data.objects if obj.type=='EMPTY' and obj.name.endswith('_v2_review')]
assert len(roots)==4
assert all(root.children for root in roots)
result={'result':'PASS','models_checked':4,'original_blend_hashes_unchanged':True,
    'editable_v2_roots':len(roots),'checks':['empty-scene GLB import','triangle-count parity',
    'finite coordinates','positive triangle areas','material slots','UVs and embedded grip normal map',
    'editable Blender roots','original file SHA-256 preservation'],'items':results,
    'not_tested':['gameplay integration','mechanical function','full 3D photo equivalence']}
(OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('PHOTO_MATCH_VERIFICATION',json.dumps(result))
