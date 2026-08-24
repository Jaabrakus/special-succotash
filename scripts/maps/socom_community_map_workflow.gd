class_name SocomCommunityMapWorkflow
extends RefCounted

## Application service for the Map Lab community-map boundary. It coordinates
## the cloud client and local map library without owning editor controls.

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")


func identity_text(service: Node) -> String:
	if service == null or not bool(service.call("is_configured")):
		return "COMMUNITY: Offline / not configured"
	if bool(service.call("has_guest_session")):
		return "COMMUNITY: %s" % String(service.call("display_name"))
	return "COMMUNITY: Guest connects when needed"


func publish(service: Node, document: Dictionary) -> Dictionary:
	if service == null:
		return {
			"ok": false,
			"message": "Community service is unavailable. Your map remains saved locally.",
		}
	return await service.call("publish_map", document)


func list_public(service: Node) -> Dictionary:
	if service == null:
		return {"ok": false, "message": "Community service is unavailable.", "maps": []}
	var result: Dictionary = await service.call("list_public_maps")
	return {
		"ok": bool(result.get("ok", false)),
		"message": String(result.get("message", "Could not load community maps.")),
		"maps": result.get("maps", []) if result.get("maps", []) is Array else [],
	}


func download_to_library(service: Node, entry: Dictionary) -> Dictionary:
	if service == null:
		return {"ok": false, "message": "Community service is unavailable."}
	var result: Dictionary = await service.call("download_map", entry)
	if not bool(result.get("ok", false)):
		return result
	var downloaded: Dictionary = result.get("document", {})
	var saved := MapDocument.save_to_library(downloaded)
	if not bool(saved.get("ok", false)):
		return {
			"ok": false,
			"message": saved.get("error", "Could not save the downloaded map locally."),
		}
	return {
		"ok": true,
		"message": String(result.get("message", "Community map downloaded.")),
		"document": (saved.get("document", downloaded) as Dictionary).duplicate(true),
	}
