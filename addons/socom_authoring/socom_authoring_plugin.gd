@tool
extends EditorPlugin

const DockContent := preload("res://addons/socom_authoring/animation_routes_dock.gd")

var dock: EditorDock
var content: SocomAnimationRoutesDock
var scroll: ScrollContainer


func _enter_tree() -> void:
	content = DockContent.new()
	content.play_requested.connect(_play_canonical_game)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock = EditorDock.new()
	dock.title = "SOCOM Routes"
	dock.layout_key = "socom_animation_routes"
	dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	dock.add_child(scroll)
	add_dock(dock)
	print("SOCOM_AUTHORING_PLUGIN READY source=%s" % DockContent.PROFILE_PATH)


func _exit_tree() -> void:
	if dock != null:
		remove_dock(dock)
		dock.queue_free()
	dock = null
	scroll = null
	content = null


func _play_canonical_game() -> void:
	EditorInterface.play_main_scene()
