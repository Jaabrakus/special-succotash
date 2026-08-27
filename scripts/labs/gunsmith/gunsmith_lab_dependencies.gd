class_name GunsmithLabDependencies
extends Node3D

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const OperatorAnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const OperatorAnimationStateContract := preload("res://scripts/player/operator_animation_state_contract.gd")
const WeaponAnimationProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const WeaponContactSolver := preload("res://scripts/player/operator_weapon_contact_solver.gd")
const OperatorPostureLayer := preload("res://scripts/player/operator_posture_layer.gd")
const ProceduralPoseProfile := preload("res://scripts/player/operator_procedural_pose_profile.gd")
const JointControlSchema := preload("res://scripts/player/operator_joint_control_schema.gd")
const GunsmithAnimationFrameEditorScript := preload("res://scripts/labs/gunsmith/gunsmith_animation_frame_editor.gd")
const GunsmithBallisticsView := preload("res://scripts/labs/gunsmith/gunsmith_ballistics_view.gd")
const GunPlacementProfile := preload("res://scripts/player/weapon_gun_placement_profile.gd")
const WeaponProfileRepository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const WeaponSceneExporter := preload("res://scripts/labs/gunsmith/gunsmith_weapon_scene_exporter.gd")
const GunsmithHitboxModelScript := preload("res://scripts/labs/gunsmith/gunsmith_hitbox_model.gd")
const GunsmithComposurePanelScript := preload("res://scripts/labs/gunsmith/gunsmith_composure_panel.gd")
const GunsmithGizmoFactory := preload("res://scripts/labs/gunsmith/gunsmith_gizmo_factory.gd")
const GunsmithFrameEditorView := preload("res://scripts/labs/gunsmith/gunsmith_frame_editor_view.gd")
const GunsmithStudioView := preload("res://scripts/labs/gunsmith/gunsmith_studio_view.gd")
const GunsmithInputController := preload("res://scripts/labs/gunsmith/gunsmith_input_controller.gd")
const GunsmithPreviewUpdateController := preload("res://scripts/labs/gunsmith/gunsmith_preview_update_controller.gd")
const GunsmithProfileLoader := preload("res://scripts/labs/gunsmith/gunsmith_profile_loader.gd")
const GunsmithWeaponPreviewLoader := preload("res://scripts/labs/gunsmith/gunsmith_weapon_preview_loader.gd")
const GunsmithHandlingPanel := preload("res://scripts/labs/gunsmith/gunsmith_handling_panel.gd")
const GunsmithAnimationFrameController := preload("res://scripts/labs/gunsmith/gunsmith_animation_frame_controller.gd")
const GunsmithAnimationPreviewController := preload("res://scripts/labs/gunsmith/gunsmith_animation_preview_controller.gd")
const GunsmithGizmoInteractionController := preload("res://scripts/labs/gunsmith/gunsmith_gizmo_interaction_controller.gd")
const GunsmithRigAuthoringController := preload("res://scripts/labs/gunsmith/gunsmith_rig_authoring_controller.gd")
const GunsmithPreviewSceneController := preload("res://scripts/labs/gunsmith/gunsmith_preview_scene_controller.gd")
const GunsmithWeaponPoseController := preload("res://scripts/labs/gunsmith/gunsmith_weapon_pose_controller.gd")
const GunsmithWeaponFirePreviewController := preload("res://scripts/labs/gunsmith/gunsmith_weapon_fire_preview_controller.gd")
const GunsmithPersistenceController := preload("res://scripts/labs/gunsmith/gunsmith_persistence_controller.gd")
const GunsmithHitboxAuthoringController := preload("res://scripts/labs/gunsmith/gunsmith_hitbox_authoring_controller.gd")
const GunsmithActionWeaponController := preload("res://scripts/labs/gunsmith/gunsmith_action_weapon_controller.gd")
const GunsmithHandSolver := preload("res://scripts/labs/gunsmith/gunsmith_hand_solver.gd")
const GunsmithPresentationController := preload("res://scripts/labs/gunsmith/gunsmith_presentation_controller.gd")
const GunsmithEventPreviewController := preload("res://scripts/labs/gunsmith/gunsmith_event_preview_controller.gd")
const GunsmithAnimationQualityAuditorScript := preload("res://scripts/labs/gunsmith/gunsmith_animation_quality_auditor.gd")
const GunsmithRotationOrbitControlScript := preload("res://scripts/labs/gunsmith/gunsmith_rotation_orbit_control.gd")
const GunsmithAnimationAssetCatalogScript := preload("res://scripts/labs/gunsmith/gunsmith_animation_asset_catalog.gd")
const GunsmithRecomCatalogAdapter := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const OperatorComposureScript := preload("res://scripts/weapons/operator_composure.gd")
const PresentationRouterScript := preload("res://scripts/player/operator_presentation_router.gd")
const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")

const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"
const HAND_GIZMO_ARROW_LENGTH := 0.12
const HAND_GIZMO_RING_RADIUS := 0.09
const WEAPON_GIZMO_ARROW_LENGTH := 0.10
const WEAPON_GIZMO_RING_RADIUS := 0.075
const GIZMO_CENTER_RADIUS := 0.018
const GIZMO_PICK_DISTANCE_PX := 28.0
const MUZZLE_RETICLE_LEAD_PX := 64.0
const BULLET_VELOCITY_PREVIEW_SECONDS := 0.004
const MIN_BARREL_AXIS_LENGTH_METERS := 0.02
const EYE_ORIGIN_FORWARD_METERS := 0.13
const EYE_ORIGIN_HEIGHT_METERS := 0.09
const EYE_SIGHT_PICK_LENGTH_METERS := 0.5
const GUN_PLACEMENT_DIRECTION_HANDLE_METERS := 2.0
const TUNABLE_BODY_JOINTS := JointControlSchema.SELECTABLE_JOINTS
const MAX_GRIP_OFFSET_RADIUS_METERS := 0.75
const MAX_HAND_TO_GRIP_ERROR_METERS := 0.40

const JOINT_CHAIN_LINKS: Dictionary = {
	&"head": {&"neck": 0.55, &"spine2": 0.25, &"spine1": 0.10},
	&"neck": {&"spine2": 0.18},
	&"spine2": {&"spine1": 0.35, &"spine": 0.15},
	&"spine1": {&"spine": 0.25},
	&"left_upper_arm": {&"left_shoulder": 0.20},
	&"right_upper_arm": {&"right_shoulder": 0.20},
}
