extends SceneTree

const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Rounds := preload("res://scripts/network/socom_round_weapon_rules.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")
const EXPECTED := ["mark_23", "de__50", "m9", "m4a1", "m16a2", "ak-47", "aks-74", "hk5", "m14", "m40a1", "870", "m60e3"]
var failures: Array[String] = []

func _initialize() -> void:
	var public_ids: Array[String] = []
	var names: Array[String] = []
	var context := {"cash": 0, "loadout": {}, "phase_open": true, "economy_enabled": true, "allow_training_prototypes": true}
	for record: Dictionary in Catalog.get_all_weapons():
		var id := String(record.weapon_id)
		if Economy.is_armory_weapon(record):
			public_ids.append(id)
			_expect(EXPECTED.has(id), "visible ID approved: " + id)
			var profile := Contract.load_config("res://config/weapons/" + id + ".json")
			_expect(profile.weapon_id == id, "internal ID preserved")
			_expect(profile.display_name == record.display_name, "HUD and menu name parity")
			_expect(not names.has(record.display_name), "codename unique")
			names.append(record.display_name)
		else:
			_expect(not Validator.validate(id, context).ok, "hidden ID cannot be submitted to selection")
	_expect(public_ids.size() == 12, "exactly twelve visible")
	var eagle := Validator.validate("de__50", context)
	_expect(eagle.ok and eagle.slot == "secondary", "Desert Eagle selectable in pistol slot")
	_expect(Contract.load_config("res://config/weapons/de__50.json").display_name == "Sentinel .50", "Desert Eagle HUD codename")
	var pool := Rounds.firearm_pool()
	public_ids.sort()
	_expect(pool == public_ids, "menu and tournament pool identical")
	for index in 100:
		_expect(EXPECTED.has(Rounds.choose_shared_weapon(42, str(index))), "random assignment stays in roster")
	_expect(Catalog.get_all_weapons().size() == 63, "all source records retained")
	_expect(FileAccess.get_sha256(Catalog.CATALOG_PATH) == "a867d849e3e1a3c1e056537395d9832e13958a31bf3dca688e8711d9a9325d79", "archive unchanged")
	_expect(not Contract.load_config("res://config/weapons/hk5sd.json").is_empty(), "hidden profile remains loadable for developers")
	print("CORE_WEAPON_ROSTER_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
