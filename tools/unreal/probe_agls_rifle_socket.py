#!/usr/bin/env python3
"""Print the native AGLS rifle attachment sockets without modifying assets."""

from __future__ import annotations

import json

import unreal


CHARACTER_SKELETON = (
    "/Game/AdvancedLocomotionV4/CharacterAssets/MannequinSkeleton/"
    "ALS_Mannequin_Skeleton.ALS_Mannequin_Skeleton"
)
M4_MESH = "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/M4A1.M4A1"
CHARACTER_MESH = (
    "/Game/AdvancedLocomotionV4/CharacterAssets/MannequinSkeleton/Meshes/"
    "Mannequin.Mannequin"
)


def property_if_present(obj: object, name: str, default: object = None) -> object:
    try:
        return obj.get_editor_property(name)
    except Exception:
        return default


def vector_dict(value: object) -> dict[str, float] | None:
    if value is None:
        return None
    return {
        "x": float(property_if_present(value, "x", 0.0)),
        "y": float(property_if_present(value, "y", 0.0)),
        "z": float(property_if_present(value, "z", 0.0)),
    }


def rotator_dict(value: object) -> dict[str, float] | None:
    if value is None:
        return None
    return {
        "pitch": float(property_if_present(value, "pitch", 0.0)),
        "yaw": float(property_if_present(value, "yaw", 0.0)),
        "roll": float(property_if_present(value, "roll", 0.0)),
    }


def transform_dict(value: object) -> dict[str, object] | None:
    if value is None:
        return None
    return {
        "location_cm": vector_dict(value.translation),
        "rotation_degrees": rotator_dict(value.rotation.rotator()),
        "scale": vector_dict(value.scale3d),
    }


def socket_dict(socket: object, owner: str) -> dict[str, object]:
    return {
        "owner": owner,
        "name": str(property_if_present(socket, "socket_name", "")),
        "bone": str(property_if_present(socket, "bone_name", "")),
        "relative_location_cm": vector_dict(
            property_if_present(socket, "relative_location")
        ),
        "relative_rotation_degrees": rotator_dict(
            property_if_present(socket, "relative_rotation")
        ),
        "relative_scale": vector_dict(property_if_present(socket, "relative_scale")),
    }


def main() -> None:
    skeleton = unreal.EditorAssetLibrary.load_asset(CHARACTER_SKELETON)
    character_mesh = unreal.EditorAssetLibrary.load_asset(CHARACTER_MESH)
    m4_mesh = unreal.EditorAssetLibrary.load_asset(M4_MESH)
    if skeleton is None:
        raise RuntimeError(f"missing AGLS character skeleton: {CHARACTER_SKELETON}")
    if m4_mesh is None:
        raise RuntimeError(f"missing AGLS M4 mesh: {M4_MESH}")

    sockets = [
        socket_dict(socket, "character_skeleton")
        for socket in property_if_present(skeleton, "sockets", []) or []
    ]
    if character_mesh:
        sockets.extend(
            socket_dict(socket, "character_skeletal_mesh")
            for socket in property_if_present(
                character_mesh, "mesh_only_socket_list", []
            )
            or []
        )
    sockets.extend(
        socket_dict(socket, "m4_skeletal_mesh")
        for socket in property_if_present(m4_mesh, "mesh_only_socket_list", []) or []
    )
    m4_skeleton = property_if_present(m4_mesh, "skeleton")
    if m4_skeleton:
        sockets.extend(
            socket_dict(socket, "m4_skeleton")
            for socket in property_if_present(m4_skeleton, "sockets", []) or []
        )

    component = unreal.new_object(unreal.SkeletalMeshComponent)
    component.set_skeletal_mesh_asset(character_mesh)
    component_space = unreal.RelativeTransformSpace.RTS_COMPONENT
    named_attachment_points = {}
    for name in ["hand_RifleSocket", "hand_r", "ik_hand_gun"]:
        named_attachment_points[name] = {
            "exists": bool(component.does_socket_exist(name)),
            "parent_bone": str(component.get_socket_bone_name(name)),
            "component_transform": transform_dict(
                component.get_socket_transform(name, component_space)
            ),
        }

    report = {
        "character_skeleton": CHARACTER_SKELETON,
        "character_mesh": CHARACTER_MESH,
        "m4_mesh": M4_MESH,
        "m4_skeleton": m4_skeleton.get_path_name() if m4_skeleton else None,
        "named_attachment_points": named_attachment_points,
        "sockets": sockets,
    }
    unreal.log(f"AGLS_RIFLE_SOCKET_REPORT {json.dumps(report, sort_keys=True)}")


if __name__ == "__main__":
    main()
