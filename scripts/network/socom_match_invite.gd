class_name SocomMatchInvite
extends RefCounted

## Compact direct-IP invite codes. The code contains an IPv4 address, UDP port,
## and checksum. It is not a password and does not bypass router/firewall rules.

const PREFIX := "141"
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const PAYLOAD_CHARACTERS := 10
const CHECKSUM_CHARACTERS := 2


static func create_for_host(port: int) -> Dictionary:
	return encode(best_host_address(), port)


static func encode(address: String, port: int) -> Dictionary:
	var octets := _ipv4_octets(address)
	if octets.size() != 4:
		return {"ok": false, "message": "Invite codes need an IPv4 host address."}
	if port < 1 or port > 65535:
		return {"ok": false, "message": "Invite port is outside the valid range."}
	var payload := 0
	for octet: int in octets:
		payload = (payload << 8) | octet
	payload = (payload << 16) | port
	var compact := _encode_base32(payload, PAYLOAD_CHARACTERS) + _encode_base32(_checksum(payload), CHECKSUM_CHARACTERS)
	return {
		"ok": true,
		"code": "%s-%s-%s-%s" % [PREFIX, compact.substr(0, 4), compact.substr(4, 4), compact.substr(8, 4)],
		"address": address,
		"port": port,
	}


static func decode(code: String) -> Dictionary:
	var compact := _normalize_code(code)
	if not compact.begins_with(PREFIX) or compact.length() != PREFIX.length() + PAYLOAD_CHARACTERS + CHECKSUM_CHARACTERS:
		return {"ok": false, "message": "Invite code format is invalid."}
	compact = compact.substr(PREFIX.length())
	var payload := _decode_base32(compact.substr(0, PAYLOAD_CHARACTERS))
	var supplied_checksum := _decode_base32(compact.substr(PAYLOAD_CHARACTERS, CHECKSUM_CHARACTERS))
	if payload < 0 or supplied_checksum < 0 or supplied_checksum != _checksum(payload):
		return {"ok": false, "message": "Invite code is invalid or mistyped."}
	var port := payload & 0xFFFF
	var packed_address := payload >> 16
	var address := "%d.%d.%d.%d" % [
		(packed_address >> 24) & 0xFF,
		(packed_address >> 16) & 0xFF,
		(packed_address >> 8) & 0xFF,
		packed_address & 0xFF,
	]
	return {"ok": port > 0, "address": address, "port": port, "code": code}


static func parse(value: String, default_port: int) -> Dictionary:
	var clean := value.strip_edges()
	if clean.is_empty():
		return {"ok": false, "message": "Enter an invite code or server address."}
	var normalized := _normalize_code(clean)
	if clean.to_upper().begins_with(PREFIX + "-") or normalized.length() == 15 and normalized.begins_with(PREFIX):
		return decode(clean)
	var address := clean
	var port := default_port
	if clean.count(":") == 1:
		var separator := clean.rfind(":")
		var port_text := clean.substr(separator + 1)
		if port_text.is_valid_int():
			address = clean.substr(0, separator).strip_edges()
			port = int(port_text)
	if address.is_empty() or port < 1 or port > 65535:
		return {"ok": false, "message": "Server address or port is invalid."}
	return {"ok": true, "address": address, "port": port}


static func best_host_address() -> String:
	var configured := OS.get_environment("SOCOM_INVITE_ADDRESS").strip_edges()
	if _ipv4_octets(configured).size() == 4:
		return configured
	var fallback := ""
	for candidate: String in IP.get_local_addresses():
		var octets := _ipv4_octets(candidate)
		if octets.size() != 4 or octets[0] == 127 or (octets[0] == 169 and octets[1] == 254):
			continue
		if _is_private_ipv4(octets):
			return candidate
		if fallback.is_empty():
			fallback = candidate
	return fallback if not fallback.is_empty() else "127.0.0.1"


static func _ipv4_octets(address: String) -> Array[int]:
	var result: Array[int] = []
	var parts := address.split(".")
	if parts.size() != 4:
		return result
	for part: String in parts:
		if not part.is_valid_int():
			return []
		var value := int(part)
		if value < 0 or value > 255:
			return []
		result.append(value)
	return result


static func _is_private_ipv4(octets: Array[int]) -> bool:
	return (
		octets[0] == 10
		or (octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31)
		or (octets[0] == 192 and octets[1] == 168)
	)


static func _normalize_code(code: String) -> String:
	return code.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")


static func _checksum(payload: int) -> int:
	return (payload ^ (payload >> 10) ^ (payload >> 20) ^ (payload >> 30) ^ (payload >> 40) ^ 0x141) & 0x3FF


static func _encode_base32(value: int, width: int) -> String:
	var encoded := ""
	var remaining := value
	for _index in width:
		encoded = ALPHABET[remaining & 31] + encoded
		remaining >>= 5
	return encoded


static func _decode_base32(encoded: String) -> int:
	var value := 0
	for character: String in encoded:
		var digit := ALPHABET.find(character)
		if digit < 0:
			return -1
		value = (value << 5) | digit
	return value
