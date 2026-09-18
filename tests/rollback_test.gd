extends SceneTree
const Rollback = preload("res://scripts/rollback.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for chars in [[0,1],[2,0],[1,2],[2,2],[3,0],[3,1],[2,3],[3,3]]: check_match(chars)
	quit()
func check_match(chars: Array) -> void:
	var a=Rollback.new();var b=Rollback.new()
	a.start(chars,455,18,0);b.start(chars,455,18,1)
	var packets: Array=[]
	for tick in 2200:
		var ka: int=8 if tick%60<30 else 16 if tick%60==30 else 0
		var kb: int=4 if tick%70<25 else 64 if tick%70==25 else 0
		a.tick(ka);b.tick(kb)
		if tick%19!=0:
			packets.append({"at":tick+3+tick%3,"to":b,"pairs":a.batch(),"ack":a.remote_high})
		if tick%23!=0:
			packets.append({"at":tick+2+tick%4,"to":a,"pairs":b.batch(),"ack":b.remote_high})
		for packet in packets.duplicate():
			if packet.at<=tick:
				packet.to.receive(packet.pairs,packet.ack);packets.erase(packet)
		assert(a.error=="" and b.error=="","rollback must tolerate delay/loss")
	# Flush remaining actual inputs, then compare equal simulation frames.
	b.receive(a.batch(),a.remote_high);a.receive(b.batch(),b.remote_high)
	assert(a.cursor==b.cursor)
	assert(a.battle.checksum()==b.battle.checksum(),"peers must converge")
	print("PASS rollback: 2200 frames, 2–6 tick delay, recurring loss; corrections ",a.rollback_count+b.rollback_count,"; peak replay µs ",maxi(a.max_replay_us,b.max_replay_us),"; CRC ",a.battle.checksum())
