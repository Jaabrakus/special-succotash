"""Export the local Mixamo Beta character as a visual-only Godot skin.

The skin retains its native bind skeleton. Godot mirrors final poses from the
authoritative SOCOM animation rig at runtime, so neither skeleton needs a
destructive rest-pose conversion.
"""

import bpy
import json
import os
import sys


BODY_COLOR = (0.18, 0.23, 0.15, 1.0)
JOINT_COLOR = (0.045, 0.055, 0.045, 1.0)


def args_after_separator():
    if "--" not in sys.argv:
        raise RuntimeError("Expected skin FBX and GLB output after --")
    args = sys.argv[sys.argv.index("--") + 1:]
    if len(args) != 2:
        raise RuntimeError("Expected exactly 2 arguments: skin-fbx glb-output")
    return tuple(os.path.abspath(path) for path in args)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes, bpy.data.materials):
        for block in list(collection):
            collection.remove(block)


def set_material_color(material, color):
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = 0.82
        principled.inputs["Metallic"].default_value = 0.0


def main():
    source_path, output_path = args_after_separator()
    clear_scene()
    bpy.ops.import_scene.fbx(
        filepath=source_path,
        use_anim=True,
        ignore_leaf_bones=False,
        automatic_bone_orientation=False,
    )
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(armatures) != 1 or not meshes:
        raise RuntimeError(
            f"Expected one armature and at least one mesh, found "
            f"{len(armatures)} armatures and {len(meshes)} meshes"
        )
    armature = armatures[0]
    if len(armature.data.bones) != 65:
        raise RuntimeError(f"Expected 65 Mixamo bones, found {len(armature.data.bones)}")
    armature.name = "MixamoBetaArmature"
    armature.data.name = "MixamoBetaSkeleton"
    armature.animation_data_clear()
    armature.data.pose_position = "REST"

    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for mesh in meshes:
        suffix = "Joints" if "joint" in mesh.name.lower() else "Surface"
        mesh.name = "MixamoBeta" + suffix
        mesh.data.name = mesh.name + "Mesh"
        for slot in mesh.material_slots:
            if slot.material is not None:
                set_material_color(slot.material, JOINT_COLOR if suffix == "Joints" else BODY_COLOR)
        mesh["visual_only"] = True

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_def_bones=True,
        export_lights=False,
        export_cameras=False,
        export_extras=True,
    )
    print("MIXAMO_SKIN_EXPORT_COMPLETE " + json.dumps({
        "source": source_path,
        "output": output_path,
        "bones": len(armature.data.bones),
        "meshes": [mesh.name for mesh in meshes],
    }))


main()
