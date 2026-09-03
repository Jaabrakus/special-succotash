#!/usr/bin/env python3
"""Read-only audit of native AGLS rifle aim-sweep animation data."""

from __future__ import annotations

import json

import unreal


ASSETS = {
    "standing": (
        "/Game/AdvancedLocomotionV4/CharacterAssets/MannequinSkeleton/"
        "AnimationExamples/Overlay/Rifles/ALS_Props_Rifle_Aim_Sweep."
        "ALS_Props_Rifle_Aim_Sweep"
    ),
    "crouched": (
        "/Game/AdvancedLocomotionV4/CharacterAssets/MannequinSkeleton/"
        "AnimationExamples/Overlay/Rifles/ALS_Props_Rifle_Aim_Sweep_Crouched."
        "ALS_Props_Rifle_Aim_Sweep_Crouched"
    ),
    "prone": (
        "/Game/AdvancedLocomotionV4/CharacterAssets/MannequinSkeleton/"
        "AnimationExamples/Overlay/Rifles/ALS_Crawl_Props_Rifle_Aim_Sweep."
        "ALS_Crawl_Props_Rifle_Aim_Sweep"
    ),
}


def transform_dict(value: object) -> dict[str, object]:
    location = value.translation
    rotation = value.rotation.rotator()
    return {
        "location_cm": {
            "x": float(location.x),
            "y": float(location.y),
            "z": float(location.z),
        },
        "rotation_degrees": {
            "pitch": float(rotation.pitch),
            "yaw": float(rotation.yaw),
            "roll": float(rotation.roll),
        },
    }


def safe_call(callable_value, *args):
    try:
        return callable_value(*args)
    except Exception as error:
        return {"error": str(error)}


def safe_method(owner: object, name: str, *args):
    method = getattr(owner, name, None)
    if method is None:
        return {"error": f"missing method {name}"}
    return safe_call(method, *args)


def integer_or_default(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def audit_asset(label: str, path: str) -> dict[str, object]:
    asset = unreal.EditorAssetLibrary.load_asset(path)
    if asset is None:
        return {"label": label, "path": path, "error": "asset not found"}
    data_model = safe_method(asset, "get_data_model")
    sampled_keys = (
        safe_method(data_model, "get_number_of_keys")
        if not isinstance(data_model, dict)
        else 0
    )
    sampled_frames = (
        safe_method(data_model, "get_number_of_frames")
        if not isinstance(data_model, dict)
        else 0
    )
    report: dict[str, object] = {
        "label": label,
        "path": path,
        "class": asset.get_class().get_name(),
        "play_length_seconds": float(asset.get_play_length()),
        "sampled_keys": integer_or_default(sampled_keys),
        "sampled_frames": integer_or_default(sampled_frames),
    }
    track_names = safe_method(
        unreal.AnimationLibrary, "get_animation_track_names", asset
    )
    report["track_names"] = (
        [str(name) for name in track_names]
        if not isinstance(track_names, dict)
        else track_names
    )
    curve_names = safe_method(
        unreal.AnimationLibrary,
        "get_animation_curve_names",
        asset,
        unreal.RawCurveTrackTypes.RCT_FLOAT,
    )
    if isinstance(curve_names, dict):
        report["curve_error"] = curve_names
        curve_names = []
    report["float_curves"] = [str(name) for name in curve_names]
    curve_samples = {}
    for curve_name in curve_names:
        values = safe_method(
            unreal.AnimationLibrary, "get_float_keys", asset, curve_name
        )
        curve_samples[str(curve_name)] = str(values)
    report["curve_samples"] = curve_samples
    bone_samples = {}
    frame_count = max(
        int(report["sampled_frames"]),
        int(round(float(report["play_length_seconds"]) * 30.0)) + 1,
        1,
    )
    for bone_name in ["spine_03", "hand_r", "hand_l", "ik_hand_gun"]:
        samples = []
        for frame in sorted({0, frame_count // 2, max(frame_count - 1, 0)}):
            value = safe_method(
                unreal.AnimationLibrary,
                "get_bone_pose_for_frame",
                asset,
                bone_name,
                frame,
                False,
            )
            samples.append(
                {"frame": frame, "transform": transform_dict(value)}
                if not isinstance(value, dict)
                else {"frame": frame, **value}
            )
        bone_samples[bone_name] = samples
    report["bone_samples"] = bone_samples
    return report


def main() -> None:
    report = [audit_asset(label, path) for label, path in ASSETS.items()]
    unreal.log(f"AGLS_RIFLE_AIM_SWEEP_REPORT {json.dumps(report, sort_keys=True)}")


if __name__ == "__main__":
    main()
