"""Reconstruct registered SOCOM source clips; preserve native units and samples.

Run in a fresh background Blender process. Does not modify runtime resources.
Based on the project's reviewed external blender_pilot.py transform method.
"""
import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--all-seal', action='store_true',
                        help='Include every decoded seal_ catalog clip, not just runtime dependencies.')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert not (args.output / 'socom_source_actions.blend').exists(), 'Refusing overwrite'
    profile = read(args.project / 'config/operator_animation_map.json')
    gameplay = read(args.project / 'assets/animations/seal_gameplay/manifest.json')['states']
    firing = read(args.project / 'assets/animations/seal_firing_reference/manifest.json')['entries']
    reference = read(args.project / 'assets/animations/seal_reference/manifest.json')['clips']
    coverage = {x['name']: x['classification']['coverage'] for x in reference}
    coverage.update({name: entry['coverage'] for name, entry in firing.items()})
    rig = read(args.source / 'seal-skeleton.json')
    catalog = {x['name']: x for x in read(args.source / 'animation-catalog.json')}
    selected = {}

    def add(name, consumer):
        assert (args.source / 'motion' / (name + '.json')).exists(), name
        selected.setdefault(name, set()).add(consumer)

    def scan(value, route='profile', ancestors=()):
        if isinstance(value, dict):
            for k, v in value.items():
                scan(v, route + '/' + k, ancestors)
        elif isinstance(value, list):
            for v in value:
                scan(v, route, ancestors)
        elif isinstance(value, str) and value.startswith('res://assets/animations/seal_') and value.endswith('.tres'):
            path = args.project / value[6:]
            assert value not in ancestors, ('Cyclic source_asset dependency', value)
            text = path.read_text()
            source_assets = re.findall(r'metadata/source_asset = "(res://assets/animations/seal_[^"]+\.tres)"', text)
            for source_asset in source_assets:
                scan(source_asset, route + '/source_asset', ancestors + (value,))
            names = re.findall(r'(?:metadata/source_name|resource_name) = "(seal_[^"]+)"', text)
            for name in names:
                if (args.source / 'motion' / (name + '.json')).exists():
                    add(name, route)
            for key, entry in gameplay.items():
                if entry.get('path') == value:
                    add(entry['source'], route)
            for key, entry in firing.items():
                if value in (entry.get('path'), entry.get('composed_path')):
                    add(key, route)
                    if entry.get('base'):
                        add(entry['base'], route + '/composition_base')
            assert names or source_assets or any(e.get('path') == value for e in gameplay.values()), value

    scan(profile)
    if args.all_seal:
        for name in sorted(catalog):
            if name.startswith('seal_'):
                add(name, 'offline/full_seal_catalog')
    assert selected
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    scene = bpy.context.scene
    scene.render.fps = 30
    data = bpy.data.armatures.new('Original_SEAL_Hierarchy')
    arm = bpy.data.objects.new('SOCOM_Source_Actions', data)
    scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    arm.rotation_euler.x = math.pi / 2
    arm.show_in_front = True
    data.display_type = 'STICK'
    nodes = {n['name']: n for n in rig['nodes']}
    local, rest = {}, {}
    bpy.ops.object.mode_set(mode='EDIT')
    for n in rig['nodes']:
        name = n['name']
        vals = n['matrix_column_major']
        local[name] = Matrix([vals[i:i+4] for i in range(0, 16, 4)]).transposed()
        rest[name] = rest[n['parent']] @ local[name] if n['parent'] else local[name]
        bone = data.edit_bones.new(name)
        bone.matrix = rest[name]
        bone.length = 0.7
        if n['parent']:
            bone.parent = data.edit_bones[n['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    blender_local = {name: (data.bones[n['parent']].matrix_local.inverted() @ data.bones[name].matrix_local
                           if n['parent'] else data.bones[name].matrix_local.copy()) for name, n in nodes.items()}
    arm.animation_data_create()
    results = []
    args.output.mkdir(parents=True, exist_ok=True)
    for name in sorted(selected):
        path = args.source / 'motion' / (name + '.json')
        clip = read(path)
        tracks = {t['name']: t for t in clip['tracks']}
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        action['source_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        action['duration_seconds'] = clip['duration']
        action['source_frames'] = clip['frames']
        action['consumers'] = json.dumps(sorted(selected[name]))
        action['source_settings'] = json.dumps(catalog.get(name, {}).get('settings', []))
        missing = sorted(set(tracks) - set(nodes))
        # Retain unattached channels verbatim, without inventing a weapon parent.
        action['unattached_tracks_json'] = json.dumps([tracks[k] for k in missing])
        action['source_coverage'] = coverage.get(name, 'unknown')
        action['partial_source'] = action['source_coverage'] != 'full'
        previous = {}

        def transform(bone, sample):
            if bone not in tracks:
                return local[bone]
            t = tracks[bone]
            p = t['positions_raw'][0 if len(t['positions_raw']) == 1 else sample]
            q = t['rotations_raw'][0 if len(t['rotations_raw']) == 1 else sample]
            return Matrix.Translation(Vector(p) / 256) @ Quaternion((q[3], q[0], q[1], q[2])).normalized().to_matrix().to_4x4()

        # Fractional key times preserve each source duration, not an assumed 30 Hz duration.
        times = [1 + f * clip['duration'] * 30 / clip['frames'] for f in range(clip['samples'])]
        for f, time in enumerate(times):
            for bone in nodes:
                pb = arm.pose.bones[bone]
                pb.rotation_mode = 'QUATERNION'
                basis = blender_local[bone].inverted() @ transform(bone, f)
                loc, q, scale = basis.decompose()
                if bone in previous and q.dot(previous[bone]) < 0:
                    q.negate()
                previous[bone] = q.copy()
                pb.location, pb.rotation_quaternion, pb.scale = loc, q, scale
                for prop in ('location', 'rotation_quaternion', 'scale'):
                    pb.keyframe_insert(data_path=prop, frame=time, group=bone)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        max_error = 0.0
        for f, time in enumerate(times):
            scene.frame_set(int(time), subframe=time - int(time))
            expected = {}
            for bone, n in nodes.items():
                expected[bone] = expected[n['parent']] @ transform(bone, f) if n['parent'] else transform(bone, f)
                actual = arm.pose.bones[bone].matrix
                max_error = max(max_error, max(abs(actual[i][j] - expected[bone][i][j]) for i in range(4) for j in range(4)))
        assert max_error < 0.0002, (name, max_error)
        results.append({'name': name, 'samples': clip['samples'], 'duration': clip['duration'],
                        'max_matrix_error': max_error, 'unattached_tracks': missing,
                        'source_sha256': action['source_sha256'], 'consumers': sorted(selected[name])})
        print('SOURCE_ACTION_PASS', name, max_error, flush=True)
    arm['units'] = rig['units']
    arm['scope'] = 'Source samples, not retargeted gameplay; unknown weapon parents are not guessed.'
    arm.animation_data.action = bpy.data.actions.get('seal_stand') or bpy.data.actions[0]
    scene.frame_start = 1
    scene.frame_end = 1 + arm.animation_data.action['source_frames']
    scene.frame_set(1)
    readme = bpy.data.texts.new('README')
    readme.write('Select the armature and use Dope Sheet > Action Editor to choose a source action.\n'
                 'Native units, original hierarchy, root travel and source key timing are preserved.\n'
                 'Missing body channels use rest pose for inspection; partial clips are not invented full-body motions.\n'
                 'Unattached weapon/helper channels are retained in each Action custom property as raw JSON.\n'
                 'Exactness is checked at decoded sample times only, not original-engine interpolation, mesh or runtime IK.\n')
    report = {'scope': ('Full decoded seal_ catalog plus saved runtime dependencies' if args.all_seal else
                        'All SOCOM source dependencies found in the saved animation map, including registered fallbacks'),
              'count': len(results), 'samples': sum(x['samples'] for x in results), 'clips': results,
              'limits': ['No original-engine interpolation proof', 'No recovered weapon/helper parent',
                         'Bone-only source rig, not a character mesh', 'No runtime mappings changed']}
    (args.output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'socom_source_actions.blend'))
    print('SOURCE_LIBRARY_PASS', len(results), flush=True)


if __name__ == '__main__':
    main()
