extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const Ambience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const Assets := preload("res://scripts/maps/socom_map_asset_library.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/maps/jungle_village_placement.json"))
	var source := Maps.load_path(spec["source_map"])
	var document := Maps.load_path(spec["library_path"])
	_expect(Commands.validate_document(document).get("ok",false),"valid editor contract")
	_expect(Maps.normalize(JSON.parse_string(JSON.stringify(document)))==document,"save roundtrip")
	var by_id := {}
	var plants := 0
	var spawns: Array[Vector3] = []
	for object: Dictionary in source["objects"]:
		if String(object["type"]).ends_with("spawn"): spawns.append(Maps.data_to_vector(object["position"]))
	for object: Dictionary in document["objects"]:
		by_id[object["id"]] = object
		if not String(object["id"]).begins_with("jungle_"): continue
		plants += 1
		_expect(object["properties"]["collision_mode"]=="none","nonblocking leaf geometry")
		var p := Maps.data_to_vector(object["position"])
		for spawn in spawns:
			_expect(Vector2(p.x,p.z).distance_to(Vector2(spawn.x,spawn.z))>=12,"clear spawn radius")
	for object: Dictionary in source["objects"]:
		_expect(by_id.get(object["id"],{})==object,"original geometry and markers preserved")
	_expect(plants>=100,"substantial vegetation placement")
	var asset := Assets.instantiate_asset("user://map_assets/mp64_fern01.glb")
	_expect(asset.get("ok",false),"fern loads")
	var fern: Node3D = asset["scene"]
	var material: BaseMaterial3D = (fern.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh.surface_get_material(0)
	_expect(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,"GLB mask reaches Godot cutout material")
	var image := material.albedo_texture.get_image()
	var clear := 0
	var solid := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a<0.5: clear += 1
			else: solid += 1
	_expect(clear>0 and solid>0,"texture retains both leaf and clear pixels")
	fern.free()
	var host := Node3D.new()
	root.add_child(host)
	Ambience.build_into(host,document)
	var built := Runtime.build_into(host,document,false)
	await physics_frame
	await physics_frame
	for child in built.get_children():
		if String(child.get_meta("map_object_id","")).begins_with("jungle_"):
			_expect(child.find_children("*","CollisionShape3D",true,false).is_empty(),"no leaf-card collision")
	for object: Dictionary in document["objects"]:
		if not String(object["id"]).begins_with("jungle_"): continue
		var p := Maps.data_to_vector(object["position"])
		var hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.2,p-Vector3.UP*.4,1))
		_expect(not hit.is_empty(),"vegetation rests on canonical geometry")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size=Vector2i(1600,1000)
		var cam := Camera3D.new()
		host.add_child(cam)
		cam.position=Vector3(210,170,210)
		cam.look_at(Vector3(90,8,78))
		cam.current=true
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/jungle-village-overview.png")
		cam.position=Vector3(64,24,114)
		cam.look_at(Vector3(85,16,100))
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/jungle-village-street.png")
	host.free()
	if failures==0: print("JUNGLE_VILLAGE_REGRESSION PASS: %d plants, original preserved, cutouts, save/runtime parity, ground support and clear spawns" % plants)
	quit(0 if failures==0 else 1)
func _expect(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error("JUNGLE_VILLAGE_REGRESSION FAIL: "+message)
