extends SceneTree
const Rollback = preload("res://scripts/rollback.gd")
const Cpu = preload("res://scripts/cpu.gd")
var cpu=Cpu.new()
var full: bool=false
var results: int=0
var result_sent: bool=false
var hostname: String="127.0.0.1"
var net
var driver
var creator: bool = false
var code_path: String="/tmp/kolbb-test-room"
var frames: int=0
var done: bool=false
var elapsed: float=0
func _initialize() -> void:
	call_deferred("begin")
func begin() -> void:
	net=root.get_node("Net")
	creator="--creator" in OS.get_cmdline_user_args()
	full="--full" in OS.get_cmdline_user_args()
	var args=OS.get_cmdline_user_args()
	if "--host" in args: hostname=args[args.find("--host")+1]
	net.failed.connect(func(reason):
		if done: quit()
		else: printerr("FAIL network ",reason);quit(1))
	net.result_confirmed.connect(func(info):
		results+=1;print("PASS confirmed result ",results," slot ",net.slot," CRC ",info.crc," wins ",info.wins)
		if results>=2: done=true;finish_later())
	net.room_changed.connect(func(info):
		if creator:
			var f=FileAccess.open(code_path,FileAccess.WRITE);f.store_string(info.code);f.close()
		if not done and info.chars.size()==2 and not info.ready[info.slot]: net.set_ready(true))
	net.match_started.connect(func(info):
		driver=Rollback.new();driver.start(info.chars,info.seed,info.match,info.slot)
		cpu=Cpu.new();cpu.level=2;cpu.seed_value=info.seed+info.slot;result_sent=false
		print("START slot ",info.slot))
	net.input_received.connect(func(pairs,ack):
		if driver: driver.receive(pairs,ack))
	if creator: net.connect_room(hostname)
	else:
		var code: String=FileAccess.get_file_as_string(code_path).strip_edges()
		net.connect_room(hostname,code)
func _process(dt: float) -> bool:
	elapsed+=dt
	if elapsed>(480 if full else 25): printerr("FAIL network timeout");quit(1);return false
	return false
func _physics_process(_dt: float) -> bool:
	if not driver: return false
	if driver.error!="": printerr(driver.error);quit(1);return false
	if full and driver.battle.state.phase!="done":
		driver.tick(cpu.sample(driver.battle,net.slot))
	elif not full and driver.cursor<700:
		var n: int=driver.cursor
		var bits: int=(8 if creator else 4) if n%90<25 else 16 if n%90==25 else 0
		driver.tick(bits)
	net.send_inputs(driver.batch(),driver.remote_high)
	frames+=1
	if frames%3==0 and driver.remote_high<driver.cursor+2: net.request_gap(driver.remote_high+1,driver.cursor+2)
	for n in driver.checksums:
		if n<=driver.confirmed and (n+1)%60==0: net.report_hash(n,driver.checksums[n])
	if full and driver.battle.state.phase=="done" and driver.confirmed>=driver.cursor-1 and not result_sent:
		net.report_result(driver.cursor-1,driver.battle.checksum(),driver.battle.state.wins,driver.battle.state.winner);result_sent=true
	if not full and driver.cursor==700 and driver.confirmed>=699 and not done:
		done=true
		print("PASS ENet slot ",net.slot," frame ",driver.cursor," CRC ",driver.battle.checksum()," rollbacks ",driver.rollback_count)
		var f=FileAccess.open("/tmp/kolbb-net-%d.txt" % net.slot,FileAccess.WRITE);f.store_string(str(driver.battle.checksum()));f.close()
		finish_later()
	return false
func finish_later() -> void:
	await create_timer(1).timeout
	quit()
