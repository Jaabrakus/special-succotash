# Look pitch without automatic zoom

Translation card: player wants a restrained spine response to looking up/down and no zoom simply from looking down. Camera composition owns the lens; existing operator posture owns distributed spine rotations. Keep camera aim, collision/recovery, CharacterBody, legs, authored traversal, jump, reload and shot timing unchanged. Proof: `look_pitch_presentation_regression.gd`, obstruction regression, main rendered standing/crouched pitch sweeps.

MERGE delta: `camera_composition_controller.gd::update_dynamic_fov` previously narrowed 68° to 60° then 42° by downward aim; the saved CameraProfile gains `pitch_zoom_enabled = false`. Collision widening remains; scope ownership is unchanged. `operator_posture_layer.gd::apply` previously multiplied pitch by weapon-ready only, while the runtime zeroed moving relaxed pitch. A saved 0.4 relaxed weight and response 12 now retain a bounded pitch component on standing/crouched spine bones only; authored action ownership remains.

Scores current -> candidate: correctness 2->4, ownership 5->5, canonical parity 5->5, editor usability 3->4, performance 5->5, regression coverage 2->4. Evidence: camera composition/profile, operator posture/runtime, focused pitch regression and obstruction guard regression.
