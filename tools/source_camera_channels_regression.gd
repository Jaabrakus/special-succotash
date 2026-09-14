extends SceneTree

const Channels := preload("res://scripts/player/operator_source_camera_channels.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_expect(Channels.data().size() == 285, "all285 independent keyed source roots retained")
	var library := AnimationLibrary.new()
	for name in ["seal_stand", "seal_stand_alert02", "seal_crouch", "seal_prone", "seal_run"]:
		var clip := load("res://assets/animations/seal_reference/"+name+".tres") as Animation
		library.add_animation(name, clip)
		var descriptor := Channels.describe(clip)
		_expect(not descriptor.is_empty(), name+" exact source provenance")
		var row: Dictionary = Channels.data()[name]
		for fraction in [0.0,.5,1.0]:
			var index := minf(float(row.frames)*fraction,row.positions_raw.size()-1)
			var expected_raw: Array = row.positions_raw[int(index)]
			var next_raw: Array = row.positions_raw[mini(int(index)+1,row.positions_raw.size()-1)]
			var actual := Channels.sample(descriptor,clip.length*fraction)
			var expected := Vector3(expected_raw[0],expected_raw[1],expected_raw[2]).lerp(Vector3(next_raw[0],next_raw[1],next_raw[2]),index-floorf(index))/256.0
			_expect(actual.distance_to(expected) < .00001, name+" early/middle/late exact samples")
	var unsupported := Animation.new()
	var dive := load("res://assets/animations/seal_gameplay/seal_dive_to_prone.tres") as Animation
	var dive_source := load("res://assets/animations/seal_reference/seal_dive2prone.tres") as Animation
	library.add_animation("dive", dive)
	var dive_descriptor := Channels.describe(dive)
	var dive_row: Dictionary = Channels.data()["seal_dive2prone"]
	var retained_end := float(dive_row.duration) * (float(dive_row.frames)-1.0) / float(dive_row.frames)
	_expect(absf(float(dive_descriptor.end)-retained_end)<.000001,"trimmed dive observer excludes duplicate upright closure")
	_expect(absf(Channels.sample(dive_descriptor,dive.length).y-2.125)<.00001,"trimmed dive ends on retained prone root")
	_expect(absf(Channels.sample(Channels.describe(dive_source),dive_source.length).y-9.76171875)<.00001,"untrimmed source still retains its original closing sample")
	for index in 16:
		var row: Array = dive_row.positions_raw[index]
		var time := dive.length * float(index) / 15.0
		_expect(Channels.sample(dive_descriptor,time).distance_to(Vector3(row[0],row[1],row[2])/256.0)<.00001,"trimmed body and observer preserve identical source sample clock")
	library.add_animation("unsupported",unsupported)
	var mutable_jump := unsupported.duplicate() as Animation
	mutable_jump.set_meta("operator_mutable_jump",true)
	library.add_animation("jump_local",mutable_jump)
	var a := Skeleton3D.new()
	var b := Skeleton3D.new()
	root.add_child(a)
	root.add_child(b)
	a.add_bone("mixamorig_Hips")
	b.add_bone("mixamorig_Hips")
	var copy_a := Channels.augment(library,a)
	var copy_b := Channels.augment(library,b)
	_expect(a.get_bone_count()==1 and b.get_bone_count()==1,"no added skinned bone")
	_expect(a.get_node("SourceCameraAnchor")!=b.get_node("SourceCameraAnchor"),"operators have independent observations")
	for name in library.get_animation_list():
		var source := library.get_animation(name)
		var result := copy_a.get_animation(name)
		_expect(source.get_track_count()+2==result.get_track_count(),str(name)+" append only2 observer tracks")
		_expect((copy_b.get_animation(name)==result) == (name!=&"jump_local"),"immutable clips shared but mutable jumps remain player-local")
		_expect(source!=result,"original source never mutated")
		for track in source.get_track_count():
			_expect(source.track_get_path(track)==result.track_get_path(track),"existing track path unchanged")
			for key in source.track_get_key_count(track):
				_expect(source.track_get_key_value(track,key)==result.track_get_key_value(track,key),"body pose unchanged")
				_expect(source.track_get_key_time(track,key)==result.track_get_key_time(track,key),"body timing unchanged")
		var coverage := result.find_track(Channels.COVERAGE_PATH,Animation.TYPE_VALUE)
		_expect(result.track_get_key_value(coverage,0)==(0.0 if name in [&"unsupported",&"jump_local"] else 1.0),"coverage resets unsupported source")
	var pistol := load("res://assets/animations/seal_gameplay/pistol_crouch_forward.tres") as Animation
	_expect(Channels.describe(pistol).get("name")=="seal_crouchwalk","sparse source uses explicit phase-matched composite base")
	var jump := load("res://assets/animations/seal_gameplay/jump_coherent_run.tres") as Animation
	_expect(not Channels.describe(jump).is_empty(),"source jump resolves existing bounded window")
	a.free()
	b.free()
	print("SOURCE_CAMERA_CHANNELS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _expect(value: bool,label: String) -> void:
	checks+=1
	if not value and not label in failures: failures.append(label)
