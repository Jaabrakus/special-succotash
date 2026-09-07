# 141 Network Interpolation and Shot Timing

## Purpose

141 uses a short remote-player history to make online movement stable when
packets arrive at uneven times. The client renders remote players 130 ms behind
the newest known server state and blends between stored snapshots.

This is a presentation delay. It is not simulated ping. It does not delay the
local player's input.

## Current values

| Setting | Current value | Function |
| --- | ---: | --- |
| Server snapshot rate | 60 Hz | Sends one authoritative world state every 16.7 ms (1.0 / 60.0). |
| Remote interpolation delay | 130 ms | Gives the client multiple snapshots to blend between. |
| Maximum extrapolation | 80 ms | Moves a remote player briefly along the last known velocity if a snapshot is late. |
| Snapshot history | 1.0 seconds | Stores recent authoritative and remote states for interpolation and rewind. |
| Strafe direction change | 16.7 ms | Direction changes on the next physics frame. |
| Strafe opening burst | 2 frames at 1.18x | Makes the initial plant violent and readable. |
| Strafe burst decay | 120 ms | Smoothly reduces speed from 7.67 m/s to the sustained 6.5 m/s. |
| Reversal fatigue | Disabled | Every reversal gets the same burst and decay. |
| Locomotion animation blend | 75 ms | Keeps the visual direction change sharp without moving the authoritative body. |
| Simulated network latency | 0 ms | Remains disabled; packet delay must not stack with interpolation. |
| Transport-only rewind | 0–80 ms one way | Used for baseline transport-only assertions. |
| Compensated combat rewind | Transport + 130 ms buffer | Unwinds remote presentation buffer during live hitscan raycasts to match shooter screen. |

The current implementation is in:

- `scripts/network/socom_multiplayer_slice.gd`
- `scripts/network/socom_network_operator.gd`

## What the player sees

The local player responds immediately through local prediction. A remote player
is shown at this render time:

```text
remote render time = current time - 130 ms
```

The client selects two server snapshots around that time and blends position,
yaw, velocity, posture, health, and alive state. This hides ordinary packet
jitter and provides fluid rendering between 60 Hz updates.

If the newest snapshot is late, the client can extrapolate the last known
velocity for no more than 80 ms. This is a small loss-recovery window. It is not
permission for the remote client to author movement.

## Does this make players lead shots?

The interpolation delay alone does not define shot behavior. Shot validation
defines it.

141 implements full **Compensated Timing** for live combat shot processing:

1. The local client sends bounded aim intent.
2. The server supplies the authoritative muzzle position.
3. The server rewinds remote targets by total shot compensation: the measured
   one-way packet transit (capped at 80 ms) plus the 130 ms remote presentation
   interpolation delay via `_total_shot_compensation_seconds()`.
4. The server performs the hitscan ray against the rewound world state matching
   the shooter's visual frame.
5. The server restores current authoritative world state immediately after the query.
6. Transport-only rewind (`include_presentation_buffer = false`) remains supported
   for legacy transport regression assertions.

Because the server rewinds both network transit and presentation delay during
live shot queries, players can aim directly at visible character models with zero
artificial network lead, matching single-player local feel.

This is distinct from physical projectile travel. The current authoritative shot
is hitscan. Saved muzzle velocity controls tracer presentation and does not
delay damage.

## Classic timing and compensated timing

141 supports two shot-timing modes:

### Classic / transport-only mode

- Keep the 130 ms remote interpolation delay.
- Rewind targets only by measured packet transit, excluding the presentation buffer.
- Used in regression tests (`tools/multiplayer_slice_regression.gd`).

### Modern compensated timing (Default in live combat)

- Keep the 130 ms interpolation delay for smooth movement.
- Store authoritative target position and hurtbox history on the server (1.0 s window).
- Rewind targets by `_total_shot_compensation_seconds()` (transit + presentation delay) in `_server_process_shot()`.
- Validate the hitscan shot against that historical server state.
- Restore the current server state after the query.

This lets a player aim directly at the target that was visibly presented without
giving the client authority over hits or damage.

## Historical context

Interpolation, prediction, and server rewind are not obsolete techniques. Many
modern online action games still use them. The values and policies vary by
game, server rate, expected latency, weapon model, and fairness target.

Early online shooters often operated with lower update rates and less complete
latency compensation. That made prediction, interpolation, and player-learned
shot leading more visible. This makes the current 141 behavior consistent with
an early broadband tactical-shooter feel.

No public technical source has been found that proves a specific older console
shooter used exactly a 130 ms interpolation buffer or the same shot-validation
policy. Treat that connection as design inspiration, not a verified recreation
of another game's network code.

General historical references:

- [Game Developer Magazine, June 2001: latency compensation methods](https://media.gdcvault.com/GD_Mag_Archives/GDM_June_2001.pdf)
- [Valve: Source multiplayer networking and server rewind](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking)

## 141 authority boundary

The following rules apply to both timing policies:

- The server owns movement, muzzle validation, hit queries, hurtboxes, damage,
  score, and respawn.
- The client sends input and aim intent. It does not send final hit results.
- The camera and reticle remain local presentation systems.
- Animation and procedural pose do not move the authoritative body.
- The network replicates gameplay state and intent, not full skeleton poses.

## Public-server timing

The server now sends recurring opaque time probes. It measures each peer's
round trip without trusting a client-reported ping. Clients use the returned
sample to translate server snapshot timestamps onto their local interpolation
timeline. The server uses half of the smoothed round trip for transport-only
rewind, capped at 80 ms.

The public test also needs measurements for:

- 30, 60, 100, 150, and 250 ms round-trip latency;
- 0%, 1%, 3%, and 5% packet loss;
- steady and burst jitter;
- target movement across the shooter's aim line;
- shots near cover edges;
- crouch and prone hurtbox transitions.

## Recommended product choice

Keep the 130 ms interpolation buffer in the competitive ruleset. Do not enable
the unused simulated packet-latency field. Ranked servers must publish the same
buffer, transport-compensation cap, burst, and fatigue values in their ruleset
hash so every player receives the same timing model.
