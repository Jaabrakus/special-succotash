class_name SocomOperatorAnimationProfile
extends Resource

## Drag-and-drop animation surface for the operator state matrix.
##
## Animations placed in an override library replace clips with the same logical
## name. Aliases let a logical movement slot use a differently named imported
## clip without changing controller or animation-selection code.

@export_group("Drag-and-drop clips")
@export var loop_overrides: AnimationLibrary
@export var action_overrides: AnimationLibrary

@export_group("Imported clip aliases")
@export var clip_aliases: Dictionary[StringName, StringName] = {}

const DIRECTION_SUFFIXES: Array[StringName] = [
    &"forward", &"forward_left", &"left", &"back_left",
    &"backward", &"back_right", &"right", &"forward_right",
]


func install_overrides(animation_player: AnimationPlayer) -> void:
    _install_library(animation_player, loop_overrides, true)
    _install_library(animation_player, action_overrides, false)


func resolve_clip(logical_name: StringName) -> StringName:
    return clip_aliases.get(logical_name, logical_name) as StringName


func get_required_loop_slots() -> Array[StringName]:
    var slots: Array[StringName] = [
        &"low_ready_idle", &"low_ready_crouch_idle", &"low_ready_prone_idle",
        &"combat_ready_idle", &"combat_ready_crouch_idle", &"combat_ready_prone_idle",
        &"compressed_ready_idle", &"compressed_ready_crouch", &"compressed_ready_prone",
    ]
    for prefix in [
        "low_ready_walk", "low_ready_run", "low_ready_crouch",
        "walk", "run", "crouch",
    ]:
        for suffix in DIRECTION_SUFFIXES:
            slots.append(StringName("%s_%s" % [prefix, suffix]))
    for suffix in [&"forward", &"backward", &"left", &"right"]:
        slots.append(StringName("low_ready_prone_%s" % suffix))
    return slots


func _install_library(
    animation_player: AnimationPlayer,
    source: AnimationLibrary,
    looping: bool
) -> void:
    if source == null:
        return
    var target := animation_player.get_animation_library(&"")
    if target == null:
        target = AnimationLibrary.new()
        animation_player.add_animation_library(&"", target)
    for clip_name in source.get_animation_list():
        var animation := source.get_animation(clip_name).duplicate() as Animation
        if animation == null:
            continue
        animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
        if target.has_animation(clip_name):
            target.remove_animation(clip_name)
        target.add_animation(clip_name, animation)
