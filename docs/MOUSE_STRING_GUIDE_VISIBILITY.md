# Mouse aim string stays active when hidden

Translation card: the mouse aim-string behavior stays on during gameplay; M
only shows/hides its guide. Acceptance: M press toggles debug visibility but
preserves enabled state, aim angles, destination and accumulated blue offset;
hidden mode continues updating aim. Key release/repeat does not toggle.
Owner: SocomCameraRig input handler; guide only reads its visibility state.
Protected: sensitivity, deadzone, smoothing, recoil/VRC, bullet aim, controller
ownership, menus/pointer capture, movement, animation and damage.
Proof: mouse_aim_string_regression, input_device_ownership_regression, VRC test,
feature gate, and a rendered visibility check.

M used to call set_mouse_aim_string_enabled, which also resets the mouse model.
M now changes mouse_string_debug_visible only. Existing default active behavior
is preserved. Internal legacy/calibration setters and automated-test isolation
remain available, but normal gameplay has no key that disables the string.
N no longer toggles the debug guide or forcibly hides it when activating NVG.
The F3 controls guide describes M as visibility only. No other aiming parameter
or camera transform writer changes, and no browser export is performed.
