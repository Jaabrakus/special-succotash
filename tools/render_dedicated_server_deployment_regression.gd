extends SceneTree

const DOCKERFILE_PATH := "res://deploy/server/Dockerfile"
const DOCKERIGNORE_PATH := "res://deploy/server/Dockerfile.dockerignore"
const START_SCRIPT_PATH := "res://deploy/server/start_server.sh"
const RENDER_BLUEPRINT_PATH := "res://deploy/server/render.dedicated.yaml"
const RULESET_MIGRATION_PATH := (
	"res://supabase/migrations/20260902003000_seed_gunfight_ruleset.sql"
)

var failures: Array[String] = []


func _initialize() -> void:
	var dockerfile := FileAccess.get_file_as_string(DOCKERFILE_PATH)
	var dockerignore := FileAccess.get_file_as_string(DOCKERIGNORE_PATH)
	var start_script := FileAccess.get_file_as_string(START_SCRIPT_PATH)
	var blueprint := FileAccess.get_file_as_string(RENDER_BLUEPRINT_PATH)
	var migration := FileAccess.get_file_as_string(RULESET_MIGRATION_PATH)

	_expect(
		dockerfile.contains("ARG GODOT_VERSION=4.7.1")
		and dockerfile.contains("c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba")
		and dockerfile.contains("sha256sum --check --strict"),
		"container pins the verified Godot 4.7.1 Linux artifact"
	)
	_expect(
		dockerfile.contains("USER socom")
		and dockerfile.contains("install -d --owner=socom --group=socom /srv/socom/.godot")
		and dockerfile.contains("/^\\[editor_plugins\\]$/,/^$/d")
		and dockerfile.contains("--recovery-mode")
		and dockerfile.contains("--import")
		and dockerfile.contains("ENTRYPOINT"),
		"container imports once and runs as an unprivileged user"
	)
	_expect(
		dockerignore.contains("config/supabase.json")
		and dockerignore.contains("assets/characters/*")
		and dockerignore.contains("assets/external/*")
		and dockerignore.contains("military_tactical_suit_safe_scale.glb"),
		"container excludes the ignored local Supabase configuration"
	)
	_expect(
		start_script.contains("${PORT:-${SOCOM_SERVER_PORT:-10000}}")
		and start_script.contains("RENDER_EXTERNAL_HOSTNAME")
		and start_script.contains("wss://${RENDER_EXTERNAL_HOSTNAME}")
		and start_script.contains("--mp-transport=websocket")
		and start_script.contains("--tournament-32"),
		"entrypoint binds the host port and advertises its secure WebSocket endpoint"
	)
	_expect(
		start_script.contains("SOCOM_SUPABASE_SERVER_KEY is not configured")
		and start_script.contains("SOCOM_RULESET_ID is not configured"),
		"entrypoint fails closed when privileged registration inputs are missing"
	)
	_expect(
		blueprint.contains("runtime: docker")
		and blueprint.contains("plan: 1c-2g")
		and blueprint.contains("region: virginia")
		and blueprint.contains("autoDeployTrigger: off")
		and blueprint.contains("SOCOM_SUPABASE_SERVER_KEY")
		and blueprint.contains("sync: false"),
		"Render blueprint requests always-on capacity and dashboard-only secret injection"
	)
	_expect(
		migration.contains("14100000-0000-4000-8000-000000000001")
		and migration.contains("'gunfight_2v2'")
		and migration.contains("'0.1.0'")
		and migration.contains("'active'"),
		"database migration seeds the exact ruleset identity used by the server"
	)

	if failures.is_empty():
		print("RENDER_DEDICATED_SERVER_DEPLOYMENT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RENDER_DEDICATED_SERVER_DEPLOYMENT_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("RENDER_DEPLOYMENT_CHECK PASS ", label)
	else:
		failures.append(label)
