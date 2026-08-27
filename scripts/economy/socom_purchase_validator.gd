class_name SocomPurchaseValidator
extends RefCounted

## Pure purchase decision logic for the buy menu. The caller supplies the
## context (cash, current loadout, phase state); this class never mutates it.
## Both the server authority and the training-range sandbox resolve through
## the same rules so presentation can predict the authoritative outcome.

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
	if record.is_empty() or not Economy.is_firearm_category(String(record.get("category", ""))):
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
	var cost := Economy.price_for(clean_id)
	result["cost"] = cost
	if cost <= 0:
		result["reason"] = "NOT FOR SALE"
		return result

	if economy_enabled:
		if not bool(context.get("phase_open", false)):
			result["reason"] = "BUY WINDOW CLOSED"
			return result
		if cost > int(context.get("cash", 0)):
			result["reason"] = "INSUFFICIENT FUNDS"
			return result

	var replaced_weight := Economy.carry_weight_for(String(loadout.get(slot, "")))
	var carry_after := (
		loadout_carry_weight(loadout)
		- replaced_weight
		+ Economy.carry_weight_for(clean_id)
	)
	result["carry_weight_after"] = carry_after
	if economy_enabled and carry_after > Economy.carry_weight_cap():
		result["reason"] = "OVER CARRY WEIGHT"
		return result

	result["ok"] = true
	return result


## Applies a validated purchase to a loadout copy and returns the cash left.
static func apply_purchase(weapon_id: String, loadout: Dictionary, cash: int, economy_enabled: bool) -> Dictionary:
	var next_loadout := loadout.duplicate(true)
	var record := Economy.weapon_record(weapon_id)
	next_loadout[Economy.slot_for_category(String(record.get("category", "")))] = weapon_id.to_lower()
	var next_cash := cash
	if economy_enabled:
		next_cash = maxi(0, cash - Economy.price_for(weapon_id))
	return {"loadout": next_loadout, "cash": next_cash}
