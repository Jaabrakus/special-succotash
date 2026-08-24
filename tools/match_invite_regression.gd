extends SceneTree

const MatchInvite := preload("res://scripts/network/socom_match_invite.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var encoded: Dictionary = MatchInvite.encode("192.168.14.27", 14141)
	_expect(bool(encoded.get("ok", false)), "IPv4 host and UDP port create an invite code")
	var code := String(encoded.get("code", ""))
	_expect(code.begins_with("141-") and code.length() == 18, "invite code is short and grouped for humans")
	var decoded: Dictionary = MatchInvite.decode(code.to_lower())
	_expect(String(decoded.get("address", "")) == "192.168.14.27", "invite code restores the host address")
	_expect(int(decoded.get("port", 0)) == 14141, "invite code restores the host port")
	var parsed_code: Dictionary = MatchInvite.parse(code, 9999)
	_expect(bool(parsed_code.get("ok", false)) and int(parsed_code.get("port", 0)) == 14141, "join parsing accepts invite codes")
	var parsed_address: Dictionary = MatchInvite.parse("example.test:15555", 14141)
	_expect(String(parsed_address.get("address", "")) == "example.test" and int(parsed_address.get("port", 0)) == 15555, "join parsing still accepts server addresses with ports")
	var corrupted := code.left(code.length() - 1) + ("0" if not code.ends_with("0") else "1")
	_expect(not bool(MatchInvite.decode(corrupted).get("ok", false)), "checksum rejects a mistyped invite code")
	if failures.is_empty():
		print("MATCH_INVITE_REGRESSION PASS")
		quit(0)
	else:
		push_error("MATCH_INVITE_REGRESSION FAIL %s" % failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
