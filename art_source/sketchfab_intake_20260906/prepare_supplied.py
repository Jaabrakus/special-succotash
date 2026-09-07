"""Lossless, offline preparation of this user-supplied intake; no gameplay edits."""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
BASE = Path(__file__).resolve().parent
SOURCE = ROOT / 'untitled folder'
HELD = {'psx_houses': 'Review exact Sketchfab Standard terms before production use.',
        'fix_price_brutalist_low_poly_psx': 'CC BY-NC-SA: hold out of commercial production.'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_uri(folder, uri):
    assert ':' not in uri and '\\' not in uri, f'Unsupported URI: {uri}'
    path = (folder / uri).resolve()
    assert path.is_relative_to(folder.resolve()) and path.is_file(), uri
    return path


def load_glb(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from('<4sII', raw)
    assert magic == b'glTF' and version == 2 and size == len(raw)
    chunks = {}
    offset = 12
    while offset < size:
        length, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        assert offset + length <= size
        chunks[kind] = raw[offset:offset + length]
        offset += length
    return json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]


def main():
    files = sorted(p for p in SOURCE.rglob('*') if p.is_file() and p.name != '.DS_Store')
    assert all(not p.is_symlink() for p in SOURCE.rglob('*')), 'Symlinks not accepted'
    before = {str(p.relative_to(SOURCE)): digest(p) for p in files}
    archive = BASE / 'source_archives' / 'user_supplied_20260906'
    for p in files:
        target = archive / p.relative_to(SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert digest(target) == digest(p), f'Refusing to overwrite changed source: {target}'
        else:
            shutil.copy2(p, target)
    records = []
    for item in sorted(SOURCE.iterdir()):
        if item.suffix == '.glb':
            doc, binary = load_glb(item)
            key = item.stem
        elif item.is_dir() and (item / 'scene.gltf').is_file():
            doc = json.loads((item / 'scene.gltf').read_text())
            binary = None
            key = item.name
        else:
            continue
        extras = doc.get('asset', {}).get('extras', {})
        record = {'id': key, 'source_file': str(item.relative_to(ROOT)),
                  'provenance': extras, 'meshes': len(doc.get('meshes', [])),
                  'materials': len(doc.get('materials', [])), 'images': len(doc.get('images', [])),
                  'skins': len(doc.get('skins', [])),
                  'animations': [a.get('name', '') for a in doc.get('animations', [])],
                  'required_extensions': doc.get('extensionsRequired', [])}
        if key in HELD:
            record.update(status='held', reason=HELD[key])
            records.append(record)
            continue
        assert 'CC-BY-4.0' in str(extras), f'License not allowlisted: {key}'
        output = BASE / 'prepared' / key
        output.mkdir(parents=True, exist_ok=True)
        converted = copy.deepcopy(doc)
        if binary is not None:
            assert len(doc['buffers']) == 1
            assert doc['buffers'][0]['byteLength'] <= len(binary)
            converted['buffers'][0]['uri'] = 'scene.bin'
            (output / 'scene.bin').write_bytes(binary[:doc['buffers'][0]['byteLength']])
            for index, image in enumerate(converted.get('images', [])):
                assert 'bufferView' in image and image['mimeType'] in ('image/png', 'image/jpeg')
                view = doc['bufferViews'][image.pop('bufferView')]
                assert view.get('buffer', 0) == 0
                start = view.get('byteOffset', 0)
                data = binary[start:start + view['byteLength']]
                assert len(data) == view['byteLength']
                ext = '.png' if image['mimeType'] == 'image/png' else '.jpg'
                image['uri'] = f'textures/{index:02d}{ext}'
                target = output / image['uri']
                target.parent.mkdir(exist_ok=True)
                target.write_bytes(data)
        else:
            for resource in doc.get('buffers', []) + doc.get('images', []):
                original = safe_uri(item, resource['uri'])
                target = output / resource['uri']
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, target)
            shutil.copy2(item / 'license.txt', output / 'license.txt')
        for field in ('meshes', 'nodes', 'skins', 'animations', 'accessors', 'materials'):
            assert converted.get(field) == doc.get(field), f'Unexpected modification: {field}'
        character_only = key == 'ps1low_poly_night_vision_special_forces_soldier'
        if character_only:
            # Verified source-specific split: only these two meshes use weapons material.
            assert len(doc['meshes']) == 9 and doc['materials'][1]['name'] == 'weapons'
            assert [i for i, m in enumerate(doc['meshes'])
                    if any(p.get('material') == 1 for p in m['primitives'])] == [7, 8]
            assert doc['nodes'][21]['mesh'] == 7 and doc['nodes'][23]['mesh'] == 8
            converted['meshes'] = converted['meshes'][:7]
            for index in (21, 23):
                converted['nodes'][index].pop('mesh')
                converted['nodes'][index].pop('skin')
            # Keep node indices, skin joints and animation tracks stable. Empty source
            # placeholders and weapon bones are harmless; no weapon geometry remains.
            converted['materials'] = converted['materials'][:1]
            assert converted['meshes'] == doc['meshes'][:7]
            assert converted['skins'] == doc['skins'] and converted['animations'] == doc['animations']
            record.update(source_meshes=9, meshes=7, removed_meshes=['SHOTGUN', 'SMG'],
                          modification='Character-only: weapon meshes removed; body, skeleton and animations retained.')
        (output / 'scene.gltf').write_text(json.dumps(converted, indent=2) + '\n')
        for resource in converted.get('buffers', []) + converted.get('images', []):
            safe_uri(output, resource['uri'])
        (output / 'CREDITS.md').write_text(
            '# Source attribution\n\n' + '\n'.join(f'- {k}: {v}' for k, v in extras.items()) +
            '\n\nChanges: container unpacked to glTF + external textures. ' +
            ('Bundled shotgun and SMG mesh definitions removed at user request. Character geometry, '
             'UVs, skin joints and animation data unchanged. Unused source buffer/texture data retained; '
             'no weapon geometry is instantiated. ' if character_only else
             'Geometry, UVs, transforms, materials, skins and animation data unchanged. ') +
            'Godot scene is a derived '
            'engine import. Attribution must accompany distribution. Source license metadata '
            'does not independently verify third-party trademarks or photo-texture rights.\n')
        record.update(status='editable_copy_prepared', gltf=str((output / 'scene.gltf').relative_to(ROOT)))
        records.append(record)
    after = {str(p.relative_to(SOURCE)): digest(p) for p in files}
    assert before == after
    manifest = {'source_hashes_sha256': before, 'source_files_unchanged': True, 'assets': records,
                'scope': 'Staging only. No game replacement, collision generation or rig retargeting.'}
    (BASE / 'inventory.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'prepared': sum(r['status'] != 'held' for r in records),
                      'held': sum(r['status'] == 'held' for r in records),
                      'source_files_hash_verified': len(files)}))


if __name__ == '__main__':
    main()
