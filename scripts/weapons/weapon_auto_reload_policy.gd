class_name WeaponAutoReloadPolicy
extends RefCounted

## Shared trigger rule for local play and multiplayer presentation. Ammo transfer
## remains in each mode's authoritative reload completion path.


static func should_start(rounds_in_magazine: int, reserve_rounds: int, reload_pending: bool) -> bool:
	return rounds_in_magazine <= 0 and reserve_rounds > 0 and not reload_pending
