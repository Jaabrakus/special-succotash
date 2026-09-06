extends SceneTree

const Audio := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const Presentation := preload("res://scripts/network/socom_shot_presentation.gd")
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Purchase := preload("res://scripts/economy/socom_purchase_validator.gd")
var failures := 0

class AcousticSpy extends Node:
	var events: Array[Dictionary] = []
	func play_event(stream: AudioStream, position: Vector3, category: StringName, options: Dictionary) -> Dictionary:
		events.append({"stream": stream, "position": position, "category": category, "options": options})
		return {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var real_acoustics := root.get_node("AcousticPropagation")
	real_acoustics.name = "RealAcoustics"
	var spy := AcousticSpy.new()
	spy.name = "AcousticPropagation"
	root.add_child(spy)
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Audio.WEAPON_SOUND_BANK_PATH))
	var entries: Dictionary = bank.weapons
	_expect(entries.size() == 33, "33 explicit existing-firearm assignments")
	var exclusions: Dictionary = bank.get("non_firearm_exclusions", {})
	var expected_exclusions := ["designator", "mk_3-a2", "air_to_ground_missile", "exploding_fuel"]
	_expect(exclusions.size() == expected_exclusions.size(), "only four audited legacy non-firearm exclusions")
	for id: String in expected_exclusions:
		_expect(exclusions.has(id) and not entries.has(id), id + " excluded explicitly, not miswired")
	var selectable_firearms := 0
	for category: String in Economy.firearm_categories():
		for record: Dictionary in Economy.weapons_for_category(category):
			var id := String(record.weapon_id)
			var decision := Purchase.validate(id, {
				"loadout": {}, "economy_enabled": false, "allow_training_prototypes": true,
			})
			if not bool(decision.ok) or expected_exclusions.has(id):
				continue
			selectable_firearms += 1
			_expect(entries.has(id), id + " selectable firearm has intentional audio")
	_expect(selectable_firearms == 33, "all 33 actual selectable firearms audited")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://artifacts/audio/socom2_weapon_samples/manifest.json"))
	var samples := {}
	for sample: Dictionary in manifest.samples:
		samples[String(sample.sample_id)] = sample
	var distinct_streams := {}
	var substitutes := 0
	var scene := load("res://main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 30:
		await process_frame
	var presentation := Presentation.new()
	game.add_child(presentation)
	var fallback := Audio.gunshot_stream()
	for id: String in entries:
		var entry: Dictionary = entries[id]
		distinct_streams[entry.stream] = true
		var sample: Dictionary = samples.get(String(entry.source_sample_id), {})
		_expect(sample.get("event", "") == "fire", id + " uses a gunshot, not launch or detonation")
		_expect(sample.get("sha256", "") == entry.sha256, id + " source provenance preserved")
		var kind := String(entry.get("match_kind", ""))
		_expect(kind in ["reference_match", "game_label_match", "same_firearm_variant", "family_substitute"], id + " match confidence is explicit")
		if kind == "family_substitute":
			substitutes += 1
			_expect(id in ["870", "mark_46_mod_0"] and not String(entry.get("match_basis", "")).is_empty(), id + " provisional substitution documented")
		_expect(not Catalog.get_weapon(id).is_empty(), id + " exists in catalog")
		_expect(FileAccess.get_sha256(entry.stream) == entry.sha256, id + " exact reviewed-pack PCM")
		var selected_path := String(entry.stream)
		if bool(bank.get("use_cleaned_streams", false)):
			selected_path = String(entry.get("cleaned_stream", ""))
			_expect(not selected_path.is_empty(), id + " cleaned assignment exists")
			_expect(FileAccess.get_sha256(selected_path) == entry.get("cleaned_sha256", ""), id + " derived PCM hash verified")
		var stream := Audio.gunshot_stream(false, id)
		_expect(stream == load(selected_path), id + " runtime uses selected bank variant")
		_expect(stream != fallback and stream.get_length() > 0.1, id + " assigned imported sound")
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, id + " no looping")
		for shot in 10:
			_expect(Audio.gunshot_stream(false, id) == stream, id + " cached resource")
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/%s.json" % id))
		spy.events.clear()
		presentation.present_shot(Vector3.ZERO, Vector3.FORWARD, false, "MISS", config, [])
		_expect(spy.events.size() == 1 and spy.events[0].stream == stream, id + " multiplayer one matching event")
		game.weapon_controller.equipped_weapon_config = config
		spy.events.clear()
		game.weapon_runtime.on_authoritative_shot({"origin": Vector3.ZERO, "hit_pos": Vector3.FORWARD, "projectiles": []})
		_expect(spy.events.size() == 1 and spy.events[0].stream == stream, id + " canonical one matching event")
		var expected_volume := -2.0 if bool(config.ballistics.get("is_silenced", false)) else 2.0
		_expect(float(spy.events[0].options.volume_db) == expected_volume, id + " suppression preserved")
	_expect(Audio.gunshot_stream(false, "unknown") == fallback, "unknown uses original fallback")
	_expect(distinct_streams.size() == 29, "33 assignments reuse 29 imported WAVs")
	_expect(substitutes == 2, "only 870 and Mark 46 are provisional family substitutes")
	for variant: String in ["m4a1-m203", "m16a2-m203"]:
		var parent := variant.trim_suffix("-m203")
		_expect(Audio.gunshot_stream(false, variant) == Audio.gunshot_stream(false, parent), variant + " shares parent bullet sound")
	_expect(entries.m14.match_kind == "game_label_match", "M14 is a game-label match, not real-world identity claim")
	_expect(Audio.gunshot_stream(false, "mk_3-a2") == fallback, "no grenade sound on firearm")
	_expect(Audio.gunshot_stream(true, "unknown") == Audio.gunshot_stream(true), "silenced fallback")
	Audio.shutdown()
	game.queue_free()
	spy.queue_free()
	await process_frame
	real_acoustics.name = "AcousticPropagation"
	await process_frame
	print("WEAPON_SOUND_BANK_REGRESSION ", "PASS" if failures == 0 else "FAIL", " matches=", entries.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("WEAPON_SOUND_BANK FAIL " + label)
