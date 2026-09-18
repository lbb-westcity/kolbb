extends SceneTree

func _initialize() -> void: call_deferred("run")

func press(main: Node,key: int) -> void:
	var event=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=true
	main._input(event)

func run() -> void:
	var main=load("res://main.tscn").instantiate();root.add_child(main)
	main.set_physics_process(false)
	main.settings.keys[4]=KEY_F
	for page in 5:
		main.show_moves("select",page)
		await process_frame
		assert(main.ui.get_viewport().gui_get_focus_owner().text==(main.Battle.NAMES+["共通操作"])[page])
		assert(main.ui.get_children().any(func(n): return n is Label and n.text=="F"),"Footer must use remapped keys")
		var rows=main.ui.get_children().filter(func(n): return str(n.name).begins_with("MoveRow"))
		assert(rows.size()==([4,4,5,4,0][page]),"Every character move must be visible")
		if page<4:
			assert(main.ui.get_node("MovePortrait").texture.resource_path=="res://assets/ui/%s-movelist-v2.png" % main.Battle.ART[page])
		for node in main.ui.get_children():
			if node is Control:
				assert(Rect2(0,0,640,360).encloses(node.get_rect()),"Control outside viewport: %s %s" % [node.name,node.get_rect()])
		if "--capture-moves" in OS.get_cmdline_user_args():
			main.settings.keys[4]=KEY_J;main.show_moves("select",page);await process_frame
			DirAccess.make_dir_recursive_absolute("res://build/qa")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/qa/moves_%d.png" % page)
		main.settings.keys[4]=KEY_F
	press(main,KEY_RIGHT);assert(main.moves_page==0,"Last tab wraps to first")
	press(main,KEY_LEFT);assert(main.moves_page==4,"First tab wraps to last")
	press(main,KEY_ESCAPE);assert(main.screen=="select","Escape returns to origin")
	main.selected=2;main.start_local();main.show_pause();main.show_moves("pause")
	assert(main.moves_page==2 and main.paused,"Pause opens the active fighter's moves")
	press(main,KEY_ESCAPE);assert(main.screen=="pause" and main.paused)
	print("Move list UI: five pages, key remapping, tab wrapping and pause return PASS")
	main.queue_free();await process_frame;quit()
