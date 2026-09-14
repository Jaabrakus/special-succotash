# Original rifle idle versus ready selection

## Translation card — offline observer

- Intent: identify whether the original playable, rifle-equipped actor necessarily uses the `ready` variant of `Stand`.
- Acceptance: locate original mode storage, mode-name registration, selection and direct callers; execute bounded original selector instructions; state precisely what remains unverified.
- Owner: offline source-audit tool only.
- Must not change: gameplay animation map, assets, readiness grace, camera, movement/collision, server weapons, or other agents' files.
- Focused proof: `node tools/source_rifle_ready_selection_audit.cjs`; pinned original module hash, direct-call inventory and synthetic-input original-instruction fixtures.
- System delta: **MERGE evidence**, not a gameplay feature or activation. Preserve the semantic distinction between default, ready and firing clips; do not claim a new player policy from an AI caller. No runtime contract is changed by this observer.

## Result

The original engine has an explicit animation mode, stored at actor `+4918`, separate from its equipped weapon. The examined mode-changing path includes **AI awareness**, not an unconditional “rifle equipped” rule. This bounded audit does **not** establish the normal playable actor's final idle mode across a whole frame. Therefore neither “every armed player always uses ready” nor “every playable idle must use default” is proven here.

The existing extracted reader provides the clip names:

- `Seal anim set / Stand / modes / default`: `seal_stand`.
- `... / ready`: `seal_stand_alert01` and `seal_stand_alert02`, weights `0.5` each.
- `Fire stand`: separate `seal_fp_stand` action, not the `ready` mode.

Reader: `/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/readers/animset.rdr.json`, near line 2368. This mapping alone cannot establish the playable controller's choice.

## Original callable chain

ZSeal `0x57d710` stores mode `a1` into actor `+4918`, looks up every active action with `0x5e3c20(animset, action_type, mode)`, falls back to mode `0` when necessary, and replaces the active clip. It also requests the original transition snapshot/blend using the replacement clip's blend time.

```text
0x57d730 sh a1,4918(a0)
0x57d75c lh a2,4918(s1)
0x57d760 lw a0,1320(s1)
0x57d764 jal 0x5e3c20
0x57d768 daddu a1,s3,zero
```

`0x5e5970` searches the action's mode records by their byte-sized mode identifier. A single choice returns its packed clip index; multiple choices call the original RNG and accumulate the saved weights. No weapon-equipment test exists inside this mode lookup.

Only one direct `jal` to `0x57d710` occurs in the scanned original ZSeal/FTS modules: `0x58c5e4`, within wrapper `0x58c5d0`. That wrapper rejects negative mode identifiers. Its three direct callers (`0x56076c`, `0x5607a8`, `0x5607e8`) are inside controller function `0x5605a0`.

## Controller request values are not weapon kinds

Original registration at `0x574d40` and `0x574e68–0x574ed8` builds global table `0x66ad00`. String identities come from original bytes, not inferred names:

| Controller request | Registered mode |
| --- | --- |
| 0 | default identifier 0 |
| 1 | nominally bored02; setter randomizes into request 2 or 3 |
| 2 | `bored02` |
| 3 | `bored03` |
| 4 | `suspicious` |
| 5 | `ready` |
| 6 | `conversation` |

The original mode identifiers returned by `0x5e4f20` are runtime registration results; these controller request numbers must **not** be treated as literal actor `+4918` values.

At `0x570b70–0x570bc0`, a controller scalar at `+180` is compared against a five-entry threshold table at `0x65c700`. When the resulting level changes, `0x570c58–0x570cc0` restores the saved mode for level `0`, requests `suspicious` for level `1`, and requests `ready` for levels `2–4`. Adjacent registration strings identify AI difficulty/awareness context. This is evidence for a controller awareness path, not a proven accepted-shot timer or playable rifle-equipment latch.

```text
0x570c58 addiu a1,zero,4     # suspicious request
0x570c80 beq s2,v0,0x570ca8 # level 1
0x570ca8 jal 0x5604d0
0x570cb8 daddu a0,s3,zero   # levels 2,3,4
0x570cbc jal 0x5604d0
0x570cc0 addiu a1,zero,5     # ready request, delay slot
```

Changing an actor's animation set at `0x58c350` explicitly resets the mode before selecting an action:

```text
0x58c434 sw s2,1320(s3)
0x58c438 jal 0x58bcb0
0x58c43c sh zero,4918(s3)   # reset to default
```

## Integration decision and limits

Keep default, ready and firing as separate source routes. Do not replace every idle with `alert01/02` on the strength of “rifle equipped,” and do not describe the current custom `1.2`-second readiness grace as decoded original logic.

Remaining exact gap: a frame-by-frame original **playable** actor's animation-set/mode/action selection, including whether a different action or script changes the effective standing pose. The direct-call scan does not exclude computed indirect calls or module code outside the two pinned images. This audit does not execute a complete original game/controller frame.

## Reproduction

```sh
node tools/source_rifle_ready_selection_audit.cjs --output=/private/tmp/source-rifle-ready-selection-new.json
```

Fixtures run the original mode-record lookup with disclosed synthetic records and the original request-to-mode table-reading slice. They do not inject a live actor or assert which mode a playable character actually selects. No original game, runtime profile or animation asset is modified.

Observed 2026-09-13:

```text
SOURCE_RIFLE_READY_SELECTION PASS lookup=3 request_slices=6 unknown_stubs=0
```

Machine-readable report: `/private/tmp/source-rifle-ready-selection-20260913.json`. Node syntax and the scoped whitespace/diff check also passed. The exact source excerpts and direct-call addresses are persisted in the report.

Pinned ZSealEtc SHA-256: `cdb3fa8e707090ac879874e3987c6b7784808a4767e85d0e19fc6909d36549b1`.
