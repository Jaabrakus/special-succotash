extends SceneTree

const Catalog := preload("res://scripts/labs/animation_clip_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.weapon_family = "TWO_HAND_RIFLE"
	catalog.family_state_names = {"aim_idle": true, "run_left": true}
	var slots := {
		"aim_idle": "res://clips/rifle_idle.fbx",
		"pistol_idle": "res://clips/pistol_idle.fbx",
	}
	_expect(
		catalog.describe({"display": "[Rifle] Idle", "path": slots.aim_idle}, slots).status == Catalog.LIVE,
		"an exact equipped-family state assignment is labeled live"
	)
	_expect(
		catalog.describe({"display": "[Rifle] Run Left", "path": "res://clips/run_left.fbx"}, slots, "run_left").status == Catalog.RIFLE_CANDIDATE,
		"a rifle filename without an assignment stays a candidate"
	)
	_expect(
		catalog.describe({"display": "[Pistol] Idle", "path": "res://clips/other_pistol.fbx"}, slots).status == Catalog.OTHER_FAMILY,
		"another weapon family is kept separate"
	)
	_expect(
		catalog.describe({"display": "Start Walking", "path": "res://clips/start.fbx"}, slots).status == Catalog.UNCLASSIFIED,
		"an ambiguous name is honestly labeled unclassified"
	)
	catalog.family_state_names["start_forward"] = true
	slots["start_forward"] = "res://clips/start.fbx"
	_expect(
		catalog.describe({"display": "Start Walking", "path": "res://clips/start.fbx"}, slots).status == Catalog.LIVE,
		"a shared transition becomes live only through its exact approved state assignment"
	)
	if failures.is_empty():
		print("ANIMATION_CLIP_CATALOG_REGRESSION PASS")
		quit(0)
	else:
		push_error("ANIMATION_CLIP_CATALOG_REGRESSION FAIL " + str(failures))
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_CLIP_CATALOG_CHECK PASS ", label)
	else:
		failures.append(label)
