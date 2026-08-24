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
| Server snapshot rate | 20 Hz | Sends one authoritative world state every 50 ms. |
| Remote interpolation delay | 130 ms | Gives the client multiple snapshots to blend between. |
| Maximum extrapolation | 80 ms | Moves a remote player briefly along the last known velocity if a snapshot is late. |
| Snapshot history | 1.5 seconds | Stores recent remote states for interpolation. |
| Strafe direction change | 16.7 ms | Direction changes on the next physics frame. |
| Strafe opening burst | 2 frames at 1.18x | Makes the initial plant violent and readable. |
| Strafe burst decay | 120 ms | Smoothly reduces speed from 7.67 m/s to the sustained 6.5 m/s. |
| Reversal fatigue | Disabled | Every reversal gets the same burst and decay. |
| Locomotion animation blend | 75 ms | Keeps the visual direction change sharp without moving the authoritative body. |
| Simulated network latency | 0 ms | Remains disabled; packet delay must not stack with interpolation. |
| Transport-only rewind | 0–80 ms one way | Reduces real connection differences without removing the 130 ms lead window. |

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
jitter and prevents remote players from snapping between 20 Hz updates.

If the newest snapshot is late, the client can extrapolate the last known
velocity for no more than 80 ms. This is a small loss-recovery window. It is not
permission for the remote client to author movement.

## Does this make players lead shots?

The interpolation delay alone does not define shot behavior. Shot validation
defines it.

141 currently has these rules:

1. The local client sends bounded aim intent.
2. The server supplies the authoritative muzzle position.
3. The server performs an immediate hitscan ray against its current world.
4. The server measures round-trip time with opaque echo probes.
5. The server rewinds remote targets only by the measured one-way packet
   transit, capped at 80 ms.
6. The server does not rewind the authored 130 ms presentation delay.

Because the displayed remote target is approximately 130 ms in the past, a
laterally moving target can already be ahead of the body shown on the shooter's
screen when the server tests the ray. Transport-only rewind removes part of the
connection-dependent difference but intentionally preserves this common lead.

A rough estimate is:

```text
network lead distance ~= target lateral speed * 0.130 s
                         + uncompensated/capped transport variance
```

This is network lead. It is separate from physical projectile lead. The current
authoritative shot is hitscan. Saved muzzle velocity controls tracer
presentation and does not delay damage.

## Classic timing and compensated timing

141 can support two explicit shot-timing policies.

### 141 competitive timing

- Keep the 130 ms remote interpolation delay.
- Rewind targets only by measured packet transit, never by the authored buffer.
- Require players to learn some network lead against moving targets.
- Cap compensation and use regional matchmaking for high-latency connections.

This is the behavior of the current multiplayer slice.

### Compensated timing

- Keep the 130 ms interpolation delay for smooth movement.
- Store authoritative target position and hurtbox history on the server.
- Rewind targets to the time represented on the shooter's screen.
- Validate the hitscan shot against that historical server state.
- Restore the current server state after the query.

This lets a player aim at the target that was visibly presented without giving
the client authority over hits or damage. It can also produce the familiar
tradeoff where a player is hit shortly after reaching cover.

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
