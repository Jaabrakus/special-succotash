class_name SocomRoundPolicy
extends RefCounted

## Pure rules: no RPCs, player nodes, timers or presentation state.
static func advance_clock(remaining: float, shown_second: int, delta: float,
		can_advance: bool, timeout_result: String) -> Dictionary:
	if not can_advance:
		return {"remaining": remaining, "shown": shown_second, "broadcast": false, "expired": false, "winner": -1}
	var next := maxf(0.0, remaining - delta)
	var shown := ceili(next)
	return {"remaining": next, "shown": shown, "broadcast": shown != shown_second,
		"expired": next <= 0.0, "winner": 0 if timeout_result == "alpha" else 1 if timeout_result == "bravo" else -1}

static func match_complete(winner: int, wins: Dictionary, round_index: int, rules: Dictionary) -> bool:
	return (winner in [0, 1] and int(wins.get(winner, 0)) >= int(rules.get("rounds_to_win", 4))) \
		or round_index >= int(rules.get("maximum_rounds", 7))
