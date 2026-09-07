extends SceneTree
## Numerical bore direction validity is independent of physical barrel length.
const Contract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/assaultrifle_1_v3.json"))
	_expect(bool(Contract.validate(source, true).ok), "existing long rifle still valid")
	var short: Dictionary = source.duplicate(true)
	var sockets: Dictionary = short.visual.weapon_sockets
	sockets.barrel_base_socket = {"x":0.18957705,"y":0.1660831,"z":0.0}
	sockets.muzzle_socket = {"x":0.24973985,"y":0.1660831,"z":0.0}
	_expect(bool(Contract.validate(short, true).ok), "actual 1212 Uzi short bore valid")
	sockets.muzzle_socket = sockets.barrel_base_socket.duplicate(true)
	_expect(not bool(Contract.validate(short, true).ok), "zero bore rejected")
	sockets.muzzle_socket.x += 0.000001
	_expect(not bool(Contract.validate(short, true).ok), "one-micrometer degenerate pair rejected")
	sockets.muzzle_socket.x = NAN
	_expect(not bool(Contract.validate(short, true).ok), "nonfinite bore rejected")
	sockets.muzzle_socket.x = INF
	_expect(not bool(Contract.validate(short, true).ok), "infinite bore rejected")
	short.visual.weapon_sockets.erase("muzzle_socket")
	_expect(not bool(Contract.validate(short, true).ok), "missing required marker rejected")
	print("WEAPON_SHORT_BARREL_CONTRACT ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
