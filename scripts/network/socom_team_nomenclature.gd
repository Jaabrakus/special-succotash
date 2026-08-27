class_name SocomTeamNomenclature
extends RefCounted

## Single source of the Square's team words (docs/SQUARE_DESIGN_LANGUAGE.md).
## Team ids 0 and 1 never change; this maps them onto the axis a map declares.
## Presentation layers read words from here — never hardcode them again.

const AXES := {
	"default": ["SATOR", "ROTAS"],
	"alternate": ["AREPO", "OPERA"],
	"classic": ["ALPHA", "BRAVO"],
}
const HOUSES: Array[String] = ["SATOR", "AREPO", "TENET", "OPERA", "ROTAS"]


## Ordered labels [team 0, team 1] for an axis name. Unknown axes fall back
## to the default axis rather than erroring.
static func labels_for_axis(axis: String) -> Array[String]:
	var pair: Array = AXES.get(axis, AXES["default"]) as Array
	var labels: Array[String] = []
	for word: Variant in pair:
		labels.append(String(word))
	return labels


## Ordered labels [team 0, team 1] for a map document's declared axis.
static func labels_for_document(document: Dictionary) -> Array[String]:
	var lore: Dictionary = document.get("lore", {}) as Dictionary if document.get("lore", {}) is Dictionary else {}
	return labels_for_axis(String(lore.get("axis", "default")))


## The map's patron House (one of the five words), or "" when unaffiliated.
static func house_for_document(document: Dictionary) -> String:
	var lore: Dictionary = document.get("lore", {}) as Dictionary if document.get("lore", {}) is Dictionary else {}
	var house := String(lore.get("house", "")).to_upper()
	return house if HOUSES.has(house) else ""


## The map's one-sentence brief, clamped to a marginalia length.
static func brief_for_document(document: Dictionary) -> String:
	var lore: Dictionary = document.get("lore", {}) as Dictionary if document.get("lore", {}) is Dictionary else {}
	return String(lore.get("brief", "")).strip_edges().substr(0, 160)
