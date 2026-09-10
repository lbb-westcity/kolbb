extends RefCounted
const Battle = preload("res://scripts/battle.gd")
var battle = Battle.new()
var slot: int = 0
var cursor: int = 0
var local_inputs: Dictionary = {}
var remote_inputs: Dictionary = {}
var used_remote: Dictionary = {}
var snapshots: Dictionary = {}
var checksums: Dictionary = {}
var remote_high: int = -1
var peer_ack: int = -1
var confirmed: int = -1
var rollback_count: int = 0
var max_replay_us: int = 0
var error: String = ""
var pending_events: Array = []

func start(chars: Array, seed_value: int, match_id: int, my_slot: int) -> void:
	battle.reset(chars,seed_value,match_id)
	slot=my_slot;cursor=0;remote_high=2;peer_ack=2;confirmed=2
	local_inputs={0:0,1:0,2:0};remote_inputs={0:0,1:0,2:0}
	used_remote.clear();snapshots.clear();checksums.clear();pending_events.clear()
	error="";rollback_count=0;max_replay_us=0

func receive(pairs: Array, ack: int) -> void:
	peer_ack=maxi(peer_ack,ack)
	var earliest: int=cursor
	for pair in pairs:
		var n: int=pair[0]
		var bits: int=pair[1]
		if remote_inputs.has(n) and remote_inputs[n]!=bits:
			error="输入冲突，本场无结果"
			return
		remote_inputs[n]=bits
		if n<cursor and used_remote.get(n,bits)!=bits: earliest=mini(earliest,n)
	while remote_inputs.has(remote_high+1): remote_high+=1
	confirmed=mini(remote_high,peer_ack)
	if earliest<cursor:
		if cursor-earliest>12 or not snapshots.has(earliest):
			error="连接中断，本场无结果"
			return
		var end: int=cursor
		var began: int=Time.get_ticks_usec()
		battle.restore(snapshots[earliest])
		cursor=earliest
		pending_events.clear()
		while cursor<end: advance()
		rollback_count+=1
		max_replay_us=maxi(max_replay_us,Time.get_ticks_usec()-began)

func can_advance() -> bool:
	return error=="" and cursor-remote_high<=12

func tick(bits: int) -> Array:
	if not can_advance(): return []
	if not local_inputs.has(cursor+3): local_inputs[cursor+3]=bits
	advance()
	var result: Array=pending_events.duplicate()
	pending_events.clear()
	return result

func predicted(n: int) -> int:
	if remote_inputs.has(n): return remote_inputs[n]
	for k in range(n-1,maxi(-1,n-240),-1):
		if remote_inputs.has(k): return remote_inputs[k]
	return 0

func advance() -> void:
	snapshots[cursor]=battle.snapshot()
	var remote: int=predicted(cursor)
	used_remote[cursor]=remote
	var input_pair: Array=[0,0]
	input_pair[slot]=local_inputs.get(cursor,0)
	input_pair[1-slot]=remote
	pending_events.append_array(battle.step(input_pair))
	if (cursor+1)%60==0 or battle.state.phase=="done":
		checksums[cursor]=battle.checksum()
	cursor+=1
	snapshots.erase(cursor-21)
	for table in [local_inputs,remote_inputs,used_remote,checksums]: table.erase(cursor-241)

func batch() -> Array:
	var result: Array=[]
	var newest: int=cursor+2
	for n in range(maxi(0,newest-7),newest+1):
		if local_inputs.has(n): result.append([n,local_inputs[n]])
	return result
