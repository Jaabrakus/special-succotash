# Ranked authority protection: first pass

Intent: clients cannot award themselves rank or submit trusted results.
Acceptance: profile naming remains editable; rank fields and raw tournament
tables reject client writes; only the service role executes result ingress.
Owner: PostgreSQL grants/RLS for stored results, existing dedicated backend for delivery.
Protected: gameplay, weapon timing, animation, movement, networking wire protocol.
Proof: ranked_authority_security_regression, tournament_event_delivery_regression,
feature contract gate, and supabase/verify_ranked_result_authority.sql on deployment.

Findings from saved code, not confirmed live database permissions:
- 20260821001000 grants table-wide profile INSERT/UPDATE. The later ELO migration
  adds ranking columns without narrowing those grants; ownership RLS cannot
  stop editing protected columns on one's own row.
- Tournament match/inbox migrations omit explicit RLS and table privilege fences.
- Result RPC already revokes PUBLIC execution, but now also explicitly revokes
  client-role grants. Its event idempotency remains unchanged.
- ELO/rewards are NOT implemented by that RPC: its comment explicitly waits for
  trusted account-id mapping. Do not advertise persisted ranked rewards yet.
- Backend exists only on dedicated hosting; an explicit mode guard now fences
  tournament outbox delivery as defense in depth. Browser backend initialization
  refuses credentials. SQL privileges remain the real security boundary.

MERGE scores (0–5 current -> candidate): correctness 2->4, ownership 4->5,
runtime parity 3->4, editor usability 3->4, performance 5->5, coverage 2->3.
Evidence: migrations/20260821001000 and 20260830010000; new migration
20260906010000, scripts/server/socom_server_backend.gd and focused regression.

Deployment status: prepared, NOT applied. Docker daemon unavailable; no live SQL
connector is configured. SQL execution and real-role behavior remain unverified.
Local proof: static security contract PASS; trusted result delivery PASS; durable
outbox retry/restart PASS (rerun with local user-data access); 68 feature contracts
PASS. The initial restricted outbox test could not write its fixture; no runtime
outbox change was needed. These passes do not validate PostgreSQL execution.
Apply the transaction only to the intended game database after schema review and
backup, then run the read-only verification SQL. Do not regrant table-wide profile
writes to repair a client request; submit only the permitted name/handle fields.

This does not migrate all games to dedicated hosting, authenticate peer-to-account
mapping, add rate limits, or deploy a server. Those remain separate work before
calling the competitive backend production-secure. Browser P2P play remains usable
but must not be trusted to publish ranked results. Existing client assets and
client-side logic remain inspectable; no anti-extraction claim is made.
