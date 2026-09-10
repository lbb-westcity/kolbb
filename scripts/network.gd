extends Node
signal room_changed(info: Dictionary)
signal match_started(info: Dictionary)
signal input_received(pairs: Array, ack: int)
signal failed(reason: String)
signal result_confirmed(info: Dictionary)
const VERSION = "kolbb-0.1-rules-1-art-2"
const PORT = 7000
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
var server_mode: bool = false
var rooms: Dictionary = {}
var members: Dictionary = {}
var verified: Dictionary = {}
var limits: Dictionary = {}
var next_match: int = 100
var arrival: Dictionary = {}
var join_limits: Dictionary = {}
var housekeeping: float = 0
var room: Dictionary = {}
var room_code: String = ""
var slot: int = 0
var match_id: int = 0
var connected: bool = false
var connecting: bool = false
var elapsed: float = 0.0
var active_elapsed: float = 0.0
var pending_action: String = ""
var pending_code: String = ""
var address: String = ""
var ping_ms: int = 0
var ping_elapsed: float = 0.0
var local_rtt: int = 0
var peer_rtt: Dictionary = {}
var sent_history: Dictionary = {}
var reported: Dictionary = {}
var match_active: bool = false

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): abort("无法连接服务器"))
	multiplayer.server_disconnected.connect(func(): abort("连接中断，本场无结果"))
	multiplayer.peer_disconnected.connect(_departed)
	multiplayer.peer_connected.connect(func(peer):
		if server_mode:
			if arrival.size()-members.size()>=16: multiplayer.multiplayer_peer.disconnect_peer(peer)
			else: arrival[peer]=Time.get_ticks_msec())

func host() -> Error:
	server_mode=true
	var peer=ENetMultiplayerPeer.new()
	var error: Error=peer.create_server(PORT,24,3)
	if error==OK:
		multiplayer.multiplayer_peer=peer
		print("KOLBB relay listening UDP ",PORT," / 4 rooms / ",VERSION)
	return error

func connect_room(hostname: String, code: String = "") -> void:
	disconnect_room()
	address=hostname.strip_edges()
	if address.is_empty():
		failed.emit("请填写服务器地址")
		return
	pending_action="create" if code.is_empty() else "join"
	pending_code=code.to_upper()
	var peer=ENetMultiplayerPeer.new()
	var error: Error=peer.create_client(address,PORT,3)
	if error!=OK:
		failed.emit("无法连接服务器")
		return
	connecting=true;elapsed=0
	multiplayer.multiplayer_peer=peer

func _connected() -> void:
	connected=true;connecting=false
	control.rpc_id(1,"hello",{"version":VERSION})

func disconnect_room() -> void:
	if connected and not server_mode:
		control.rpc_id(1,"leave",{})
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.multiplayer_peer.get_host(): multiplayer.multiplayer_peer.get_host().flush()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	connected=false;connecting=false;match_active=false;room={};room_code="";match_id=0
	sent_history.clear();reported.clear()

func abort(reason: String) -> void:
	if server_mode: return
	disconnect_room()
	failed.emit(reason)

func _process(dt: float) -> void:
	if server_mode:
		housekeeping+=dt
		if housekeeping>=1:
			housekeeping=0
			var now: int=Time.get_ticks_msec()
			for peer in arrival.keys():
				if not members.has(peer) and now-arrival[peer]>15000:
					multiplayer.multiplayer_peer.disconnect_peer(peer)
			for code in rooms.keys():
				var r: Dictionary=rooms[code]
				if r.phase=="room" and now-r.created>600000: end_room(r,"房间空闲超时，已结束")
		return
	if connecting:
		elapsed+=dt
		if elapsed>=8: abort("无法连接服务器")
	if connected:
		ping_elapsed+=dt
		if ping_elapsed>=1:
			ping_elapsed=0
			control.rpc_id(1,"ping",{"time":Time.get_ticks_msec(),"rtt":local_rtt})
		if match_active:
			active_elapsed+=dt
			if active_elapsed>=5: abort("连接中断，本场无结果")

func set_character(ch: int) -> void:
	if connected: control.rpc_id(1,"character",{"character":ch})
func set_ready(value: bool) -> void:
	if connected: control.rpc_id(1,"ready",{"ready":value})
func send_inputs(pairs: Array, ack: int) -> void:
	if not connected or not match_active: return
	for pair in pairs: sent_history[pair[0]]=pair[1]
	for key in sent_history.keys():
		if key<int(pairs[-1][0])-240: sent_history.erase(key)
	input_batch.rpc_id(1,match_id,pairs,ack)
func request_gap(first: int, last: int) -> void:
	if connected: repair_request.rpc_id(1,match_id,first,mini(first+15,last))
func report_hash(frame: int, crc: int) -> void:
	if connected and not reported.has(frame):
		reported[frame]=true
		control.rpc_id(1,"hash",{"match":match_id,"frame":frame,"crc":crc})
func report_result(frame: int, crc: int, wins: Array, winner: int) -> void:
	if connected:
		control.rpc_id(1,"result",{"match":match_id,"frame":frame,"crc":crc,"wins":wins,"winner":winner})

func allowed(peer: int) -> bool:
	var now: int=Time.get_ticks_msec()/1000
	var limit: Array=limits.get(peer,[now,0])
	if limit[0]!=now: limit=[now,0]
	limit[1]+=1;limits[peer]=limit
	return limit[1]<=140

@rpc("any_peer","call_remote","reliable",0)
func control(action: String, payload: Dictionary) -> void:
	if not server_mode: return
	var peer: int=multiplayer.get_remote_sender_id()
	if not allowed(peer) or payload.size()>8: return
	if action=="hello":
		if payload.get("version","")!=VERSION: tell(peer,"error",{"reason":"版本不一致，请更新游戏"});return
		verified[peer]=true
		tell(peer,"hello",{})
		return
	if not verified.has(peer): return
	if action=="ping":
		peer_rtt[peer]=clampi(int(payload.get("rtt",0)),0,10000)
		var other: int=0
		if members.has(peer):
			for p in rooms[members[peer]].peers:
				if p!=peer: other=peer_rtt.get(p,0)
		tell(peer,"pong",{"time":payload.get("time",0),"other":other})
		return
	if action=="leave": leave(peer);return
	if action in ["create","join"]:
		var now: int=Time.get_ticks_msec()/1000
		var join_limit: Array=join_limits.get(peer,[now,0])
		if join_limit[0]!=now: join_limit=[now,0]
		join_limit[1]+=1;join_limits[peer]=join_limit
		if join_limit[1]>2 or members.has(peer): return
		var code: String=str(payload.get("code","")).to_upper()
		if action=="create":
			if rooms.size()>=4: tell(peer,"error",{"reason":"服务器房间已满"});return
			code=new_code()
			rooms[code]={"code":code,"peers":[],"chars":[],"ready":[],"loaded":[],"phase":"room","match":0,"inputs":[{},{}],"highs":[2,2],"acks":[2,2],"hashes":{},"results":{},"go":[],"created":Time.get_ticks_msec()}
		if not rooms.has(code): tell(peer,"error",{"reason":"房间不存在或已结束"});return
		var r: Dictionary=rooms[code]
		if r.peers.size()>=2 or r.phase!="room": tell(peer,"error",{"reason":"房间已满"});return
		r.peers.append(peer);r.chars.append(0 if r.peers.size()==1 else 1);r.ready.append(false);r.loaded.append(false)
		members[peer]=code
		print(Time.get_datetime_string_from_system(true)," room ",code," joined slot ",r.peers.size()-1)
		broadcast_room(r)
		return
	if not members.has(peer): return
	var r: Dictionary=rooms[members[peer]]
	var index: int=r.peers.find(peer)
	r.created=Time.get_ticks_msec()
	if action=="character" and r.phase=="room":
		var ch: int=int(payload.get("character",-1))
		if ch not in [0,1]: return
		r.chars[index]=ch
		for i in r.ready.size(): r.ready[i]=false
		broadcast_room(r)
	elif action=="ready" and r.phase=="room":
		r.ready[index]=bool(payload.get("ready",false))
		broadcast_room(r)
		if r.peers.size()==2 and r.ready[0] and r.ready[1]:
			next_match+=1
			r.match=next_match;r.phase="loading";r.loaded=[false,false];r.seed=randi_range(1,2147483646)
			print(Time.get_datetime_string_from_system(true)," match ",r.match," loading chars ",r.chars)
			r.inputs=[{0:0,1:0,2:0},{0:0,1:0,2:0}];r.highs=[2,2];r.acks=[2,2];r.hashes={};r.results={};r.go=[]
			for i in 2: tell(r.peers[i],"load",{"match":r.match,"slot":i,"chars":r.chars,"seed":r.seed})
	elif action=="loaded" and r.phase=="loading" and payload.get("match",-1)==r.match:
		r.loaded[index]=true
		if r.loaded[0] and r.loaded[1]:
			r.phase="fight"
			for p in r.peers: tell(p,"go",{})
	elif action=="hash" and r.phase=="fight" and payload.get("match",-1)==r.match:
		var n: int=int(payload.get("frame",-1))
		if n<0 or (n+1)%60!=0 or n>mini(r.acks[0],r.acks[1]) or n>mini(r.highs[0],r.highs[1]): return
		if not r.hashes.has(n): r.hashes[n]={}
		r.hashes[n][index]=int(payload.get("crc",-1))
		if r.hashes[n].size()==2:
			if r.hashes[n][0]!=r.hashes[n][1]: end_room(r,"同步异常，本场无结果")
			r.hashes.erase(n)
	elif action=="result" and r.phase=="fight" and payload.get("match",-1)==r.match:
		var n: int=int(payload.get("frame",-1))
		if n<0 or n>mini(r.acks[0],r.acks[1]) or n>mini(r.highs[0],r.highs[1]): return
		r.results[index]=payload
		if r.results.size()==2:
			if r.results[0]!=r.results[1]: end_room(r,"同步异常，本场无结果");return
			for p in r.peers: tell(p,"result",payload)
			print(Time.get_datetime_string_from_system(true)," match ",r.match," confirmed ",payload)
			r.phase="room";r.ready=[false,false]
			broadcast_room(r)

func new_code() -> String:
	var code: String=""
	while code=="" or rooms.has(code):
		code=""
		for i in 6: code+=ALPHABET[randi()%ALPHABET.length()]
	return code
func tell(peer: int, action: String, data: Dictionary) -> void:
	if peer not in multiplayer.get_peers(): return
	var remote: ENetPacketPeer=multiplayer.multiplayer_peer.get_peer(peer)
	if remote and remote.get_state()==ENetPacketPeer.STATE_CONNECTED: message.rpc_id(peer,action,data)
func broadcast_room(r: Dictionary) -> void:
	for i in r.peers.size(): tell(r.peers[i],"room",{"code":r.code,"chars":r.chars,"ready":r.ready,"slot":i,"phase":r.phase})
func leave(peer: int) -> void:
	if not members.has(peer): return
	var code: String=members[peer]
	members.erase(peer)
	if not rooms.has(code): return
	var r: Dictionary=rooms[code]
	if r.phase!="room": end_room(r,"对手已退出，本场无结果");return
	var i: int=r.peers.find(peer)
	if i>=0:
		r.peers.remove_at(i);r.chars.remove_at(i);r.ready.remove_at(i);r.loaded.remove_at(i)
	if r.peers.is_empty(): rooms.erase(code)
	else:
		r.ready=[false]
		broadcast_room(r)
func end_room(r: Dictionary, reason: String) -> void:
	print(Time.get_datetime_string_from_system(true)," room ",r.code," ended ",reason)
	for p in r.peers:
		members.erase(p)
		tell(p,"error",{"reason":reason})
	rooms.erase(r.code)
func _departed(peer: int) -> void:
	if server_mode:
		leave(peer);verified.erase(peer);limits.erase(peer);arrival.erase(peer);join_limits.erase(peer);peer_rtt.erase(peer)

@rpc("authority","call_remote","reliable",0)
func message(action: String, data: Dictionary) -> void:
	if server_mode: return
	match action:
		"hello": control.rpc_id(1,pending_action,{"code":pending_code})
		"error": abort(str(data.get("reason","连接失败")))
		"room":
			room=data;room_code=data.code;slot=data.slot
			room_changed.emit(data)
		"load":
			match_id=data.match;slot=data.slot;room.merge(data,true)
			sent_history.clear();reported.clear()
			control.rpc_id(1,"loaded",{"match":match_id})
		"go":
			active_elapsed=0;match_active=true
			match_started.emit(room)
		"pong":
			local_rtt=maxi(0,Time.get_ticks_msec()-int(data.time))
			ping_ms=local_rtt+int(data.get("other",0))
		"result":
			match_active=false
			result_confirmed.emit(data)

@rpc("any_peer","call_remote","unreliable",1)
func input_batch(id: int, pairs: Array, ack: int) -> void:
	if not server_mode: return
	var peer: int=multiplayer.get_remote_sender_id()
	if not allowed(peer): return
	accept_batch(peer,id,pairs,ack,false)

func accept_batch(peer: int,id: int,pairs: Array,ack: int,reliable: bool) -> void:
	if not members.has(peer): return
	var r: Dictionary=rooms[members[peer]]
	if r.phase!="fight" or r.match!=id or pairs.size()> (16 if reliable else 8) or pairs.is_empty(): return
	var index: int=r.peers.find(peer)
	var previous: int=-1
	for pair in pairs:
		if not pair is Array or pair.size()!=2 or not pair[0] is int or not pair[1] is int: return
		var frame: int=pair[0]
		var bits: int=pair[1]
		if bits<0 or bits>1023 or frame<=previous or frame<r.highs[index]-240 or frame>mini(r.highs[0],r.highs[1])+120: return
		previous=frame
		if r.inputs[index].has(frame) and r.inputs[index][frame]!=bits:
			end_room(r,"输入冲突，本场无结果")
			return
	for pair in pairs: r.inputs[index][pair[0]]=pair[1]
	while r.inputs[index].has(r.highs[index]+1): r.highs[index]+=1
	r.acks[index]=maxi(r.acks[index],mini(ack,r.highs[1-index]))
	if reliable: repaired.rpc_id(r.peers[1-index],id,pairs,r.acks[index])
	else: forwarded.rpc_id(r.peers[1-index],id,pairs,r.acks[index])
	for key in r.inputs[index].keys():
		if key<r.highs[index]-240: r.inputs[index].erase(key)

@rpc("authority","call_remote","unreliable",1)
func forwarded(id: int,pairs: Array,ack: int) -> void:
	if not server_mode and id==match_id:
		active_elapsed=0
		input_received.emit(pairs,ack)
@rpc("authority","call_remote","reliable",2)
func repaired(id: int,pairs: Array,ack: int) -> void:
	forwarded(id,pairs,ack)
@rpc("any_peer","call_remote","reliable",2)
func repair_request(id: int,first: int,last: int) -> void:
	if not server_mode: return
	var peer: int=multiplayer.get_remote_sender_id()
	if not members.has(peer) or not allowed(peer): return
	var r: Dictionary=rooms[members[peer]]
	if r.phase!="fight" or id!=r.match or first<0 or last<first or last-first>15: return
	var index: int=r.peers.find(peer)
	var pairs: Array=[]
	for n in range(first,last+1):
		if r.inputs[1-index].has(n): pairs.append([n,r.inputs[1-index][n]])
	if not pairs.is_empty(): repaired.rpc_id(peer,id,pairs,r.acks[1-index])
	# Ask original sender as well: an uplink gap may never have reached relay.
	resend_request.rpc_id(r.peers[1-index],id,first,last)
@rpc("authority","call_remote","reliable",2)
func resend_request(id: int,first: int,last: int) -> void:
	if server_mode or id!=match_id: return
	var pairs: Array=[]
	for n in range(first,last+1):
		if sent_history.has(n): pairs.append([n,sent_history[n]])
	if not pairs.is_empty(): resend.rpc_id(1,id,pairs)
@rpc("any_peer","call_remote","reliable",2)
func resend(id: int,pairs: Array) -> void:
	if server_mode and allowed(multiplayer.get_remote_sender_id()): accept_batch(multiplayer.get_remote_sender_id(),id,pairs,-1,true)
