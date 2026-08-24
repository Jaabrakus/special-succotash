extends SceneTree

const WorkflowScript := preload("res://scripts/maps/socom_community_map_workflow.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

class FakeCommunityService:
	extends Node
	var configured := true
	var download_document: Dictionary = {}

	func is_configured() -> bool:
		return configured

	func has_guest_session() -> bool:
		return true

	func display_name() -> String:
		return "NOMAD_141"

	func publish_map(document: Dictionary) -> Dictionary:
		return {"ok": true, "message": "Published", "version": 3, "document": document}

	func list_public_maps() -> Dictionary:
		return {"ok": true, "message": "One map", "maps": [{"id": "map-1", "title": "Test"}]}

	func download_map(_entry: Dictionary) -> Dictionary:
		return {"ok": true, "message": "Downloaded", "document": download_document.duplicate(true)}


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	MapDocument.library_directory_override = "/private/tmp/socom-community-workflow-regression"
	var workflow = WorkflowScript.new()
	var service := FakeCommunityService.new()
	service.download_document = MapDocument.new_document("Downloaded Regression")
	root.add_child(service)
	_expect(workflow.identity_text(service) == "COMMUNITY: NOMAD_141", "workflow formats the connected identity")
	var published: Dictionary = await workflow.publish(service, MapDocument.new_document("Publish Regression"))
	_expect(bool(published.get("ok", false)) and int(published.get("version", 0)) == 3, "workflow delegates publishing")
	var listed: Dictionary = await workflow.list_public(service)
	_expect(bool(listed.get("ok", false)) and (listed.get("maps", []) as Array).size() == 1, "workflow normalizes the public map list")
	var downloaded: Dictionary = await workflow.download_to_library(service, {"id": "map-1"})
	_expect(bool(downloaded.get("ok", false)) and String(downloaded.get("document", {}).get("name", "")) == "Downloaded Regression", "workflow saves downloads into the local map library")
	_expect(not bool((await workflow.publish(null, {})).get("ok", true)), "workflow handles an unavailable community service")
	service.queue_free()
	MapDocument.library_directory_override = ""
	if failures.is_empty():
		print("COMMUNITY_MAP_WORKFLOW_REGRESSION PASS")
		quit(0)
	else:
		push_error("COMMUNITY_MAP_WORKFLOW_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
