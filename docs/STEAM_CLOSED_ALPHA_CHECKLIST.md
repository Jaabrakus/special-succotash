# 141 Steam Closed-Alpha Checklist

Verified against official documentation on 2026-08-23. Recheck before acting,
because platform requirements can change.

## Recommended distribution path

Use Steam Playtest for the first external multiplayer alpha. It is a separate
child app ID associated with the main game, can be enabled or disabled without
changing the base game's reviews or wishlists, and supports controlled batches,
keys, country selection, and the same Steamworks technical features as the base
app. Do not charge for Steam Playtest access or sell its keys.

Official source: https://partner.steamgames.com/doc/features/playtest

## Account and calendar blockers

- [ ] Create the legal Steamworks partner account and complete identity, bank,
  and tax onboarding.
- [ ] Pay the current Steam Direct fee for the base app. The official page lists
  USD $100 per app and explains its revenue-recoupment condition.
- [ ] Start the required waiting clock immediately. Steam currently documents a
  30-day wait between paying the app fee and releasing the game.
- [ ] Prepare the publicly visible Coming Soon page. Steam currently requires it
  to be visible for at least two weeks before release.
- [ ] Reserve time for Steam's documented build/store review, currently stated
  as roughly one to five days, plus correction time.

Official sources:

- https://partner.steamgames.com/doc/gettingstarted/appfee
- https://partner.steamgames.com/steamdirect

## Playtest app

- [ ] Create the Playtest child app from Associated Packages & DLC.
- [ ] Choose the permanent customer-visible Playtest name carefully.
- [ ] Provide the required library capsule and community assets.
- [ ] Upload a release build and complete the Playtest release checklist.
- [ ] Start with limited signup or Playtest keys; grant only the number of users
  the current server capacity can support.
- [ ] Publish the test dates, supported region, hardware target, known issues,
  privacy notice, support path, and access expectations.
- [ ] Verify host, join, invite, match completion, reconnect, rematch, clean exit,
  crash reporting, and version rejection from a fresh Steam installation.
- [ ] Set the Playtest to Not Playable when the test ends and communicate first.

## SteamPipe build pipeline

- [ ] Download the current Steamworks SDK from the partner portal.
- [ ] Create a dedicated build account with only the documented app-metadata and
  publish permissions needed for uploads.
- [ ] Keep Steam credentials and Steam Guard material outside the repository.
- [ ] Define app and depot VDF files outside customer content.
- [ ] Upload preview builds first, inspect their file mappings, and verify that
  no source art, reference media, Labs, credentials, or unapproved packages are
  included.
- [ ] Promote builds to a password-protected alpha branch before any wider branch.
- [ ] Record game version, Git commit, content hash, Steam BuildID, depot manifest
  IDs, environment, migration version, and test result for every promoted build.
- [ ] Keep the previous verified manifest available as the rollback candidate.

Official sources:

- https://partner.steamgames.com/doc/sdk/uploading
- https://partner.steamgames.com/doc/sdk/updating

## Godot Windows release export

- [ ] Add or verify an x86_64 Windows Desktop release preset.
- [ ] Export from a clean, tagged commit with release templates—not the editor or
  debug executable.
- [ ] Use an explicit include list or audited export filters.
- [ ] Configure a package signing certificate and Godot's Windows signing support.
  Godot documents Windows SDK SignTool on Windows or `osslsigncode` elsewhere.
- [ ] Store the signing certificate/password outside the repository and inject
  them through the build environment.
- [ ] Test the signed export on clean minimum/recommended Windows machines.

Official sources:

- https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html

## Current no-go conditions

Do not upload a customer-facing build while any of these are true:

- `commercial_asset_clearance_audit.gd --enforce-clearance` reports blockers.
- The full integration gate is red.
- A complete multiplayer soak has not passed at the advertised lobby size.
- The build contains editable source art, reference media, experimental third-
  party characters, developer Labs, service-role secrets, or private credentials.
- There is no privacy notice, support path, rollback build, or version-rejection
  behavior.
