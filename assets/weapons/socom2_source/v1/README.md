# Incomplete source weapon export — do not use in gameplay

This first export stopped at `Missing source texture: satchel_tex.tif` before
writing a completed manifest. Its existing partial files are preserved for
inspection. `.gdignore` prevents Godot from importing this incomplete folder.

The corrected exporter resolves all original material dependencies before
writing a fresh version. Use a version with a complete manifest and passing
asset validation; this folder is not a verified runtime asset library.
