import bpy

def start_playback():
    try:
        # Find 3D view and set to Material Preview
        for area in bpy.context.screen.areas:
            if area.type == 'VIEW_3D':
                for space in area.spaces:
                    if space.type == 'VIEW_3D':
                        space.shading.type = 'MATERIAL'
        # Play the animation loop
        bpy.ops.screen.animation_play()
        print("[AUTOPLAY] Animation playback started successfully!")
    except Exception as e:
        print(f"[AUTOPLAY] Error starting playback: {e}")
    return None

bpy.app.timers.register(start_playback, first_interval=0.6)
