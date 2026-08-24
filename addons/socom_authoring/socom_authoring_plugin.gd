@tool
extends EditorPlugin

const DockContent := preload("res://addons/socom_authoring/animation_routes_dock.gd")
const RouteTransaction := preload("res://addons/socom_authoring/route_document_transaction.gd")
const TOOL_MENU_TITLE := "SOCOM Routes"

var dock: EditorDock
var content: SocomAnimationRoutesDock
var scroll: ScrollContainer


func _enter_tree() -> void:
	content = DockContent.new()
	content.play_requested.connect(_play_canonical_game)
	content.document_transaction_requested.connect(_record_document_transaction)
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
	add_tool_menu_item(TOOL_MENU_TITLE, _show_routes_dock)
	# A saved Godot layout can remember a newly registered global dock as closed.
	# Defer the focus request until editor initialization restores that layout.
	dock.call_deferred(&"make_visible")
	print("SOCOM_AUTHORING_PLUGIN READY source=%s" % DockContent.PROFILE_PATH)


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_TITLE)
	if dock != null:
		remove_dock(dock)
		dock.queue_free()
	dock = null
	scroll = null
	content = null


func _play_canonical_game() -> void:
	EditorInterface.play_main_scene()


func _show_routes_dock() -> void:
	if dock != null:
		dock.make_visible()


func _record_document_transaction(
	action_name: String,
	before_document: Dictionary,
	after_document: Dictionary
) -> void:
	var undo_redo := get_undo_redo()
	var transaction = RouteTransaction.new(content, before_document, after_document)
	undo_redo.create_action(
		action_name,
		UndoRedo.MERGE_DISABLE,
		content.repository,
		false,
		false
	)
	undo_redo.add_do_method(transaction, &"apply_after")
	undo_redo.add_undo_method(transaction, &"apply_before")
	undo_redo.commit_action()
