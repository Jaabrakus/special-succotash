import os
import unreal


OUTPUT_ROOT = "/Users/kiwimango/Documents/SOCOM-141/assets/external/agls_intake/imported/weapons"

WEAPONS = {
    "m4a1": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/M4A1.M4A1",
    "ak47": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/AK-47.AK-47",
    "c8": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/C8.C8",
    "famas": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/Famas.Famas",
    "as50": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/Accuracy-International-as-50.Accuracy-International-as-50",
    "perun_x16": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/perun-x16.perun-x16",
    "beowulf_50": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/aa-50-beowulf.aa-50-beowulf",
    "mossberg_590": "/Game/AdvancedLocomotionV4/Props/Meshes/Rifle/Mossberg-590.Mossberg-590",
    "m9": "/Game/AdvancedLocomotionV4/Props/Meshes/M9.M9",
    "p018": "/Game/AdvancedLocomotionV4/Props/Meshes/Pistol/p-018.p-018",
    "desert_eagle": "/Game/AdvancedLocomotionV4/Props/Meshes/Pistol/Desert_Eagle.Desert_Eagle",
    "sw39": "/Game/AdvancedLocomotionV4/Props/Meshes/Pistol/SW_39.SW_39",
}


def export_weapon(weapon_id, asset_path):
    asset = unreal.load_asset(asset_path)
    if asset is None:
        unreal.log_error("AGLS_WEAPON_EXPORT missing {} {}".format(weapon_id, asset_path))
        return False
    weapon_dir = os.path.join(OUTPUT_ROOT, weapon_id)
    os.makedirs(weapon_dir, exist_ok=True)
    task = unreal.AssetExportTask()
    task.object = asset
    task.filename = os.path.join(weapon_dir, weapon_id + ".fbx")
    task.automated = True
    task.prompt = False
    task.replace_identical = True
    task.write_empty_files = False
    options = unreal.FbxExportOption()
    options.ascii = False
    options.collision = False
    options.export_morph_targets = False
    options.export_preview_mesh = False
    task.options = options
    exported = unreal.Exporter.run_asset_export_task(task)
    unreal.log(
        "AGLS_WEAPON_EXPORT {} {} {}".format(
            "PASS" if exported else "FAIL", weapon_id, task.filename
        )
    )
    return bool(exported)


def main():
    os.makedirs(OUTPUT_ROOT, exist_ok=True)
    exported = 0
    for weapon_id, asset_path in WEAPONS.items():
        if export_weapon(weapon_id, asset_path):
            exported += 1
    unreal.log("AGLS_WEAPON_EXPORT_SUMMARY {}/{}".format(exported, len(WEAPONS)))
    if exported != len(WEAPONS):
        raise RuntimeError("One or more AGLS weapon meshes did not export")


main()
