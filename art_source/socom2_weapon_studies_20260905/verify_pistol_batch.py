"""Independent empty-scene re-import gate for the standalone pistol exports."""
from pathlib import Path
import bpy
import json
import math

OUT=Path(__file__).resolve().parent
BATCH=OUT/'pistol_batch'
report=json.loads((BATCH/'pistol_batch_report.json').read_text())
roster=json.loads((OUT/'weapon_build_list.json').read_text())
assert len(roster['items'])==roster['count']==43
assert len({item['id'] for item in roster['items']})==43
assert len(report['items'])==10
results=[]
for item in report['items']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(OUT/item['glb']))
    meshes=[obj for obj in bpy.data.objects if obj.type=='MESH']
    assert len(meshes)==1,(item['id'],len(meshes))
    mesh=meshes[0].data
    mesh.calc_loop_triangles()
    assert len(mesh.loop_triangles)==item['triangles'],item['id']
    assert all(math.isfinite(v) for vertex in mesh.vertices for v in vertex.co)
    assert all(polygon.area>1e-13 for polygon in mesh.polygons),item['id']
    assert all(slot.material is not None for slot in meshes[0].material_slots)
    assert all(len(p.vertices)==3 for p in mesh.polygons)
    assert all(x>0 for x in meshes[0].dimensions),item['id']
    results.append({'id':item['id'],'result':'PASS','triangles':len(mesh.loop_triangles),
                    'materials':len(meshes[0].material_slots),'mesh_objects':len(meshes)})
verification={'result':'PASS','models_checked':len(results),'roster_entries':len(roster['items']),
    'checks':['empty-scene GLB re-import','one mesh per export','triangle-count parity',
              'finite vertex coordinates','positive triangle areas','material assignments',
              'positive three-axis extents','unique 43-entry roster'],'items':results}
(BATCH/'verification.json').write_text(json.dumps(verification,indent=2)+'\n')
print('PISTOL_BATCH_VERIFICATION',json.dumps(verification))
