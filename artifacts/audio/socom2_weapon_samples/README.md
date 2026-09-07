# SOCOM II weapon sound extraction — review pack

These are **recording-derived candidate cuts**, not original isolated sound-bank
assets. They are not enabled in the game. `.gdignore` excludes this review pack
from Godot imports and game exports.

## Translation card

- Player intent: identify each demonstrated weapon's sound so it can be connected
  to the matching game weapon.
- Acceptance: separate playable WAVs, explicit source time ranges, weapon labels,
  suggested catalog IDs only where names match, and no silent runtime changes.
- Owner: this offline extraction manifest. Existing `LabLeakAudioEngine` remains
  the sole gameplay sound consumer; no new gameplay audio owner is introduced.
- Protected: gameplay sounds, acoustic propagation, shots/damage, animation,
  recoil, reticle, balance, multiplayer, browser build, and original CC0 assets.
- Proof: WAV-format, duration, clipping, hash, source-range, catalog-ID, and ZIP
  integrity checks. Listening approval and live mix checks remain outstanding.

## Contents and use

- `gunshots/`: separately named firearm or launcher samples. Suppressed versions
  remain separate. The SOCOM I M82A1A alternative is explicitly labeled.
- `throwables/`: M67 frag, Mk. III A2 HE, flashbang, and a smoke-onset candidate.
- `manifest.json`: source URL, user-confirmed permission, exact cut times,
  suggested weapon IDs, processing, hashes, and review status.
- `evidence/`: sampled before/after frames and detected source title cards.
  These support identification, not an assertion of clean audio isolation.

The runtime selection should eventually use the equipped `weapon_id` to choose
an approved clip through the existing audio engine and acoustic propagation.
Do not choose solely by weapon class: an unsuppressed Mk. 23 must not use its
suppressed counterpart. A launcher firing sound is not its impact explosion.

Example manifest contract:

```json
{
  "runtime_enabled": false,
  "quality_status": "candidate cuts; listening review required"
}
```

## Quality limits

The video has baked-in ambience, mechanics, and reverb. The short clips preserve
the recording's relative levels; they have not been aggressively normalized or
denoised. A short fade at each edge prevents cut clicks. The smoke sample needs
particular care: it may contain handling or movement noise, not an isolated hiss.

The video's ammunition counter does not consistently decrease around the
selected events. Timing therefore uses section identity and repeated audio
transients, not a claimed one-bullet counter validation. No listening review has
been claimed. Review the attack and tail before promoting any clip into runtime.

The three shotguns shown are Jackhammer, SPAS-12, and Mossberg 590. None is silently
mapped to our Remington 870. Similarly, no M46 sample is invented. The video's
M14 label identifies a Mini-14 model; verify that match before using it.

C4, mines, satchel, red smoke, designator, vision toggles, and knife sounds have
not been isolated in this pass. See `not_extracted` in the manifest.

## System-delta decision

**KEEP the current runtime until listening review; retain this pack as a candidate.**
Scores are 0–5 and concern readiness as gameplay audio, not legal clearance.

| Criterion | Current runtime | Candidate pack | Evidence |
| --- | ---: | ---: | --- |
| Correctness | 2 | 2 | `scripts/audio/lab_leak_audio_engine.gd:63` uses two generic shot streams; `manifest.json` identifies weapons but marks review pending. |
| Ownership clarity | 5 | 5 | Existing audio engine remains untouched; `runtime_enabled` is false. |
| Runtime parity | 5 | 0 | Current engine runs; this `.gdignore` review pack deliberately does not. |
| Editor usability | 2 | 3 | Individually named WAVs and source ranges are inspectable; no runtime editor selector is added. |
| Performance | 5 | 0 | Existing engine caches streams; this pack has not been integrated or profiled. |
| Regression coverage | 4 | 2 | Existing audio regressions remain unchanged; pack checks cover file integrity, not audible quality. |

No gameplay feature is claimed complete or added, so this offline review pack
does not introduce a gameplay feature contract. Promotion will require the shared
audio-bank contract, focused playback regressions, and a listening/mix check.
