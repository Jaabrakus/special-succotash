# Browser release protection

Intent: reduce accidental exposure without pretending browser assets are private.
Acceptance: exported PCK contains no protected source/review paths or recognized
privileged credentials; canonical browser Training Grounds still opens.
Owner: tools/export_restricted_web.sh and its package audit.
Protected: gameplay, appearance, animation, camera, networking protocol and licenses.
Proof: web_release_audit self-test, actual PCK audit, contract gate, browser smoke.

MERGE: existing exclusions and notices remain; add actual-package checks rather
than relying only on logs and tracked filenames. Scores current -> candidate:
correctness 2->4, ownership 5->5, parity 3->5, usability 3->4, performance 5->5,
coverage 2->4. Evidence: tools/release_protection_check.sh checks tracked filenames;
tools/web_release_audit.gd inspects PCK entries plus corresponding script sources.
No new runtime nodes, encryption keys, analytics, watermarks, or gameplay writers.

The scanner detects selected known token formats, not every possible secret.
Compiled scripts are checked through their local source; this is a build guard,
not proof that arbitrary third-party bytecode is credential-free. Keep the source
repository private. Previously distributed builds cannot be recalled by rebuilding.
If a privileged key ever shipped, revoke/rotate it at its provider; never rely on
removing it from a later ZIP. Publishable/anon keys are intentionally public and
require correctly enforced database RLS. No live database settings changed here.

Runtime models/audio/game data and compiled client logic remain extractable.
Existing ownership/third-party notices are retained, not replaced or expanded.
Reusing assets in the browser does not grant recipients ownership, but notices
and no-AI directives cannot technically stop extraction. Server-only rules and
secrets must actually remain on trusted servers, not browser-hosted P2P peers.
