# 141 release protection

No client build can keep every included asset secret. Protection comes from
shipping less material, retaining important authority on a server, marking each
release, and preserving evidence of ownership.

## Required release boundary

Keep these items out of every playable client:

- source-quality art and editable project files;
- unused and unreleased maps, characters, weapons, animation clips, and audio;
- credentials, signing keys, private URLs, service tokens, and database details;
- server validation, economy, account, moderation, and administration logic; and
- private design notes and asset acquisition records.

Use reduced runtime meshes, textures, animations, and audio in the client. Keep
the full source files in access-controlled storage. Do not depend on package
encryption as the only protection because the client must eventually read its
content.

## Web demo boundary

The web build should be a limited demo, not a copy of the full game. Include
only the content needed for the demo. Deploy `web/robots.txt` as `/robots.txt`
and `web/ai.txt` as `/ai.txt` on the same origin. These files communicate terms
to compliant crawlers but do not block a person or a crawler that ignores them.

Place the license and AI policy beside the downloadable build. Require clear
acceptance of the end-user terms before access when the release platform allows
it. A displayed notice without acceptance gives weaker evidence than a recorded
click-through agreement.

## Traceable test builds

Create a unique release identifier for each private tester. Record the tester,
release identifier, date, commit, and distributed package hash outside the game
repository. Put the identifier in a visible build screen and in at least one
non-obvious asset or manifest location. Do not put personal information in the
watermark.

Watermarks help identify a leaked build. They do not prevent extraction.

## Public repository warning

A public source repository makes every committed file downloadable, including
files removed by later commits if they remain in history. Before adding
confidential material, confirm that the repository is private. Moving a leaked
secret into `.gitignore` does not revoke or erase that secret. Revoke exposed
credentials and use a deliberate history-cleaning procedure when required.

## Release checklist

1. Run `tools/release_protection_check.sh`.
2. Review every warning and resolve unexpected source files.
3. Inventory third-party material and confirm redistribution rights.
4. Export only the scenes and resources required by the release.
5. Confirm the client contains no secrets or server-only logic.
6. Generate a unique build identifier and record the package hash.
7. Test the final package from a clean machine or clean browser profile.
8. Archive the exact license, policy, commit, and manifest used for the release.

The license and policy are practical rights-reservation documents, not legal
advice. Have qualified counsel adapt them before a commercial launch.
