# Private server boundary — first slice

Player intent: prevent browser downloads from exposing privileged server code.
Acceptance: backend persistence and tournament outbox scripts are absent from the
actual web PCK; native dedicated sessions can still load both.
Owner: existing multiplayer session, with release packaging enforcing absence.
Protected: movement, camera, animation, weapon tuning, wire protocol and training.
Proof: private_server_boundary_regression.gd, web_release_audit.gd on rebuilt PCK,
feature_contract_regression.gd and browser boot.

MERGE: replace eager private-service preloads with guarded native runtime loads,
and reject both source and compiled private services in web packaging.
This does not hide damage, tournament simulation or player-host logic yet.
Those still share an inheritance chain with the multiplayer client; removing
them requires a separate client/server runtime split and remote parity tests.
Offline training necessarily ships enough logic to simulate offline play.
No server has been deployed and no live database policy is asserted verified.

Verified this pass: native construction and multiplayer scene load PASS;
tournament event delivery regression PASS; security static contract PASS;
69 feature contracts PASS; rebuilt PCK audit PASS (1828 entries, zero findings).
Chrome booted launcher and training without missing-script errors. Cloud signup
returned HTTP 422 and existing microphone warnings remain; no online match claim.
The aggregate quick gate refuses codex/render-deployment because it requires
main. The branch and unrelated working changes were preserved.

Runtime loading follows Godot ResourceLoader documentation:
https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
