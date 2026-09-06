extends SceneTree

const Effects := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const WeaponRuntime := preload("res://scripts/runtime/main_weapon_runtime.gd")

class FakeMannequin:
	extends Node3D
	var muzzle: Marker3D
	func get_active_muzzle_marker() -> Marker3D:
		return muzzle

class FakeWeapon:
	extends Node
	var equipped_weapon_config: Dictionary = {}

class FakeHost:
	extends Node3D
	var player: Node3D
	var weapon_controller: Node

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := FakeHost.new()
	root.add_child(host)
	current_scene = host
	var actor := Node3D.new()
	host.add_child(actor)
	host.player = actor
	var mannequin := FakeMannequin.new()
	mannequin.name = "Mannequin"
	actor.add_child(mannequin)
	var marker := Marker3D.new()
	mannequin.add_child(marker)
	mannequin.muzzle = marker
	var weapon := FakeWeapon.new()
	host.add_child(weapon)
	host.weapon_controller = weapon
	var runtime := WeaponRuntime.new()
	host.add_child(runtime)
	runtime.configure(host)
	_expect(runtime._presented_muzzle_effect_source() == null, "existing profiles retain snapshot effects")
	weapon.equipped_weapon_config = {"handling_profile": {"presentation": {
		"muzzle_effect_follows_presented_muzzle": true,
	}}}
	_expect(runtime._presented_muzzle_effect_source() == marker, "saved opt-in resolves canonical active muzzle")
	Effects.initialize(host)
	var pooled_node_count := host.get_child_count()
	var origin := Vector3(2.0, 1.5, 3.0)
	var endpoint := Vector3(2.0, 1.5, -20.0)
	Effects.spawn_muzzle_flash(self, origin, Vector3.FORWARD)
	_expect(Effects._muzzle_flash_light.global_position.is_equal_approx(origin), "legacy flash remains at accepted origin")
	_expect(Effects._presented_muzzle_effects.is_empty(), "legacy effects create no follow work")
	_expect(not RenderingServer.frame_pre_draw.is_connected(Effects._sync_presented_muzzle_effects), "legacy-only firing adds no render callback")
	marker.position = origin
	var smoke_index := Effects._muzzle_smoke_index
	Effects.spawn_muzzle_flash(self, origin, Vector3.FORWARD, marker)
	var smoke := Effects._muzzle_smoke_pool[smoke_index]
	_expect(int(Effects._presented_muzzle_effects[0]["started_usec"]) == -1, "opted-in effect waits for presented frame")
	marker.position += Vector3(0.21, -0.1, -0.15)
	marker.rotation = Vector3(0.12, -0.2, 0.0)
	Effects._sync_presented_muzzle_effects()
	_expect(smoke.global_position.is_equal_approx(marker.global_position), "first emission uses post-pose muzzle, not old snapshot")
	_expect(Effects._muzzle_flash_light.global_position.is_equal_approx(marker.global_position), "first light uses post-pose muzzle")
	_expect(not smoke.local_coords, "emitted smoke remains in world space")
	_expect(smoke.direction.is_equal_approx(-marker.global_basis.z.normalized() + Vector3(0.0, 0.12, 0.0)), "smoke direction follows rendered barrel")
	marker.position += Vector3(0.05, 0.02, 0.0)
	Effects._sync_presented_muzzle_effects()
	_expect(smoke.global_position.is_equal_approx(marker.global_position), "emitter follows ongoing pose correction")
	_expect(Effects._muzzle_flash_light.global_position.is_equal_approx(marker.global_position), "short-lived light follows ongoing pose correction")
	var shot := {"origin": origin, "hit_pos": endpoint}
	var snapshot := shot.duplicate(true)
	Effects.set_trajectory_debug_enabled(true)
	var tracer_index := Effects._tracer_index
	Effects.spawn_tracer(self, shot.origin, shot.hit_pos)
	var arrays := Effects._tracer_pool[tracer_index].mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_expect(vertices.size() == 2 and vertices[0].is_equal_approx(origin) and vertices[1].is_equal_approx(endpoint), "tracer preserves accepted origin and endpoint")
	_expect(shot == snapshot, "accepted shot data is unchanged")
	var started_usec := int(Effects._presented_muzzle_effects[0]["started_usec"])
	Effects._update_presented_muzzle_effects(started_usec + 1000000)
	_expect(Effects._presented_muzzle_effects.is_empty(), "expired smoke stops all follow work")
	_expect(not RenderingServer.frame_pre_draw.is_connected(Effects._sync_presented_muzzle_effects), "idle has no frame callback")
	Effects.spawn_muzzle_flash(self, origin, Vector3.FORWARD, marker)
	Effects.spawn_muzzle_flash(self, endpoint, Vector3.FORWARD)
	Effects._sync_presented_muzzle_effects()
	_expect(Effects._muzzle_flash_light.global_position.is_equal_approx(endpoint), "older follow never overwrites newer legacy light")
	for index in range(Effects.MUZZLE_SMOKE_POOL_SIZE + 2):
		Effects.spawn_muzzle_flash(self, origin, Vector3.FORWARD, marker)
	_expect(Effects._presented_muzzle_effects.size() <= Effects.MUZZLE_SMOKE_POOL_SIZE, "pool reuse bounds follow entries")
	_expect(host.get_child_count() == pooled_node_count, "shots allocate no extra scene nodes")
	marker.free()
	Effects._sync_presented_muzzle_effects()
	_expect(Effects._presented_muzzle_effects.is_empty(), "weapon removal safely releases weak follow references")
	_expect(not RenderingServer.frame_pre_draw.is_connected(Effects._sync_presented_muzzle_effects), "removed muzzle disconnects idle callback")
	var replacement_marker := Marker3D.new()
	host.add_child(replacement_marker)
	Effects.spawn_muzzle_flash(self, origin, Vector3.FORWARD, replacement_marker)
	host.free()
	Effects._sync_presented_muzzle_effects()
	_expect(Effects._presented_muzzle_effects.is_empty(), "scene exit safely clears pending effects after the pool is freed")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/mark_23.json"))
	_expect(saved is Dictionary, "Mark23 saved profile parses")
	if saved is Dictionary:
		var handling: Dictionary = (saved as Dictionary).get("handling_profile", {})
		var presentation: Dictionary = handling.get("presentation", {})
		_expect(bool(presentation.get("muzzle_effect_follows_presented_muzzle", false)), "Mark23 saved profile enables presented muzzle effects")
	if failures.is_empty():
		print("PISTOL_PRESENTED_MUZZLE_EFFECT_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
	else:
		print("PASS: ", message)
