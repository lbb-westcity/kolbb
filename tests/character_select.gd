extends "res://tests/home_menu.gd"

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/qa/"+name+".png")

func run() -> void:
	var main=load("res://main.tscn").instantiate();root.add_child(main);main.set_physics_process(false)
	main.show_select();await process_frame
	assert(main.arena.character_select and main.arena.demo and not main.arena.hud)
	await capture("character-select")
	# Mouse-select every real portrait on both sides, including mirror matches.
	for slot in 2:
		for character in 4:
			var card=main.ui.get_node("Character%d_%d" % [slot,character])
			assert(card.get_rect().end.y<300)
			var mouse=InputEventMouseButton.new();mouse.position=card.get_rect().get_center();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
			root.push_input(mouse,true)
			mouse=mouse.duplicate();mouse.pressed=false;root.push_input(mouse,true)
			await process_frame
			assert((main.selected if slot==0 else main.opponent)==character)
			assert(main.battle.state.fighters[slot].char==character)
			assert(main.ui.get_node("Character%d_%d" % [slot,character]).button_pressed)
	await capture("character-select-mirror")
	main.ui.get_node("Character0_3").grab_focus()
	await press(KEY_D);assert(main.ui.get_node("Character1_0").has_focus())
	await press(KEY_ENTER);assert(main.opponent==0 and main.battle.state.fighters[1].char==0)
	await press(KEY_S);assert(main.ui.get_node("StartBattle").has_focus())
	main.ui.get_node("Difficulty").grab_focus()
	await press(KEY_ENTER);await press(KEY_DOWN);await press(KEY_ENTER)
	assert(main.difficulty==2)
	main.ui.get_node("SelectMoves").grab_focus();await press(KEY_ENTER)
	assert(main.screen=="moves" and not main.arena.character_select)
	await press(KEY_ESCAPE)
	assert(main.screen=="select" and main.arena.character_select)
	assert(main.selected==3 and main.opponent==0 and main.difficulty==2)
	main.ui.get_node("StartBattle").grab_focus();await press(KEY_ENTER)
	assert(main.screen=="fight" and not main.arena.character_select)
	assert(main.battle.state.fighters[0].char==3 and main.battle.state.fighters[1].char==0 and main.cpu.level==2)
	assert(main.arena.bg.resource_path=="res://assets/stage/office.png")
	main.show_select();await press(KEY_ESCAPE)
	assert(main.screen=="home" and not main.arena.character_select)
	print("PASS character select: mouse roster, mirror previews, keyboard, difficulty, move-list return and battle roster")
	main.queue_free();await process_frame;quit()
