extends RefCounted
const BUTTONS=[JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_X,JOY_BUTTON_A,JOY_BUTTON_Y,JOY_BUTTON_B,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_LEFT_SHOULDER]
const LABELS=["↑","↓","←","→","X","A","Y","B","RB","LB"]

static func setup() -> void:
	for i in 10:
		var action: String="fight_"+str(i)
		if InputMap.has_action(action): continue
		InputMap.add_action(action,.3)
		var button=InputEventJoypadButton.new();button.button_index=BUTTONS[i];button.device=-1
		InputMap.action_add_event(action,button)
		if i<4:
			var motion=InputEventJoypadMotion.new();motion.device=-1
			motion.axis=JOY_AXIS_LEFT_Y if i<2 else JOY_AXIS_LEFT_X
			motion.axis_value=-1 if i in [0,2] else 1
			InputMap.action_add_event(action,motion)

static func bits() -> int:
	var value: int=0
	for i in 10:
		if Input.is_action_pressed("fight_"+str(i)): value|=1<<i
	return value
