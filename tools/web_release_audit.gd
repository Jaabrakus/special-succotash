extends SceneTree

## Inspects the actual standalone PCK directory, not export-log claims.
## Godot core/io/file_access_pack.cpp defines these v2/v3/v4 fields.
var problems: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--self-test" in args:
		assert(secret_reason("sb_" + "secret_" + "x".repeat(24)) != "")
		assert(secret_reason("sb_publishable_" + "x".repeat(24)) == "")
		var jwt := "eyJhbGciOiJIUzI1NiJ9." + Marshalls.utf8_to_base64('{"role":"service_role"}').trim_suffix("=") + ".signature"
		assert(secret_reason(jwt) != "")
		var anon := "eyJhbGciOiJIUzI1NiJ9." + Marshalls.utf8_to_base64('{"role":"anon"}').trim_suffix("=") + ".signature"
		assert(secret_reason(anon) == "")
		var test_policy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/web_release_policy.json"))
		for protected: String in ["config/supabase.json", "config/feature_contracts/example.json", "art_source/model.blend", "config/.env.production"]:
			var blocked := false
			for pattern: String in test_policy.forbidden_globs:
				blocked = blocked or protected.matchn(pattern)
			assert(blocked)
		assert(secret_reason("const SERVER_KEY_ENV = 'SOCOM_SUPABASE_SERVER_KEY'") == "")
		print("WEB_RELEASE_AUDIT self-test PASS")
		quit()
		return
	var path := args[0] if not args.is_empty() else "res://builds/web/index.pck"
	var policy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/web_release_policy.json"))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != 0x43504447:
		push_error("WEB_RELEASE_AUDIT invalid PCK")
		quit(1)
		return
	var version := file.get_32()
	file.seek(20)
	var flags := file.get_32()
	var base := file.get_64()
	if version not in [2, 3, 4] or flags & 1 or flags & 4:
		push_error("WEB_RELEASE_AUDIT unsupported/encrypted/sparse PCK; refuse uninspected release")
		quit(1)
		return
	file.seek(file.get_64() if version >= 3 else 96)
	var count := file.get_32()
	var paths: Dictionary = {}
	for i in count:
		var length := file.get_32()
		if length > 4096 or file.get_position() + length + 36 > file.get_length():
			problems.append("Malformed package directory")
			break
		var entry := file.get_buffer(length).get_string_from_utf8().trim_prefix("res://")
		var offset := file.get_64() + base
		var size := file.get_64()
		file.get_buffer(16)
		var entry_flags := file.get_32()
		var next := file.get_position()
		paths[entry] = true
		for pattern: String in policy.forbidden_globs:
			if entry.matchn(pattern):
				problems.append("Protected path: " + entry)
		if offset + size > file.get_length() or entry_flags != 0:
			problems.append("Unreadable entry: " + entry)
		elif entry.get_extension() in ["json", "cfg", "gd", "txt", "tscn", "tres"]:
			file.seek(offset)
			var reason := secret_reason(file.get_buffer(size).get_string_from_utf8())
			if reason != "":
				problems.append(reason + ": " + entry)
		# Release GDScript is compressed bytecode. Scan its corresponding source
		# before distribution as well, without printing matched secret values.
		if entry.ends_with(".gdc"):
			var source := "res://" + entry.trim_suffix("c")
			if not FileAccess.file_exists(source):
				problems.append("Cannot inspect compiled script source: " + entry)
			elif secret_reason(FileAccess.get_file_as_string(source)) != "":
				problems.append("Credential in compiled-script source: " + entry)
		file.seek(next)
	for required: String in policy.required_files:
		if not paths.has(required):
			problems.append("Missing runtime file: " + required)
	for problem in problems:
		push_error("WEB_RELEASE_AUDIT " + problem)
	print("WEB_RELEASE_AUDIT ", "PASS" if problems.is_empty() else "FAIL", " entries=", count, " findings=", problems.size())
	quit(0 if problems.is_empty() else 1)

func secret_reason(content: String) -> String:
	var token := RegEx.new()
	token.compile("sb_secret_[A-Za-z0-9_-]{16,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}")
	if token.search(content) != null:
		return "Recognizable secret"
	token.compile("eyJ[A-Za-z0-9_-]+\\.([A-Za-z0-9_-]+)\\.[A-Za-z0-9_-]+")
	for matched in token.search_all(content):
		var payload: String = matched.get_string(1).replace("-", "+").replace("_", "/")
		while payload.length() % 4 != 0:
			payload += "="
		var decoded: Variant = JSON.parse_string(Marshalls.base64_to_utf8(payload))
		if decoded is Dictionary and decoded.get("role", "") == "service_role":
			return "Privileged Supabase token"
	return ""
