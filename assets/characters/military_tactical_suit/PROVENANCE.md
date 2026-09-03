# Military Tactical Suit provenance

- Asset: `military_tactical_suit.glb`
- Title: Military tactical suit (LowPolyGameReady)
- Creator: DanlyVostok
- Source: https://sketchfab.com/3d-models/military-tactical-suit-lowpolygameready-ef698ce36b1545a78ce592dd3db4c7ed
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
- License URL: https://creativecommons.org/licenses/by/4.0/
- SHA-256: `eed7be0507d981b5f09fbce8c6b5a827358d22b08f7052104d74251926049484`

The source, creator, title, and license are also embedded in the glTF asset
metadata. Retain this file and provide the creator attribution in shipped
credits while the asset remains in a customer build.

## Production derivative

- Asset: `military_tactical_suit_tpose.glb`
- SHA-256: `ab703af1b67874c6d4f3144314f3368f19d5a98b3eab9c597e95f09386017354`
- Source asset: `military_tactical_suit.glb`
- Source SHA-256: `eed7be0507d981b5f09fbce8c6b5a827358d22b08f7052104d74251926049484`
- Tool: repository direct-GLB rebind scripts, verified with Blender 5.2.1 LTS and Godot 4.7.1

The derivative bakes the corrected T-pose into the mesh geometry and the
88-joint armature rest, normalizes all deform weights, limits each vertex to
four influences, rebuilds the inverse-bind matrices, and removes the embedded
source animation. It does not change the license or attribution requirement.
