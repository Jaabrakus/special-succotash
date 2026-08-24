class_name SocomPlayerAmmunitionInventory
extends Node

## Player-owned ammunition state. Weapon resources describe capacity and a
## starting loadout, but never own mutable rounds or magazines.

signal ammo_changed(weapon_id: StringName, magazine_rounds: int, reserve_rounds: int)

var _weapons: Dictionary = {}


func ensure_weapon(
	weapon_id: StringName,
	magazine_capacity: int,
	starting_magazine_rounds: int,
	starting_reserve_rounds: int
) -> Dictionary:
	var key := String(weapon_id)
	var capacity := clampi(magazine_capacity, 1, 200)
	if not _weapons.has(key):
		_weapons[key] = {
			"magazine_capacity": capacity,
			"rounds_in_magazine": clampi(starting_magazine_rounds, 0, capacity),
			"reserve_ammo": clampi(starting_reserve_rounds, 0, 9999),
		}
	else:
		var existing: Dictionary = (_weapons[key] as Dictionary).duplicate(true)
		existing["magazine_capacity"] = capacity
		existing["rounds_in_magazine"] = clampi(
			int(existing.get("rounds_in_magazine", 0)), 0, capacity
		)
		existing["reserve_ammo"] = maxi(0, int(existing.get("reserve_ammo", 0)))
		_weapons[key] = existing
	return snapshot(weapon_id)


func reset_weapon(
	weapon_id: StringName,
	magazine_capacity: int,
	starting_reserve_rounds: int
) -> Dictionary:
	var key := String(weapon_id)
	var capacity := clampi(magazine_capacity, 1, 200)
	_weapons[key] = {
		"magazine_capacity": capacity,
		"rounds_in_magazine": capacity,
		"reserve_ammo": clampi(starting_reserve_rounds, 0, 9999),
	}
	_emit_changed(weapon_id)
	return snapshot(weapon_id)


func set_ammo(weapon_id: StringName, magazine_rounds: int, reserve_rounds: int) -> Dictionary:
	var current := snapshot(weapon_id)
	var capacity := maxi(1, int(current.get("magazine_capacity", magazine_rounds)))
	_weapons[String(weapon_id)] = {
		"magazine_capacity": capacity,
		"rounds_in_magazine": clampi(magazine_rounds, 0, capacity),
		"reserve_ammo": clampi(reserve_rounds, 0, 9999),
	}
	_emit_changed(weapon_id)
	return snapshot(weapon_id)


func consume_round(weapon_id: StringName) -> bool:
	var current := snapshot(weapon_id)
	var magazine := int(current.get("rounds_in_magazine", 0))
	if magazine <= 0:
		return false
	current["rounds_in_magazine"] = magazine - 1
	_weapons[String(weapon_id)] = current
	_emit_changed(weapon_id)
	return true


func reload_weapon(weapon_id: StringName) -> int:
	var current := snapshot(weapon_id)
	var capacity := int(current.get("magazine_capacity", 0))
	var magazine := int(current.get("rounds_in_magazine", 0))
	var reserve := int(current.get("reserve_ammo", 0))
	var transferred := mini(maxi(0, capacity - magazine), reserve)
	if transferred <= 0:
		return 0
	current["rounds_in_magazine"] = magazine + transferred
	current["reserve_ammo"] = reserve - transferred
	_weapons[String(weapon_id)] = current
	_emit_changed(weapon_id)
	return transferred


func snapshot(weapon_id: StringName) -> Dictionary:
	var current: Variant = _weapons.get(String(weapon_id), {})
	return (current as Dictionary).duplicate(true) if current is Dictionary else {}


func _emit_changed(weapon_id: StringName) -> void:
	var current := snapshot(weapon_id)
	ammo_changed.emit(
		weapon_id,
		int(current.get("rounds_in_magazine", 0)),
		int(current.get("reserve_ammo", 0))
	)
