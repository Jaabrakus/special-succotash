class_name SocomSessionCompatibility
extends RefCounted

## Stable admission contract for the ENet session. A peer must match both the
## wire protocol and the complete game build before it can enter the lobby.

const PROTOCOL_VERSION := 1
const MAX_BUILD_LENGTH := 80


static func local_build() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "development")).strip_edges()


static func admission(protocol_version: int, game_build: String) -> Dictionary:
	var clean_build := game_build.strip_edges()
	if protocol_version != PROTOCOL_VERSION:
		return {
			"ok": false,
			"code": "PROTOCOL_MISMATCH",
			"message": "Connection rejected: network protocol %d is required." % PROTOCOL_VERSION,
		}
	if clean_build.is_empty() or clean_build.length() > MAX_BUILD_LENGTH:
		return {
			"ok": false,
			"code": "INVALID_BUILD",
			"message": "Connection rejected: the client build identifier is invalid.",
		}
	var required_build := local_build()
	if clean_build != required_build:
		return {
			"ok": false,
			"code": "BUILD_MISMATCH",
			"message": "Connection rejected: install game build %s." % required_build,
		}
	return {"ok": true, "code": "ADMITTED", "message": "Session build accepted."}
