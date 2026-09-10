extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate();root.add_child(main)
	main.set_physics_process(false)
	var net=root.get_node("Net")
	net.failed.connect(func(reason): printerr("FAIL menu network: ",reason);quit(1))
	# More than four rooms proves menu exit releases server membership.
	for i in 5:
		net.connect_room("127.0.0.1")
		await net.room_changed
		main.show_home()
		assert(not net.connected and not net.connecting and net.room.is_empty())
		await create_timer(.15).timeout
	net.connect_room("127.0.0.1")
	main.show_home()
	assert(not net.connecting)
	await create_timer(.3).timeout
	assert(main.screen=="home")
	print("PASS menu return releases five rooms and cancels pending connection")
	main.queue_free();await process_frame;quit()
