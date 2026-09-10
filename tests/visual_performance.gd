extends SceneTree
var main
var elapsed: float=0
var frame_ms: Array=[]
var engine_ms: Array=[]
var began_us: int=0
var previous_us: int=0
func _initialize() -> void:
	call_deferred("begin")
func begin() -> void:
	main=load("res://main.tscn").instantiate();main.tests_demo=true;root.add_child(main)
	main.start_local()
	began_us=Time.get_ticks_usec();previous_us=began_us
func _process(dt: float) -> bool:
	var now: int=Time.get_ticks_usec()
	var actual_ms: float=(now-previous_us)/1000.0
	previous_us=now
	elapsed=(now-began_us)/1000000.0
	if not main or elapsed<3: return false
	frame_ms.append(actual_ms)
	engine_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
	if elapsed>=18:
		frame_ms.sort();engine_ms.sort()
		var report: Dictionary={"frames":frame_ms.size(),"fps":Engine.get_frames_per_second(),"wall_frame_ms_p95":frame_ms[int(frame_ms.size()*.95)],"engine_frame_ms_p95":engine_ms[int(engine_ms.size()*.95)],"video_memory_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"engine":Engine.get_version_info().string}
		print("RENDER PERFORMANCE ",JSON.stringify(report))
		FileAccess.open("res://build/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		main.queue_free();quit()
	return false
