extends SceneTree

func _initialize() -> void: call_deferred("run")

func press(code: Key) -> void:
	var event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event)
	await process_frame
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code
	root.push_input(event)
	await process_frame

func run() -> void:
	var main=load("res://main.tscn").instantiate();root.add_child(main)
	main.set_physics_process(false)
	await process_frame
	var buttons: Array=[]
	for child in main.ui.get_children():
		if child is Button: buttons.append(child)
	assert(buttons.size()==6)
	assert(main.ui.get_node("Logo").texture.get_image().has_mipmaps()==false)
	assert(main.arena.bg.resource_path=="res://assets/stage/menu-office.png")
	for i in buttons.size():
		assert(buttons[i].has_focus(),"Down navigation must reach every menu entry")
		assert(Rect2(Vector2.ZERO,Vector2(640,360)).encloses(buttons[i].get_rect()))
		await press(KEY_DOWN)
	assert(buttons[0].has_focus(),"Down wraps to first entry")
	await press(KEY_W)
	assert(buttons[5].has_focus(),"W wraps to last entry")
	await press(KEY_S)
	assert(buttons[0].has_focus())
	await press(KEY_D)
	assert(buttons[1].has_focus())
	await press(KEY_A)
	assert(buttons[0].has_focus())
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute("res://build/qa")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/qa/home-menu.png")
	await press(KEY_ENTER)
	assert(main.screen=="select")
	assert(main.arena.bg.resource_path=="res://assets/stage/menu-office.png")
	await press(KEY_ESCAPE)
	assert(main.screen=="home")
	for destination in ["network","moves","settings"]:
		var title: String={"network":"互联网对战","moves":"出招表","settings":"设置"}[destination]
		for child in main.ui.get_children():
			if child is Button and child.text==title: child.grab_focus()
		await press(KEY_ENTER)
		assert(main.screen==destination)
		await press(KEY_ESCAPE)
		assert(main.screen=="home")
	main.start_local()
	assert(main.arena.bg.resource_path=="res://assets/stage/office.png")
	main.show_home()
	assert(main.arena.bg.resource_path=="res://assets/stage/menu-office.png")
	print("PASS home menu: six entries, keyboard navigation, activation, return and background restoration")
	main.queue_free();await process_frame;quit()
