"""Verify relic geometry parity, preserved sources and portable PBR images."""
from pathlib import Path
import bpy
import hashlib
import json
import math
import struct
import numpy as np

OUT=Path(__file__).resolve().parent;SOURCE=OUT.parent/'photo_match_v2'
report=json.loads((OUT/'relic_report.json').read_text())
def signature(obj):
    obj.data.calc_loop_triangles()
    tris=[tuple(sorted(tuple(round(float(v),6) for v in obj.data.vertices[i].co) for i in t.vertices)) for t in obj.data.loop_triangles]
    return hashlib.sha256(repr(sorted(tris)).encode()).hexdigest()
for filename,digest in report['source_hashes'].items():
    assert hashlib.sha256((SOURCE/filename).read_bytes()).hexdigest()==digest,filename
results=[]
for item in report['models']:
    path=OUT/item['glb'];data=path.read_bytes()
    length,kind=struct.unpack_from('<II',data,12);assert kind==0x4e4f534a
    gltf=json.loads(data[20:20+length]);assert len(gltf['meshes'])==1
    mat=gltf['materials'][0];pbr=mat['pbrMetallicRoughness']
    assert 'baseColorTexture' in pbr and 'metallicRoughnessTexture' in pbr and 'normalTexture' in mat
    assert all('bufferView' in img for img in gltf['images'])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects=[obj for obj in bpy.data.objects if obj.type=='MESH'];assert len(objects)==1
    obj=objects[0];obj.data.calc_loop_triangles()
    assert signature(obj)==item['geometry_signature'],item['id']
    assert len(obj.data.loop_triangles)==item['triangles']
    assert all(math.isfinite(x) for p in obj.data.vertices for x in p.co)
    assert all(p.area>1e-13 for p in obj.data.polygons)
    for channel,filename in item['maps'].items():
        img=bpy.data.images.load(str(OUT/filename));assert tuple(img.size)==(1024,1024)
        pixels=np.empty(1024*1024*4,np.float32);img.pixels.foreach_get(pixels);pixels=pixels.reshape((-1,4))
        visible=pixels[pixels[:,3]>.5,:3];assert len(visible)>10000,(item['id'],channel)
        assert np.isfinite(visible).all()
        assert float(visible.std())>.015,(item['id'],channel,'Texture unexpectedly uniform')
    results.append({'id':item['id'],'geometry_identical':'PASS','triangles':item['triangles'],
        'pbr_embedded':'PASS','embedded_images':len(gltf['images']),'texture_content':'PASS'})
result={'result':'PASS','models_checked':len(results),'approved_geometry_changed':False,
    'approved_source_files_unchanged':True,'checks':['identical triangle-coordinate signatures after export/import',
    'triangle counts','finite geometry','positive triangle areas','source SHA-256 preservation',
    'embedded base color, roughness/metallic and normal maps','1024 texture content and variance'],'models':results}
(OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('RELIC_VERIFICATION',json.dumps(result))
