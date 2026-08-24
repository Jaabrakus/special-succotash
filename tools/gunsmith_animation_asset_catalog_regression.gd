extends SceneTree

const CatalogScript := preload(
	"res://scripts/labs/gunsmith/gunsmith_animation_asset_catalog.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = CatalogScript.new()
	var result: Dictionary = catalog.scan("res://assets/animations/mixamo")
	var entries: Array = result.get("entries", [])
	var paths: Dictionary = result.get("paths", {})
	_expect(not entries.is_empty(), "the imported animation library is discoverable")
	_expect(entries.size() == paths.size(), "every catalog entry has exactly one stable path")
	var previous_display := ""
	for raw_entry: Variant in entries:
		var entry: Dictionary = raw_entry
		var display := String(entry.get("display", ""))
		var key := StringName(entry.get("key", &""))
		_expect(previous_display.is_empty() or previous_display.naturalnocasecmp_to(display) <= 0, "catalog entries remain naturally sorted")
		_expect(String(paths.get(key, "")) == String(entry.get("path", "")), "catalog keys resolve to their displayed asset")
		previous_display = display
	if failures.is_empty():
		print("GUNSMITH_ANIMATION_ASSET_CATALOG_REGRESSION PASS")
		quit(0)
	else:
		push_error("GUNSMITH_ANIMATION_ASSET_CATALOG_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
