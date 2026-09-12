extends SceneTree
var main

func _initialize() -> void: call_deferred("run")

func shot(page: int) -> void:
	await process_frame;await process_frame
	if DisplayServer.get_name()=="headless": return
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	root.get_texture().get_image().save_png("res://build/qa/settings-"+str(page)+".png")

func press(code: Key) -> void:
	var event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	main._input(event)
	await process_frame;await process_frame

func run() -> void:
	# Keep UI checks from overwriting the player's saved preferences.
	var script=GDScript.new()
	script.source_code='extends "res://scripts/main.gd"\nvar saves: int=0\nfunc load_settings() -> void: apply_display()\nfunc save_settings() -> void: saves+=1\n'
	assert(script.reload()==OK)
	main=script.new();main.tests_demo=true;root.add_child(main)
	main.set_process(false);main.set_physics_process(false)
	var mobile: bool="mobile_validation" in main and main.mobile_validation
	for page in 4:
		main.show_settings("home",page)
		await shot(page)
		assert(main.ui.get_node("SettingsPanel").get_rect().end.y<=360)
		assert(main.ui.get_node("SettingsPreview").get_child(0).battle!=main.battle,"Preview must not alter current match")
		assert(main.ui.get_node("SettingsTab"+str(page)).has_focus())
		if page==0:
			if mobile:
				assert(main.ui.find_child("Setting_fullscreen",true,false)==null)
			else:
				var vsync=main.ui.find_child("Setting_vsync",true,false)
				vsync.button_pressed=false;assert(not main.settings.vsync)
			var cap=main.ui.find_child("Setting_frame_limit",true,false)
			cap.item_selected.emit(2);await process_frame;await process_frame
			assert(main.settings.frame_limit==120 and Engine.max_fps==120)
		elif page==1:
			main.settings.music=11
			main.ui.find_child("Setting_shake",true,false).button_pressed=false
			assert(not main.settings.shake)
			main.reset_settings_page();assert(main.settings.shake and main.settings.music==11,"Reset affects current page only")
		elif page==2:
			if mobile:
				main.ui.find_child("Setting_touch_dead_zone",true,false).value=35
				assert(is_equal_approx(main.touch.dead_zone,.35))
				main.ui.find_child("Setting_touch_opacity",true,false).value=75
				assert(is_equal_approx(main.touch.opacity,.75))
			else:
				main.ui.find_child("Setting_0",true,false).pressed.emit()
				await press(KEY_S)
				assert(main.settings.keys[0]==KEY_S and main.settings.keys[1]==KEY_W and main.settings_page==2)
				main.ui.find_child("Setting_0",true,false).pressed.emit();await press(KEY_ESCAPE)
				assert(main.rebind==-1 and main.screen=="settings")
		else:
			main.ui.find_child("Setting_music",true,false).value=35
			assert(main.settings.music==35 and is_equal_approx(main.audio.music_volume,.35))
	assert(main.saves>=5,"Control changes invoke automatic save")
	main.show_settings("home",0);await press(KEY_LEFT);assert(main.settings_page==3)
	await press(KEY_RIGHT);assert(main.settings_page==0)
	main.start_local();main.show_pause();var frame: int=main.battle.state.frame
	main.show_settings("pause",1);main._physics_process(1.0/60)
	assert(main.paused and main.battle.state.frame==frame)
	await press(KEY_ESCAPE);assert(main.screen=="pause" and main.paused)
	print("PASS settings: four pages, independent preview, video/audio/touch controls, key swap/cancel, scoped reset, save callbacks and pause return")
	main.queue_free();await process_frame;quit()
