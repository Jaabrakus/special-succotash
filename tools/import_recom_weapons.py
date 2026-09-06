#!/usr/bin/env python3
"""
Imports and normalizes authentic SOCOM weapon and ammo data from reCOM (zweapon.rdr).
Outputs:
1. config/weapons/recom_weapons_catalog.json (Complete reference catalog of all 60 SOCOM weapons & gear)
2. Enriches existing config/weapons/*.json files with authentic SOCOM ballistics, bloom, RPM, and fire modes
   without modifying existing 3D models or authored socket coordinates.
"""

import os
import re
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ZWEAPON_RDR_PATH = os.path.join(PROJECT_ROOT, "reCOM-main", "data", "s1", "common", "zrdr", "zweapon.rdr")
WEAPONS_CONFIG_DIR = os.path.join(PROJECT_ROOT, "config", "weapons")
CATALOG_OUTPUT_PATH = os.path.join(WEAPONS_CONFIG_DIR, "recom_weapons_catalog.json")


def parse_field(pattern, text, default=""):
    match = re.search(pattern, text, re.DOTALL)
    if match:
        val = match.group(1).strip()
        if val.startswith('"') and val.endswith('"'):
            val = val[1:-1]
        return val
    return default


def balanced_block(text, name):
    """Return a complete nested RDR block, respecting quoted parentheses."""
    match = re.search(r'\b' + re.escape(name) + r'\s*\(', text)
    if not match:
        return ""
    start = match.end()
    depth, quoted, escaped = 1, False, False
    for index in range(start, len(text)):
        char = text[index]
        if escaped:
            escaped = False
            continue
        if quoted and char == "\\":
            escaped = True
            continue
        if char == '"':
            quoted = not quoted
        elif not quoted:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return text[start:index]
    raise ValueError("Unclosed RDR block: " + name)


def parse_float(pattern, text, default=0.0):
    val = parse_field(pattern, text, "")
    if not val:
        return default
    val = val.strip()
    if val.startswith('.'):
        val = '0' + val
    parts = val.split('.')
    if len(parts) > 2:
        val = parts[0] + '.' + parts[1]
    try:
        return float(val)
    except ValueError:
        return default


def parse_int(pattern, text, default=0):
    val = parse_field(pattern, text, "")
    if not val:
        return default
    try:
        return int(float(val))
    except (ValueError, TypeError):
        return default


def parse_ammo():
    with open(ZWEAPON_RDR_PATH, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    parts = content.split("ZWEAPON ((")
    ammo_part = parts[0]

    ammo_blocks = re.findall(r'Name\s*\(\s*(.*?)\s*\)(.*?)(?=Name\s*\(|\Z)', ammo_part, re.DOTALL)
    ammo_dict = {}

    for name_raw, body in ammo_blocks:
        clean_name = name_raw.strip().strip('"')
        ammo_dict[clean_name] = {
            "name": clean_name,
            "id": parse_int(r'ID\s*\(\s*(\d+)\s*\)', body, 0),
            "impact_damage": parse_float(r'ImpactDamage\s*\(\s*([\d\.]+)\s*\)', body, 0.0),
            "stun": parse_float(r'Stun\s*\(\s*([\d\.]+)\s*\)', body, 1.0),
            "piercing": parse_float(r'Piercing\s*\(\s*([\d\.]+)\s*\)', body, 1.0),
            "explosion_damage": parse_float(r'Explosion_Damage\s*\(\s*([\d\.]+)\s*\)', body, 0.0),
            "explosion_radius": parse_float(r'Explosion_Radius\s*\(\s*([\d\.]+)\s*\)', body, 0.0)
        }

    return ammo_dict


def parse_weapons(ammo_dict):
    with open(ZWEAPON_RDR_PATH, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    parts = content.split("ZWEAPON ((")
    weapon_part = parts[1] if len(parts) > 1 else ""

    first_w = re.search(r'Name\s*\(\s*(.*?)\s*\)(.*?)(?=\n\s*\(\s*\n\s*Name|\Z)', weapon_part, re.DOTALL)
    w_blocks = re.findall(r'\n\s*\(\s*\n\s*Name\s*\(\s*(.*?)\s*\)(.*?)(?=\n\s*\(\s*\n\s*Name|\Z)', weapon_part, re.DOTALL)

    raw_items = []
    if first_w:
        raw_items.append((first_w.group(1), first_w.group(2)))
    raw_items.extend(w_blocks)

    weapons = []

    for name_raw, body in raw_items:
        name = name_raw.strip().strip('"')
        desc = parse_field(r'Description\s*\(\s*(.*?)\s*\)', body, name)
        
        # Fire modes
        max_fire_mode = parse_int(r'MaxFireMode\s*\(\s*(\d+)\s*\)', body, 1)
        fire_modes = []
        if "SingleMode" in body:
            fire_modes.append("semi")
        if "BurstMode" in body:
            fire_modes.append("burst")
        if "AutoMode" in body:
            fire_modes.append("auto")

        if not fire_modes:
            if max_fire_mode == 1:
                fire_modes = ["semi"]
            elif max_fire_mode == 2:
                fire_modes = ["semi", "burst"]
            elif max_fire_mode == 3:
                fire_modes = ["semi", "auto"]
            elif max_fire_mode >= 4:
                fire_modes = ["semi", "burst", "auto"]
            else:
                fire_modes = ["semi"]

        # reCOM's FIREMODE enum is safety=0, single=1, burst=2, auto=3.
        # Its M16 burst profile carries an accuracy burst maximum of three,
        # which is the authored three-round trigger group. Keep the field
        # explicit so future two-round weapons can use the same runtime gate.
        burst_size = 3
        if "burst" in fire_modes:
            burst_size = max(2, min(3, parse_int(
                r'AccBurstCnt_Max\s*\(\s*(\d+)\s*\)', body, 3
            )))

        fire_wait = parse_float(r'FireWait\s*\(\s*([\d\.]+)\s*\)', body, 0.1)
        rpm = round(60.0 / fire_wait) if fire_wait > 0 else 600

        muzzle_vel = parse_float(r'Muzzle_Velocity\s*\(\s*([\d\.]+)\s*\)', body, 715.0)
        ammo_cap = parse_int(r'Ammo_Capacity\s*\(\s*(\d+)\s*\)', body, 30)
        num_mags = parse_int(r'NumMags\s*\(\s*(\d+)\s*\)', body, 3)
        reserve_ammo = ammo_cap * num_mags
        if reserve_ammo == 0 and ammo_cap > 0:
            reserve_ammo = ammo_cap * 3

        effective_range = parse_float(r'Effective_Range\s*\(\s*([\d\.]+)\s*\)', body, 150.0)
        maximum_range = parse_float(r'Maximum_Range\s*\(\s*([\d\.]+)\s*\)', body, 400.0)

        # Stand stance modifiers
        stand_body = balanced_block(body, "STANCE_STAND") or body

        target_min = parse_float(r'TargetMin\s*\(\s*([\d\.]+)\s*\)', stand_body, 15.0)
        target_max = parse_float(r'TargetMax\s*\(\s*([\d\.]+)\s*\)', stand_body, 65.0)
        dilate_fire = parse_float(r'TargetDilateUponFire\s*\(\s*([\d\.]+)\s*\)', stand_body, 10.0)
        dilate_move = parse_float(r'TargetDilateUponMovement\s*\(\s*([\d\.]+)\s*\)', stand_body, 0.5)
        constrict = parse_float(r'TargetConstrict\s*\(\s*([\d\.]+)\s*\)', stand_body, 70.0)

        base_spread = max(0.15, min(2.5, target_min / 35.0))
        max_bloom = max(1.0, min(6.0, target_max / 25.0))
        bloom_per_shot = max(0.2, min(3.0, dilate_fire / 10.0))
        moving_spread = base_spread + (dilate_move * 1.2)
        bloom_recovery = max(8.0, min(30.0, constrict / 4.0))

        reticle_knock = parse_float(r'ReticuleKnock\s*\(\s*([\d\.]+)\s*\)', stand_body, 20.0)
        reticle_knock_return = parse_float(r'ReticuleKnockReturn\s*\(\s*([\d\.]+)\s*\)', stand_body, 40.0)
        reticle_knock_max = parse_float(r'ReticuleKnockMax\s*\(\s*([\d\.]+)\s*\)', stand_body, 60.0)

        # Linked Ammo
        ammo_type_name = parse_field(r'AMMO_TYPES\s*\(\(\s*NAME\s*\(\s*(.*?)\s*\)', body, "")
        ammo_info = ammo_dict.get(ammo_type_name, {})
        impact_dmg = ammo_info.get("impact_damage", 2.0)
        
        # Calibrate SOCOM impact damage to shooter HP (scale 1.4 - 3.5 -> 28 - 48 dmg)
        calibrated_damage = round(impact_dmg * 16.0)
        if calibrated_damage < 18:
            calibrated_damage = 25 if "SD" not in name else 22
        elif calibrated_damage > 120:
            calibrated_damage = 110 # .50 cal sniper

        # Category
        nl = name.lower()
        cat = "Assault Rifles"
        if any(p in nl for p in ["model 18", "mark 23", "f57", "de .50", "m9", "226", "pistol", "designator"]):
            cat = "Pistols"
        elif any(s in nl for s in ["hk5", "f90", "9mm sub", "submachine", "smg", "mp5", "p90", "uzi"]):
            cat = "Submachine Guns"
        elif any(a in nl for a in ["m16", "m4", "552", "ak-47", "aks-74", "m14", "g11", "ar-15", "assault"]):
            cat = "Assault Rifles"
        elif any(sh in nl for sh in ["870", "mk 3", "spas", "shotgun"]):
            cat = "Shotguns"
        elif any(m in nl for m in ["m60", "m63", "mark 46", "machine"]):
            cat = "Machine Guns"
        elif any(sn in nl for sn in ["m82", "m40", "m87", "sr-25", "sniper"]):
            cat = "Sniper Rifles"
        elif any(g in nl for g in ["m67", "he", "an-m8", "mark141", "satchel", "claymore", "c4", "m203", "grenade", "mpbomb", "mgl", "m79", "gl "]):
            cat = "Grenades & Explosives"
        elif any(eq in nl for eq in ["armor", "inserts", "load", "knife", "flashlight", "detonator", "binoculars", "restraints"]):
            cat = "Tactical Equipment"

        clean_id = re.sub(r'[^a-zA-Z0-9_-]', '_', name.lower()).strip('_')

        weapons.append({
            "weapon_id": clean_id,
            "display_name": name,
            "description": desc,
            "category": cat,
            "socom_original_id": parse_int(r'ID\s*\(\s*(\d+)\s*\)', body, 0),
            "encumbrance": parse_int(r'Encumbrance\s*\(\s*(\d+)\s*\)', body, 4),
            "fire_modes": fire_modes,
            "default_fire_mode": fire_modes[0],
            "burst_size": burst_size,
            "ballistics": {
                "fire_rate_rpm": rpm,
                "damage": calibrated_damage,
                "headshot_multiplier": 3.5,
                "muzzle_velocity_mps": muzzle_vel,
                "base_spread_deg": round(base_spread, 3),
                "moving_spread_deg": round(moving_spread, 3),
                "full_gait_spread_deg": round(moving_spread * 1.5, 3),
                "bloom_per_shot_deg": round(bloom_per_shot, 3),
                "max_recoil_bloom_deg": round(max_bloom, 3),
                "bloom_recovery_speed": round(bloom_recovery, 1),
                "magazine_capacity": ammo_cap,
                "reserve_ammo": reserve_ammo,
                "effective_range_m": effective_range,
                "max_range_m": maximum_range,
                "is_silenced": "sd" in nl or "silenced" in nl
            },
            "reticle": {
                "cadence_driven_return": False,
                "shot_kick_px": reticle_knock,
                "shot_kick_return": reticle_knock_return,
                "maximum_shot_kick_px": reticle_knock_max,
                "base_gap_px": round(base_spread * 12.0, 1),
                "max_gap_px": round(max_bloom * 16.0, 1),
                "response_speed": round(bloom_recovery * 1.5, 1)
            },
            "ammo_spec": {
                "type": ammo_type_name,
                "impact_damage": impact_dmg,
                "stun": ammo_info.get("stun", 1.0),
                "piercing": ammo_info.get("piercing", 1.0)
            },
            "recom_assets": {
                "model_name": parse_field(r'ModelName\s*\(\s*(.*?)\s*\)', body, ""),
                "icon_texture": parse_field(r'IconTextureName\s*\(\s*(.*?)\s*\)', body, ""),
                "reload_sound": parse_field(r'ReloadSound\s*\(\s*(.*?)\s*\)', body, "")
            }
        })

    return weapons


def main():
    print(f"Parsing reCOM weapons from: {ZWEAPON_RDR_PATH}")
    ammo_dict = parse_ammo()
    weapons = parse_weapons(ammo_dict)
    print(f"✓ Parsed {len(ammo_dict)} ammunition types and {len(weapons)} weapons & equipment items.")

    by_category = {}
    for w in weapons:
        cat = w["category"]
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(w)

    # 1. Output the complete standalone database
    os.makedirs(WEAPONS_CONFIG_DIR, exist_ok=True)
    catalog_doc = {
        "catalog_version": 1,
        "source": "reCOM zweapon.rdr (SOCOM US Navy SEALs)",
        "total_items": len(weapons),
        "categories": {cat: len(items) for cat, items in by_category.items()},
        "ammunition_types": ammo_dict,
        "weapons": weapons
    }

    with open(CATALOG_OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog_doc, f, indent=2)
    print(f"✓ Saved complete catalog to {CATALOG_OUTPUT_PATH}")

    # 2. In-Place Enrichment of existing config/weapons/*.json (Preserving 3D models & sockets)
    existing_files = [f for f in os.listdir(WEAPONS_CONFIG_DIR) if f.endswith(".json") and f not in ["operator_loadout.json", "recom_weapons_catalog.json"]]

    for fname in existing_files:
        fpath = os.path.join(WEAPONS_CONFIG_DIR, fname)
        with open(fpath, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except Exception as e:
                print(f"Skipping {fname}: {e}")
                continue

        w_id = data.get("weapon_id", fname.replace(".json", "")).lower()
        d_name = data.get("display_name", "").lower()

        # Find best matching weapon in parsed weapons
        match = None
        for item in weapons:
            i_id = item["weapon_id"].lower()
            i_name = item["display_name"].lower()
            if i_id == w_id or i_name == d_name or (w_id in i_id and len(w_id) > 2):
                match = item
                break

        # Fallback category match
        if not match:
            for item in weapons:
                if fname.startswith("assaultrifle") and item["category"] == "Assault Rifles":
                    match = item
                    break
                elif fname.startswith("submachinegun") and item["category"] == "Submachine Guns":
                    match = item
                    break
                elif fname.startswith("shotgun") and item["category"] == "Shotguns":
                    match = item
                    break
                elif fname.startswith("sniperrifle") and item["category"] == "Sniper Rifles":
                    match = item
                    break

        if match:
            # Preserve authored 3D sockets, model path, and hand poses!
            if "ballistics" not in data:
                data["ballistics"] = {}
            for k, v in match["ballistics"].items():
                data["ballistics"][k] = v

            if "reticle" not in data:
                data["reticle"] = {}
            for k, v in match["reticle"].items():
                data["reticle"][k] = v

            data["fire_modes"] = match["fire_modes"]
            data["default_fire_mode"] = match["default_fire_mode"]
            data["burst_size"] = match["burst_size"]
            data["socom_recom_data"] = {
                "original_name": match["display_name"],
                "encumbrance": match["encumbrance"],
                "ammo_spec": match["ammo_spec"]
            }

            with open(fpath, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            print(f"✓ Enriched {fname} with authentic SOCOM '{match['display_name']}' ballistics & tuning.")

    print("\n--- Summary of Categories Imported ---")
    for cat, items in by_category.items():
        sample_names = ", ".join([x["display_name"] for x in items[:4]])
        print(f"• {cat} ({len(items)}): {sample_names}...")


if __name__ == "__main__":
    main()
