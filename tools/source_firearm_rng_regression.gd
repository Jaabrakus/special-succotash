extends SceneTree

## Original instructions, including the whole direction function, are the oracle.
const SourceRng := preload("res://scripts/weapons/source_firearm_rng.gd")
const Dispersion := preload("res://scripts/weapons/source_firearm_dispersion.gd")
var checks := 0
var failures: Array[String] = []


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://config/reference/socom2_fire_rng_vectors.json"))
	expect(evidence.status == "PASS" and evidence.external_stubs == 0, "original execution without unknown stubs")
	for fixture in evidence.rng_vectors:
		var rng := SourceRng.new()
		rng.seed_from_u32(hex64(fixture.seed))
		expect(rng.state == hex64(fixture.seeded_state), "zero-extended original seed")
		for row in fixture.sequence:
			expect(rng.next_raw() == int(row.draw), "original exact 31-bit draw")
			expect(rng.state == hex64(row.state), "original exact 64-bit state")
	var streams: Dictionary = {}
	for row in evidence.direction_vectors:
		var seed_value := int(row.seed)
		if int(row.pellet) == 0:
			var fresh := SourceRng.new()
			fresh.seed_from_u32(seed_value)
			streams[seed_value] = fresh
		var rng: RefCounted = streams[seed_value]
		var first: int = rng.next_raw()
		var second: int = rng.next_raw()
		expect(first == int(row.raw[0]) and second == int(row.raw[1]), "whole direction draw order")
		expect(rng.state == hex64(row.state_after), "two draws per original pellet")
		var actual := Dispersion.raw_direction(vec3(row.direction), vec3(row.accuracy),
			SourceRng.signed_draw_pair(first, second))
		var expected := vec3(row.output)
		expect(actual == expected, "exact finite-float32 original direction seed=%d pellet=%d" % [seed_value, int(row.pellet)])
	print("SOURCE_FIREARM_RNG ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func hex64(value: String) -> int:
	var digits := value.trim_prefix("0x").lpad(16, "0")
	return (digits.substr(0, 8).hex_to_int() << 32) | digits.substr(8, 8).hex_to_int()


func vec3(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
