# The Square — 141 lore and design language

Status: lore design document, v1 (2026-08-27). Fiction only; nothing in this
document is implemented unless a later checkpoint says so.

## The inspiration boundary

The Sator Square is a genuine Roman palindrome square — attested at Pompeii,
Dura-Europos, and elsewhere; its original meaning is a 2,000-year-old open
question. It belongs to no one. Christopher Nolan's *Tenet* (2020) used the
same five words as character and place names, wrapped in a story of temporal
inversion.

141 takes the **artifact**, not the film:

- Taken: the square itself, the five Latin words and their real meanings,
  symmetry, mirrored geometry, restrained monospaced typography, the mood of
  a charm whose purpose was forgotten.
- Refused: time inversion or rewind mechanics in any form; the film's
  character names and relationships; any organization named for the square's
  center word; "red means forward, blue means backward" as a temporal code;
  plot structures derived from the film.

The shared sentence between 141 and the film ends at the square's edge. This
note exists so later contributors know exactly where that line is drawn.

## The palindrome already in the name

141 reads identically forwards and backwards. The project's own designation
is a two-digit palindrome bracketing a spine. In-lore, this is not a
coincidence: **141 is the signature of the Square** — the smallest number
that holds its shape when the world turns over. Operators, maps, and match
records all carry numbers and names that read both ways, and players who
notice the pattern were meant to.

## The artifact in the fiction

The square was found cut into a wall of a demolished compound during the
cleanup of an operation nobody officially names. Five words, five rows, one
property: it does not change when the world rotates around it. A subsequent
program gave its cells to five small, deniable task teams — and its center
to the thing they fight over.

In the league's own language:

> Two faces meet at one square. The sower plants, the wheels turn, the
> nameless watch, the work is done, and what is held decides who writes
> the report.

## The two faces (team names)

The square has exactly two paired axes. Each match is one axis — two words
that are the same word, read from opposite ends:

| Axis | Face one | Face two | Flavor |
| --- | --- | --- | --- |
| Default | **SATOR** (row 1) | **ROTAS** (row 5) | The beginning against the end |
| Alternate | **AREPO** (row 2) | **OPERA** (row 4) | The riddle against the craft |

- Match team identifiers in code remain `0` and `1`; the words are a
  presentation and lore layer, selected per match (deterministic from the
  match seed) or fixed to the default axis in settings.
- Colors stay as shipped: blue (Alpha/SATOR) and red (Bravo/ROTAS). The red
  and blue carry no temporal meaning — they are simply the two faces.
- **TENET never takes a side.** The center word belongs to what both faces
  contest: the objective, the bomb, the overtime flag, and — at tournament
  scale — the league itself.

## The five words as five Houses (tournament lore)

For competitive play, every entered team swears to one of five Houses. The
Houses are derived from the actual Latin senses of the words — doctrines of
play, not factions of a plot:

| House | Latin sense | Doctrine | Signature play |
| --- | --- | --- | --- |
| **SATOR** | sower, planter | Strike first and shape the ground. | Opening aggression, entry frags, the plant |
| **AREPO** | a name antiquity never translated | See without being seen. | Recon, patience, information denial |
| **TENET** | he holds | The round ends on my terms, not yours. | Anchor play, site holds, clock discipline |
| **OPERA** | work, care, craft | Win by preparation. | Utility, demolitions, gadget play |
| **ROTAS** | wheels | Never be where you were last seen. | Rotations, flanks, tempo swings |

House affiliation is flavor: it colors team pages, bracket names, and match
announcements ("SATOR queries ROTAS"). It never gates content or mechanics.

## The Tenet — the held word (the prize)

The center word never takes a side; it is the thing **won** — and the winner
does not merely receive it. **The champion is the Tenet.** They occupy the
center cell of the Square for as long as they hold.

- **Match scale:** TENET is the contested objective — in Gunfight, the
  overtime flag (a team wins the round by standing in it, which is to say:
  by holding it); in Demolition, the planted charge that decides the round.
- **Tournament scale:** squads enter as orbiting words — a House, a face of
  an axis. The final's last two faces contest the center, and the winner
  stops being a side: for the length of their reign, the squad *is* the
  Tenet, and the four Houses orbit them. The bracket resolves into the
  glyph — four words around one held center.
- **Broadcast language:** "TENET HELD BY SATOR." A title defense is a
  "hold"; a dynasty is "a long hold"; losing the final is "the hold is
  broken." The league's honor roll is **the Hold** — the list of every
  squad that has been the Tenet.

Distinction from the film, made explicit: *Tenet* (2020) uses the word as
the name of an organization. 141 uses it as the object and the title — the
word's real meaning ("he holds"), not theirs. The earlier rule stands
unchanged: the center word is never a brand, a team, or a faction. It is
only ever held — and the squad holding it is, for that reign, the Tenet.

- **Maps are palindromes**: RADAR, CIVIC, KAYAK, ROTATOR, REVIVER, DEIFIED.
  Every authored map's codename reads the same both ways.
- **Operator call-signs are palindromic numerics**: 141, 242, 353, 484, 525,
  616… Every operator's number holds under rotation.
- **A match is an Axis.** A round is a **Turn**. A tournament is **the
  Square** — a 16-team bracket draws the square four times. The trophy is
  **the Tenet**; champions are its Holders.
- **Scoreboards speak in pairs**: "SATOR 4 — ROTAS 2", never winner-first
  until the match is decided; the square does not read in one direction.

## Visual language

- The 5×5 grid is the league sigil; the two axis words are typeset as
  mirrored pairs (SATOR over ROTAS, one rotated 180 degrees) on split
  screens, loadout screens, and the tournament bracket.
- Monospaced capitals, wide tracking, no serifs; charm-like restraint.
- Mirrored geometry motifs on mats, patches, and loading screens — always
  symmetric, never animated in reverse.
- The existing round-score strip already fills its pips outward from the
  center on both sides; this is the correct visual grammar for the Square
  and should be preserved.

## Implementation mapping (future work)

1. **Nomenclature source**: a single `TeamNomenclature` helper owning
   axis selection and word lookup; HUD strings, beacons, and match events
   read from it instead of hardcoded "ALPHA"/"BRAVO".
2. **Strip and HUD**: relabel team blocks to the active axis pair.
3. **Objective beacons**: "SATOR TARGET" / "ROTAS TARGET".
4. **Match events**: "ROUND WON BY SATOR  •  resetting in 4 seconds".
5. **League layer** (tournament phase): House selection at team
   registration; bracket names; Axis rotation per tournament round.
6. **Lore delivery**: map briefings, loadout-screen marginalia, and the
   league rules page carry fragments of the fiction — one sentence each,
   never walls of text.

## Open taste decisions

1. Default axis in ranked play: fixed SATOR/ROTAS, or seeded per match?
2. Does the league (the Square) get a name that references the center word,
   or is the center word never spoken as a brand? (Recommendation: never
   spoken — the withheld word is stronger than the used one.)
3. Single-player Training Playground fiction: is the range an OPERA
   workshop (the craft house trains its own)?
