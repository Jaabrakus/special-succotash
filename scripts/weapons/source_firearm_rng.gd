extends RefCounted

## Original SCUS_972.75 0x197728 seed / 0x197740 rand; exact integer arithmetic.
## State ownership stays inside the accepted-shot ballistics call.
const ALGORITHM := "socom2_lcg64_rand31_v1"
var state: int = 1


func seed_from_u32(value: int) -> void:
	state = value & 0xffffffff


func next_raw() -> int:
	state = advance(state)
	return (state >> 32) & 0x7fffffff


static func advance(previous: int) -> int:
	# Four base-65536 limbs; largest intermediate is <2^35. No signed
	# multiplication overflow, float conversion or platform RNG dependency.
	var a := previous & 0xffff
	var b := (previous >> 16) & 0xffff
	var c := (previous >> 32) & 0xffff
	var d := (previous >> 48) & 0xffff
	var carry := a * 0x7f2d + 1
	var result := carry & 0xffff
	carry = (carry >> 16) + b * 0x7f2d + a * 0x4c95
	result |= (carry & 0xffff) << 16
	carry = (carry >> 16) + c * 0x7f2d + b * 0x4c95 + a * 0xf42d
	result |= (carry & 0xffff) << 32
	carry = (carry >> 16) + d * 0x7f2d + c * 0x4c95 + b * 0xf42d + a * 0x5851
	return result | ((carry & 0xffff) << 48)


static func signed_draw_pair(first: int, second: int) -> Vector2:
	# Original ADDIU raw,0xc0000001 then CVT.S.W and multiply2^-30.
	# CVT rounds at float32 before the exact power-of-two scaling. Vector2
	# components are float32 in the project's standard Godot build.
	var converted := Vector2(float((first & 0x7fffffff) - 0x3fffffff),
		float((second & 0x7fffffff) - 0x3fffffff))
	return converted * 0.0000000009313225746154785
