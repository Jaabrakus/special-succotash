#!/usr/bin/env python3
"""Build the first native-weight Operator Rig V2 locomotion proof.

The proof keeps the tactical suit's authored vertex groups and clean native
deformation rig. It retargets one deliberately difficult diagonal sprint in
Blender, normalizes only the cycle's global floor offset, audits joint spacing
and elbow bends, then exports one isolated GLB for Godot review.

It does not modify the live player, movement, camera, or weapon contracts.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import retarget_military_tactical_suit_actions as retarget


ACTION_NAME = "SprintForwardLeft"
EXPECTED_DEFORM_BONES = 69
EXPECTED_MESHES = 14
MIN_AUTHORED_GROUPS = 69
MIN_KNEE_PLANAR_SEPARATION_M = 0.10
MIN_ANKLE_PLANAR_SEPARATION_M = 0.08
MIN_ELBOW_ANGLE_DEG = 45.0
MAX_ELBOW_ANGLE_DEG = 145.0
FLOOR_CLEARANCE_M = 0.02
MAX_CHARACTER_DIMENSION_M = 2.75

LEFT = {
    "arm": "mixamorig:LeftArm_033",
    "elbow": "mixamorig:LeftForeArm_034",
    "wrist": "mixamorig:LeftHand_035",
    "knee": "mixamorig:LeftLeg_064",
    "ankle": "mixamorig:LeftFoot_065",
    "toe": "mixamorig:LeftToeBase_066",
}
RIGHT = {
    "arm": "mixamorig:RightArm_09",
    "elbow": "mixamorig:RightForeArm_010",
    "wrist": "mixamorig:RightHand_011",
    "knee": "mixamorig:RightLeg_058",
    "ankle": "mixamorig:RightFoot_059",
    "toe": "mixamorig:RightToeBase_060",
}


def _arguments() -> tuple[Path, Path, Path, Path, Path]:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(args) != 5:
        raise RuntimeError(
            "Expected BASE.blend SPRINT_FORWARD_LEFT.fbx OUTPUT.blend "
            "OUTPUT.glb REPORT.json"
        )
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def _meshes(target: bpy.types.Object) -> list[bpy.types.Object]:
    return sorted(
        [
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH"
            and obj.parent == target
            and any(
                modifier.type == "ARMATURE" and modifier.object == target
                for modifier in obj.modifiers
            )
        ],
        key=lambda obj: obj.name,
    )


def _mesh_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = [
        evaluated.matrix_world @ vertex.co
        for mesh in meshes
        for evaluated in [mesh.evaluated_get(depsgraph)]
        for vertex in evaluated.data.vertices
    ]
    if not points:
        raise RuntimeError("Operator Rig V2 has no evaluated mesh vertices")
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def _world_head(target: bpy.types.Object, name: str) -> Vector:
    return target.matrix_world @ target.pose.bones[name].head


def _planar_distance(left: Vector, right: Vector) -> float:
    return Vector((left.x - right.x, left.y - right.y)).length


def _elbow_angle(target: bpy.types.Object, side: dict[str, str]) -> float:
    arm = _world_head(target, side["arm"])
    elbow = _world_head(target, side["elbow"])
    wrist = _world_head(target, side["wrist"])
    return math.degrees((arm - elbow).angle(wrist - elbow))


def _global_floor_offset(
    target: bpy.types.Object,
    meshes: list[bpy.types.Object],
    frame_start: int,
    frame_end: int,
) -> tuple[float, float]:
    minimum_z = math.inf
    for frame in range(frame_start, frame_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        minimum_z = min(minimum_z, _mesh_bounds(meshes)[0].z)
    offset = FLOOR_CLEARANCE_M - minimum_z
    hips = target.pose.bones["mixamorig:Hips_01"]
    for frame in range(frame_start, frame_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        hips.location.z += offset
        hips.keyframe_insert(
            data_path="location",
            index=2,
            frame=frame,
            group=hips.name,
        )
    bpy.context.view_layer.update()
    return minimum_z, offset


def _audit(
    target: bpy.types.Object,
    meshes: list[bpy.types.Object],
    action: bpy.types.Action,
) -> dict[str, object]:
    frame_start = int(action["source_frame_start"])
    frame_end = int(action["source_frame_end"])
    samples: list[dict[str, float | int | list[float]]] = []
    minimum_knee_separation = math.inf
    minimum_ankle_separation = math.inf
    minimum_floor = math.inf
    maximum_dimension = 0.0
    left_elbow_angles: list[float] = []
    right_elbow_angles: list[float] = []
    for frame in range(frame_start, frame_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        left_knee = _world_head(target, LEFT["knee"])
        right_knee = _world_head(target, RIGHT["knee"])
        left_ankle = _world_head(target, LEFT["ankle"])
        right_ankle = _world_head(target, RIGHT["ankle"])
        knee_separation = _planar_distance(left_knee, right_knee)
        ankle_separation = _planar_distance(left_ankle, right_ankle)
        left_elbow = _elbow_angle(target, LEFT)
        right_elbow = _elbow_angle(target, RIGHT)
        minimum, maximum = _mesh_bounds(meshes)
        dimensions = maximum - minimum
        minimum_knee_separation = min(minimum_knee_separation, knee_separation)
        minimum_ankle_separation = min(minimum_ankle_separation, ankle_separation)
        minimum_floor = min(minimum_floor, minimum.z)
        maximum_dimension = max(maximum_dimension, max(dimensions))
        left_elbow_angles.append(left_elbow)
        right_elbow_angles.append(right_elbow)
        samples.append(
            {
                "frame": frame,
                "knee_planar_separation_m": round(knee_separation, 6),
                "ankle_planar_separation_m": round(ankle_separation, 6),
                "left_elbow_angle_deg": round(left_elbow, 4),
                "right_elbow_angle_deg": round(right_elbow, 4),
                "floor_minimum_m": round(minimum.z, 6),
                "bounds_m": [round(value, 6) for value in dimensions],
            }
        )

    failures: list[str] = []
    if minimum_knee_separation < MIN_KNEE_PLANAR_SEPARATION_M:
        failures.append(
            f"knees cross: {minimum_knee_separation:.4f} m < "
            f"{MIN_KNEE_PLANAR_SEPARATION_M:.4f} m"
        )
    if minimum_ankle_separation < MIN_ANKLE_PLANAR_SEPARATION_M:
        failures.append(
            f"ankles cross: {minimum_ankle_separation:.4f} m < "
            f"{MIN_ANKLE_PLANAR_SEPARATION_M:.4f} m"
        )
    for label, values in (
        ("left", left_elbow_angles),
        ("right", right_elbow_angles),
    ):
        if min(values) < MIN_ELBOW_ANGLE_DEG or max(values) > MAX_ELBOW_ANGLE_DEG:
            failures.append(
                f"{label} elbow leaves range: {min(values):.2f}-"
                f"{max(values):.2f} degrees"
            )
    if minimum_floor < FLOOR_CLEARANCE_M - 0.002:
        failures.append(
            f"mesh penetrates proof floor: {minimum_floor:.4f} m"
        )
    if maximum_dimension > MAX_CHARACTER_DIMENSION_M:
        failures.append(
            f"mesh exceeds human bound: {maximum_dimension:.4f} m"
        )

    return {
        "frame_start": frame_start,
        "frame_end": frame_end,
        "minimum_knee_planar_separation_m": round(minimum_knee_separation, 6),
        "minimum_ankle_planar_separation_m": round(minimum_ankle_separation, 6),
        "left_elbow_angle_range_deg": [
            round(min(left_elbow_angles), 4),
            round(max(left_elbow_angles), 4),
        ],
        "right_elbow_angle_range_deg": [
            round(min(right_elbow_angles), 4),
            round(max(right_elbow_angles), 4),
        ],
        "minimum_floor_m": round(minimum_floor, 6),
        "maximum_character_dimension_m": round(maximum_dimension, 6),
        "samples": samples,
        "failures": failures,
    }


def _export(
    target: bpy.types.Object,
    meshes: list[bpy.types.Object],
    output: Path,
) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = target
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_anim_single_armature=True,
        export_skins=True,
        export_morph=False,
        export_morph_animation=False,
        export_materials="EXPORT",
        export_yup=True,
    )


def main() -> None:
    base, source_path, output_blend, output_glb, report_path = _arguments()
    bpy.ops.wm.open_mainfile(filepath=str(base))
    target = bpy.data.objects.get(retarget.TARGET_ARMATURE)
    if target is None or target.type != "ARMATURE":
        raise RuntimeError(f"Missing native target rig: {retarget.TARGET_ARMATURE}")
    if len(target.data.bones) != EXPECTED_DEFORM_BONES:
        raise RuntimeError(
            f"Native target has {len(target.data.bones)} bones; "
            f"expected {EXPECTED_DEFORM_BONES}"
        )
    meshes = _meshes(target)
    if len(meshes) != EXPECTED_MESHES:
        raise RuntimeError(f"Found {len(meshes)} suit meshes; expected {EXPECTED_MESHES}")
    weak_group_meshes = [
        mesh.name for mesh in meshes if len(mesh.vertex_groups) < MIN_AUTHORED_GROUPS
    ]
    if weak_group_meshes:
        raise RuntimeError(f"Authored weight groups were lost: {weak_group_meshes}")
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)

    source, imported = retarget._import_source(source_path)
    source_action = source.animation_data.action
    action = retarget._bake_action(target, source, ACTION_NAME)
    action["source_fbx"] = str(source_path)
    retarget._remove_imported(imported)
    if source_action is not None and source_action.name in bpy.data.actions:
        bpy.data.actions.remove(source_action, do_unlink=True)
    target.animation_data.action = action
    frame_start = int(action["source_frame_start"])
    frame_end = int(action["source_frame_end"])
    floor_before, floor_offset = _global_floor_offset(
        target,
        meshes,
        frame_start,
        frame_end,
    )
    audit = _audit(target, meshes, action)
    report = {
        "schema_version": 1,
        "status": "pass" if not audit["failures"] else "fail",
        "pipeline": "native_authored_weights_blender_baked",
        "action": ACTION_NAME,
        "source_fbx": str(source_path),
        "reference_rig": "counter-strike-urban/source/Counter Strike Urban.fbx",
        "reference_features": [
            "elbow helpers",
            "bicep twist helpers",
            "wrist helpers",
            "knee helpers",
            "ankle helpers",
            "toe joints",
        ],
        "target_armature": target.name,
        "target_bones": len(target.data.bones),
        "mesh_count": len(meshes),
        "minimum_vertex_groups_per_mesh": min(
            len(mesh.vertex_groups) for mesh in meshes
        ),
        "mapped_animation_bones": int(action["mapped_bones"]),
        "floor_before_m": round(floor_before, 6),
        "global_floor_offset_m": round(floor_offset, 6),
        "audit": audit,
        "output_blend": str(output_blend),
        "output_glb": str(output_glb),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if audit["failures"]:
        raise RuntimeError("Operator Rig V2 audit failed: " + "; ".join(audit["failures"]))

    bpy.context.scene.frame_start = frame_start
    bpy.context.scene.frame_end = frame_end
    bpy.context.scene.frame_set((frame_start + frame_end) // 2)
    bpy.context.scene["operator_rig_v2_status"] = "diagonal_sprint_proof_pass"
    bpy.context.scene["operator_rig_v2_pipeline"] = (
        "native authored skin weights; Blender-baked retarget"
    )
    output_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_blend))
    _export(target, meshes, output_glb)
    print(
        "OPERATOR_RIG_V2_PROOF_PASS "
        f"bones={len(target.data.bones)} meshes={len(meshes)} "
        f"mapped={int(action['mapped_bones'])} "
        f"knee_min={audit['minimum_knee_planar_separation_m']:.4f}m "
        f"ankle_min={audit['minimum_ankle_planar_separation_m']:.4f}m "
        f"floor={audit['minimum_floor_m']:.4f}m output={output_glb}"
    )


if __name__ == "__main__":
    main()
