extends SceneTree
class Relay extends "res://scripts/network.gd":
	var sent: Array=[]
	func tell(peer: int, action: String, data: Dictionary) -> void:
		sent.append({"peer":peer,"action":action,"data":data.duplicate(true)})
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var relay=Relay.new();root.add_child(relay);relay.server_mode=true
	relay.control("hello",{"version":"kolbb-0.1.2-rules-2-art-3"})
	assert(relay.sent[-1].action=="error" and relay.verified.is_empty(),"old version rejected")
	relay.control("hello",{"version":relay.VERSION})
	assert(relay.verified.has(0),"current version accepted")
	relay.control("create",{})
	var room: Dictionary=relay.rooms[relay.members[0]]
	for ch in [0,1,2,0]:
		room.ready[0]=true
		relay.control("character",{"character":ch})
		assert(room.chars[0]==ch and not room.ready[0],"roster selection clears readiness")
	for ch in [-1,3,99]:
		relay.control("character",{"character":ch});assert(room.chars[0]==0,"invalid character rejected")
	relay.control("character",{"character":2})
	room.phase="fight";relay.control("character",{"character":0})
	assert(room.chars[0]==2,"no switching during fight")
	var result: Dictionary={"match":room.match,"frame":99,"crc":123,"wins":[2,0],"winner":0}
	room.highs=[102,102];room.acks=[98,98]
	relay.control("result",result)
	assert(room.results.is_empty(),"result may arrive before input ACK")
	room.acks=[102,102];room.results[1]=result
	relay.control("result",result)
	assert(room.phase=="room" and relay.sent[-2].action=="result","retry confirms after both ACKs")
	relay.pending_result=result.duplicate();relay.message("result",result)
	# Server-mode message handler deliberately ignores client messages.
	relay.server_mode=false;relay.message("result",result)
	assert(relay.pending_result.is_empty(),"confirmation stops retries")
	relay.pending_result=result.duplicate();relay.disconnect_room()
	assert(relay.pending_result.is_empty(),"leaving clears pending result")
	relay.queue_free();await process_frame
	print("PASS roster protocol: version gate, all characters, invalid IDs, ready reset and fight lock")
	quit()
