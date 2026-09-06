class_name SocomPurchaseValidator
extends RefCounted

## Pure loadout-selection decision logic. The caller supplies current slots
## and phase state; this class never mutates them. Legacy names and optional
## economy context remain compatible, but selection-only mode has no cost.

const Economy := preload("res://scripts/economy/socom_economy_rules.gd")


static func loadout_carry_weight(loadout: Dictionary) -> int:
	var total := 0
	for slot in ["primary", "secondary"]:
		total += Economy.carry_weight_for(String(loadout.get(slot, "")))
	return total


## context keys:
##   cash: int, loadout: {primary: String, secondary: String},
##   phase_open: bool, economy_enabled: bool
## Result keys: ok, reason, cost, slot, carry_weight_after
static func validate(weapon_id: String, context: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"cost": 0,
		"slot": "",
		"carry_weight_after": 0,
	}
	var clean_id := weapon_id.to_lower().strip_edges()
	var record := Economy.weapon_record(clean_id)
	if not Economy.is_armory_weapon(record):
		result["reason"] = "UNKNOWN WEAPON"
		return result
	var category := String(record.get("category", ""))
	var slot := Economy.slot_for_category(category)
	result["slot"] = slot

	var loadout: Dictionary = context.get("loadout", {})
	if String(loadout.get(slot, "")) == clean_id:
		result["reason"] = "ALREADY CARRIED"
		return result

	var economy_enabled := bool(context.get("economy_enabled", true))
	var training_only := bool(record.get("training_only", false))
	if training_only and (economy_enabled or not bool(context.get("allow_training_prototypes", false))):
		result["reason"] = "TRAINING ONLY"
		return result
	var cost := 0 if Economy.selection_only() else Economy.price_for(clean_id)
	result["cost"] = cost
	if not Economy.selection_only() and cost <= 0 and not (training_only and not economy_enabled):
		result["reason"] = "NOT FOR SALE"
		return result

	if economy_enabled:
		if not bool(context.get("phase_open", false)):
			result["reason"] = "LOADOUT LOCKED"
			return result
		if not Economy.selection_only() and cost > int(context.get("cash", 0)):
			result["reason"] = "INSUFFICIENT FUNDS"
			return result

	var replaced_weight := Economy.carry_weight_for(String(loadout.get(slot, "")))
	var carry_after := (
		loadout_carry_weight(loadout)
		- replaced_weight
		+ Economy.carry_weight_for(clean_id)
	)
	result["carry_weight_after"] = carry_after
	if economy_enabled and not Economy.selection_only() and carry_after > Economy.carry_weight_cap():
		result["reason"] = "OVER CARRY WEIGHT"
		return result

	result["ok"] = true
	return result


## Applies a validated selection to a loadout copy; selection-only preserves cash.
static func apply_purchase(weapon_id: String, loadout: Dictionary, cash: int, economy_enabled: bool) -> Dictionary:
	var next_loadout := loadout.duplicate(true)
	var record := Economy.weapon_record(weapon_id)
	next_loadout[Economy.slot_for_category(String(record.get("category", "")))] = weapon_id.to_lower()
	var next_cash := cash
	if economy_enabled and not Economy.selection_only():
		next_cash = maxi(0, cash - Economy.price_for(weapon_id))
	return {"loadout": next_loadout, "cash": next_cash}
