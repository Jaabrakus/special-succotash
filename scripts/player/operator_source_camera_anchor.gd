extends Node

## Non-spatial observation channel. Existing AnimationTree is its only writer;
## it neither deforms the skeleton nor translates CharacterBody3D.
@export var root_source := Vector3.ZERO
@export var coverage := 0.0
