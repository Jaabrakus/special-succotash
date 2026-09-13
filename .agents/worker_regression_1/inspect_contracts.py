#!/usr/bin/env python3
import os
import json
import glob
from collections import defaultdict

contracts_dir = "/Users/kiwimango/socom-141-camera-lab/config/feature_contracts"
contract_files = sorted(glob.glob(os.path.join(contracts_dir, "*.json")))

print(f"Total contracts: {len(contract_files)}")

proof_to_contracts = defaultdict(list)
contract_summary = []

for fpath in contract_files:
    fname = os.path.basename(fpath)
    with open(fpath, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception as e:
            print(f"Error reading {fname}: {e}")
            continue

    fid = data.get("feature_id", fname)
    proof_scripts = data.get("proof_scripts", [])
    for ps in proof_scripts:
        clean_ps = ps.replace("res://", "")
        proof_to_contracts[clean_ps].append(fid)

    contract_summary.append({
        "file": fname,
        "feature_id": fid,
        "player_intent": data.get("player_intent", ""),
        "acceptance_rule": data.get("acceptance_rule", ""),
        "proof_scripts": proof_scripts,
        "ownership": data.get("ownership", {})
    })

print(f"Unique proof scripts referenced: {len(proof_to_contracts)}")
for ps, fids in sorted(proof_to_contracts.items()):
    exists = os.path.exists(f"/Users/kiwimango/socom-141-camera-lab/{ps}")
    print(f"  {ps} (exists: {exists}) -> {len(fids)} contract(s)")

with open("/Users/kiwimango/socom-141-camera-lab/.agents/worker_regression_1/contracts_summary.json", "w", encoding="utf-8") as out:
    json.dump({
        "contracts": contract_summary,
        "proof_scripts": {k: {"exists": os.path.exists(f"/Users/kiwimango/socom-141-camera-lab/{k}"), "contracts": v} for k, v in proof_to_contracts.items()}
    }, out, indent=2)
