extends RefCounted
const Commands = preload("res://scripts/commands.gd")
const FP = 256
const GROUND = 292 * FP
const NAMES = ["RajerWei", "JU GUAI", "little black"]
const PREFIX = ["RW-", "JG-", "LB-"]
const ART = ["rajer", "juguai", "littleblack"]
const FORWARD_SPEED = [704,576,704]
const BACK_SPEED = [576,448,576]
const RUN_SPEED = [1152,1024,1152]
const BACKSTEP_DISTANCE = [64,56,64]
const BODY_WIDTH = [18,24,18]
const THROW_RANGE = [50,56,50]
const PROJECTILE_OFFSET = [32,36,32]
const PROJECTILE_HEIGHT = [88,84,88]
const PROJECTILE_SPEED = [4,5,4]
const PROJECTILE_LIFE = [150,120,150]
const PROJECTILE_RADIUS = [9,8,10]
static var CRC_TABLE: PackedInt64Array = make_crc_table()
var moves: Dictionary = {}
var state: Dictionary = {}
var events: Array = []

func _init() -> void:
	moves = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moves.json"))
	for id in moves:
		for key in ["s","a","r","damage","h","b","cost"]:
			moves[id][key] = int(moves[id][key])
	for ch in 2:
		var p: String = "P%d-" % (ch+1)
		add_move(p+"S1", ["大便投掷","积分投掷"][ch],16+ch*2,1,21+ch*2,55+ch*5,26+ch*2,16+ch,0,"projectile")
		add_move(p+"S2", ["地面汉堡","绩效面谈"][ch],24 if ch==0 else 10,1 if ch==0 else 14,29 if ch==0 else 22,0 if ch==0 else 25,16,10,100 if ch==0 else 0,"burger" if ch==0 else "talk")
		add_move(p+"S3", ["肯德基挚友","强制加班"][ch],28 if ch==0 else 7,4 if ch==0 else 2,30,120 if ch==0 else 130,24,24,100 if ch==0 else 0,"summon" if ch==0 else "grab")
		add_move(p+"U1", ["捆绑 play","你被解雇了！"][ch],16 if ch==0 else 18,2 if ch==0 else 36,36 if ch==0 else 30,240 if ch==0 else 40,14,6,100,"room" if ch==0 else "papers")
		add_move(PREFIX[ch]+"THROW","普通投",4,1,25,100+ch*10,24,0,0,"throw")
	add_move("P3-S1","篮球",16,1,21,60,26,16,0,"projectile")
	add_move("P3-S2","铁山靠",12,8,26,90,28,18,0,"shoulder")
	add_move("P3-S3","音爆",10,6,28,80,24,18,0,"sonic")
	moves["P3-S3"].launch=true
	add_move("P3-U1","鸡你太美",18,28,30,40,14,12,100,"dance")
	add_move("P3-S4","露出鸡脚",14,21,26,40,22,16,0,"trousers")
	add_move("LB-THROW","普通投",4,1,25,100,24,0,0,"throw")
	reset()

func add_move(id: String, title: String, s: int, a: int, r: int, damage: int, h: int, b: int, cost: int, kind: String) -> void:
	moves[id] = {"id":id,"name":title,"s":s,"a":a,"r":r,"damage":damage,"h":h,"b":b,"cost":cost,"kind":kind,"box":[0,0,0,0],"level":"mid","launch":false,"hard":false,"cancel":"S" if kind in ["projectile","summon","talk","shoulder","sonic"] else ""}

func fighter(ch: int, slot: int, energy: int = 0) -> Dictionary:
	return {"char":ch,"slot":slot,"x":(160+slot*320)*FP,"y":GROUND,"vx":0,"vy":0,"face":1 if slot==0 else -1,"hp":1000,"energy":energy,"max":0,"max_total":600,"mode":"idle","age":0,"action_id":0,"move":"","hits":[],"contact":false,"confirmed_hit":false,"chain":[],"combo":0,"combo_damage":0,"combo_age":0,"combo_display":0,"combo_moves":[],"combo_scale":100,"hitstun":0,"invthrow":0,"airhits":0,"air_attack":false,"hard":false,"knock":0,"knock_time":0,"knock_rem":0,"pickup":0,"reaction":"","reaction_time":0,"stain":0,"input":Commands.fresh(),"run":false,"jump_big":false,"jump_forward":0,"throw_back":false,"enhanced":false,"target_x":0,"start_x":0,"blocked_this":false,"energy_awards":[],"flash_meter":0}

func reset(chars: Array = [0,1], seed_value: int = 1234567, match_id: int = 1) -> void:
	state = {"frame":0,"world":0,"time":5940,"round":1,"wins":[0,0],"draws":0,"phase":"intro","phase_time":120,"winner":-1,"freeze":0,"cinema":{},"fighters":[fighter(int(chars[0]),0),fighter(int(chars[1]),1)],"entities":[],"next_id":1,"rng":maxi(1,seed_value),"match":match_id}
	events.clear()

func event(kind: String, slot: int = -1, data: Dictionary = {}) -> void:
	var pos: int = state.fighters[slot].x if slot>=0 else 320*FP
	var e: Dictionary = {"id":"%d/%d/%d" % [state.match,state.frame,events.size()],"kind":kind,"slot":slot,"x":pos/FP,"y":200}
	e.merge(data,true)
	events.append(e)

func rng(maximum: int) -> int:
	var x: int = state.rng
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	state.rng = x & 0xffffffff
	return int(state.rng) % maxi(1,maximum)

func is_free(f: Dictionary) -> bool:
	return f.mode in ["idle","walk","run","crouch","air"]

func grounded(f: Dictionary) -> bool:
	return f.y == GROUND

func step(buttons: Array) -> Array:
	events.clear()
	state.frame += 1
	var frozen: bool = state.freeze > 0 or not state.cinema.is_empty()
	for i in 2:
		Commands.sample(state.fighters[i].input,int(buttons[i]),state.fighters[i].face,state.fighters[i].char,frozen)
	if state.phase != "fight":
		advance_phase()
		return events
	if state.freeze > 0:
		state.freeze -= 1
		return events
	if not state.cinema.is_empty():
		advance_cinema(buttons)
		return events
	state.world += 1
	for f in state.fighters:
		f.blocked_this = false
		for key in ["max","invthrow","pickup","reaction_time","stain","flash_meter"]:
			f[key] = maxi(0,f[key]-1)
		if f.reaction_time == 0: f.reaction = ""
		f.combo_age = maxi(0,f.combo_age-1)
		if is_free(f) and f.hitstun == 0:
			f.combo = 0
			f.combo_moves.clear()
			f.airhits = 0 if grounded(f) else f.airhits
		update_facing(f)
	# Intent acceptance does not inspect the opponent's new action.
	for i in 2:
		accept_input(state.fighters[i],state.fighters[1-i])
	for f in state.fighters:
		move_fighter(f)
	push_fighters()
	for f in state.fighters:
		spawn_events(f)
	advance_entities()
	cancel_projectiles()
	var contacts: Array = []
	var grabs: Array = []
	for i in 2:
		collect_attacks(state.fighters[i],state.fighters[1-i],contacts,grabs)
	for e in state.entities:
		collect_entity(e,contacts)
	var hit_slots: Array = []
	for hit in contacts:
		if not hit.block and hit.target not in hit_slots: hit_slots.append(hit.target)
	for hit in contacts:
		apply_hit(hit)
	# Strike beats throw, even if the opposing throw was collected first.
	var legal_grabs: Array = []
	for grab in grabs:
		if grab.owner not in hit_slots and grab.target not in hit_slots and state.fighters[grab.target].hp > 0:
			legal_grabs.append(grab)
	if legal_grabs.size() == 2:
		throw_break()
	elif legal_grabs.size() == 1:
		start_cinema(legal_grabs[0])
	if state.fighters[0].hp > 0 and state.fighters[1].hp > 0 and state.cinema.is_empty():
		pick_food()
	for f in state.fighters:
		finish_frame(f)
	state.entities = state.entities.filter(func(e): return not e.get("dead",false))
	state.time = maxi(0,state.time-1)
	if state.cinema.is_empty(): check_end()
	return events

func advance_phase() -> void:
	if state.phase == "done": return
	state.phase_time -= 1
	if state.phase_time > 0: return
	match state.phase:
		"intro":
			state.phase = "round"
			state.phase_time = 60
			event("round")
		"round":
			state.phase = "ready"
			state.phase_time = 30
			event("fight")
		"ready":
			state.phase = "fight"
			for f in state.fighters: f.input = Commands.fresh()
		"result":
			if state.wins[0] >= 2 or state.wins[1] >= 2 or state.draws >= 3:
				state.phase = "done"
				event("victory",state.winner)
			else:
				var fs: Array = state.fighters
				state.fighters = [fighter(fs[0].char,0,fs[0].energy),fighter(fs[1].char,1,fs[1].energy)]
				state.time = 5940
				state.entities.clear()
				state.cinema.clear()
				state.freeze = 0
				state.round += 1
				state.phase = "round"
				state.phase_time = 60
				event("round")

func update_facing(f: Dictionary) -> void:
	if not is_free(f) or not grounded(f): return
	var other: Dictionary = state.fighters[1-f.slot]
	var face: int = signi(other.x-f.x)
	if face and face != f.face:
		f.face = face
		f.input.history.clear()
		f.input.motions.clear()
		f.input.dir = Commands.direction(f.input.prev,face)

func accept_input(f: Dictionary, other: Dictionary) -> void:
	var cmd: String = f.input.buffer
	var dir: int = f.input.dir
	if cmd == "MAX":
		var quick: bool = f.mode=="attack" and f.confirmed_hit and "Q" in moves[f.move].cancel
		if grounded(f) and f.max==0 and (is_free(f) or quick):
			var cost: int = 200 if quick else 100
			if pay(f,cost):
				f.mode = "max_start"
				f.age = 0
				f.max_total = 360 if quick else 600
				f.move = ""
				if quick:
					f.max = 360
					f.mode = "idle"
					state.freeze = maxi(state.freeze,6)
				event("max",f.slot)
			Commands.consume(f.input)
			return
	if cmd == "ROLL" and is_free(f) and grounded(f):
		f.mode = "roll"
		f.age = 0
		f.vx = f.face * (-1 if dir in [1,4,7] else 1)
		Commands.consume(f.input)
		event("roll",f.slot)
		return
	if cmd in ["A","B","C","D","S1","S2","S3","S4","U1"]:
		var special: bool = cmd.begins_with("S") or cmd=="U1"
		var id: String
		if special:
			id = "P%d-%s" % [f.char+1,cmd]
		else:
			id = PREFIX[f.char] + ("j" if not grounded(f) else "2" if dir in [1,2,3] else "5") + cmd
			if cmd == "C" and dir in [4,6] and grounded(f) and abs(f.x-other.x) <= THROW_RANGE[f.char]*FP and is_free(f):
				id = PREFIX[f.char]+"THROW"
		var cancel: bool = can_cancel(f,id)
		if (is_free(f) or cancel) and (grounded(f) or (not special and not f.air_attack)):
			if special and not grounded(f): return
			Commands.consume(f.input)
			if not can_spawn(f,id):
				f.flash_meter = 12
				event("denied",f.slot,{"text":"场上已有同类道具"})
				return
			var cost: int = moves[id].cost
			var enhanced: bool = cmd=="U1" and f.max>0
			if enhanced: cost += 100
			if not pay(f,cost): return
			if cancel and moves[f.move].kind != "normal" and cmd != "U1": f.max -= 120
			if not cancel: f.chain.clear()
			f.chain.append(id)
			f.mode = "attack"
			f.move = id
			f.action_id = state.next_id
			state.next_id += 1
			f.age = 0
			f.hits.clear()
			f.energy_awards.clear()
			f.contact = false
			f.confirmed_hit = false
			f.enhanced = enhanced
			f.throw_back = dir==4
			f.target_x = clampi(f.x+f.face*144*FP,64*FP,576*FP)
			f.start_x = f.x
			if not grounded(f): f.air_attack = true
			if cmd=="U1":
				f.max = 0
				state.freeze = maxi(state.freeze,12)
				event("super",f.slot,{"text":moves[id].name})
			else: event("action",f.slot,{"move":id,"sound":moves[id].kind})
			return
	if not is_free(f) or not grounded(f): return
	if dir in [7,8,9]:
		f.jump_big = f.run
		for item in f.input.history:
			if item[0] in [1,2,3] and f.input.clock-item[1]<=12: f.jump_big = true
		f.mode = "jump_prepare"
		f.age = 0
		f.jump_forward = -1 if dir==7 else 1 if dir==9 else 0
		return
	if f.input.dash == 4:
		f.mode = "backstep"
		f.age = 0
		f.start_x = f.x
		return
	if f.input.dash == 6: f.run = true
	if dir != 6: f.run = false
	f.mode = "crouch" if dir in [1,2,3] else "run" if f.run else "walk" if dir in [4,6] else "idle"

func pay(f: Dictionary, cost: int) -> bool:
	if f.energy < cost:
		f.flash_meter = 12
		event("denied",f.slot,{"text":"需要 %d 能量" % cost})
		return false
	f.energy -= cost
	return true

func can_cancel(f: Dictionary, id: String) -> bool:
	if f.mode != "attack" or not f.contact or id in f.chain: return false
	var old: Dictionary = moves[f.move]
	var next: Dictionary = moves[id]
	if old.kind=="normal":
		if next.kind != "normal": return "S" in old.cancel
		if "L" not in old.cancel: return false
		var lights: int = 0
		for m in f.chain:
			if m.ends_with("A") or m.ends_with("B"): lights += 1
		return "Q" in next.cancel or ("L" in next.cancel and lights < 2)
	if id.ends_with("U1"): return "S" in old.cancel
	if f.max <= 120: return false
	var pair: Array = [["P1-S1","P1-S3"],["P2-S1","P2-S2"],["P3-S1","P3-S2"]][f.char]
	return f.move in pair and id in pair

func can_spawn(f: Dictionary, id: String) -> bool:
	var kind: String = moves[id].kind
	for e in state.entities:
		if e.owner != f.slot or e.get("dead",false): continue
		if kind=="projectile" and e.kind=="projectile" and moves[e.move].kind=="projectile": return false
		if kind=="trousers" and e.get("move","")==id: return false
		if kind=="burger" and e.kind=="burger": return false
		if kind=="summon" and e.kind in ["summon","pizza"]: return false
	return true

func move_fighter(f: Dictionary) -> void:
	if f.knock_time>0:
		var delta: int = f.knock / 5
		f.x += delta
		f.knock_time -= 1
	if f.mode in ["walk","run"]:
		var forward: bool = f.input.dir==6
		var speed: int = FORWARD_SPEED[f.char] if forward else BACK_SPEED[f.char]
		if f.mode=="run": speed = RUN_SPEED[f.char]
		f.x += speed*f.face*(1 if forward else -1)
	elif f.mode=="backstep":
		f.x = f.start_x-f.face*(BACKSTEP_DISTANCE[f.char]*FP*(f.age+1)/24)
	elif f.mode=="roll":
		f.x += (80*FP*(f.age+1)/30-80*FP*f.age/30)*f.vx
	elif f.mode=="attack" and moves[f.move].kind=="room" and f.age<16:
		f.x += f.face*4*FP
	elif f.mode=="attack" and moves[f.move].kind=="shoulder" and f.age>=4 and f.age<20:
		f.x += f.face*4*FP
	if f.mode=="jump_prepare" and f.age >= (4 if f.jump_big else 3):
		f.mode = "air"
		f.age = 0
		f.vy = -1984 if f.jump_big else -1664 if f.input.dir in [7,8,9] else -1280
		var speed: int = (RUN_SPEED[f.char]) if f.jump_big else FORWARD_SPEED[f.char] if f.jump_forward>0 else BACK_SPEED[f.char]
		f.vx = speed*f.face*f.jump_forward
		f.air_attack = false
		event("jump",f.slot)
	if f.y<GROUND or f.vy<0:
		f.x += f.vx
		f.y += f.vy
		f.vy += 96
		if f.y>=GROUND:
			f.y = GROUND
			f.vy = 0
			f.vx = 0
			f.age = 0
			f.move = ""
			f.mode = "down" if f.mode=="hurt" else "land"
			f.air_attack = false
			event("land",f.slot)
	var width: int = BODY_WIDTH[f.char]*FP
	var unclamped: int = f.x
	f.x = clampi(f.x,16*FP+width,624*FP-width)
	if f.knock_time>0 and unclamped!=f.x:
		var other: Dictionary = state.fighters[1-f.slot]
		other.x -= unclamped-f.x

func push_fighters() -> void:
	var a: Dictionary = state.fighters[0]
	var b: Dictionary = state.fighters[1]
	if not grounded(a) or not grounded(b) or a.mode=="roll" or b.mode=="roll": return
	var aw: int = BODY_WIDTH[a.char]*FP
	var bw: int = BODY_WIDTH[b.char]*FP
	var overlap: int = aw+bw-absi(a.x-b.x)
	if overlap<=0: return
	var sign_x: int = 1 if b.x>=a.x else -1
	a.x -= sign_x*(overlap/2)
	b.x += sign_x*(overlap-overlap/2)
	var ax: int = clampi(a.x,16*FP+aw,624*FP-aw)
	b.x += ax-a.x
	a.x = ax
	var bx: int = clampi(b.x,16*FP+bw,624*FP-bw)
	a.x += bx-b.x
	b.x = bx
	a.x = clampi(a.x,16*FP+aw,624*FP-aw)

func spawn_events(f: Dictionary) -> void:
	if f.mode!="attack": return
	var m: Dictionary = moves[f.move]
	var t: int = f.age
	if m.kind=="projectile" and t==m.s:
		entity({"kind":"projectile","owner":f.slot,"x":f.x+f.face*PROJECTILE_OFFSET[f.char]*FP,"y":f.y-PROJECTILE_HEIGHT[f.char]*FP,"vx":f.face*PROJECTILE_SPEED[f.char]*FP,"life":PROJECTILE_LIFE[f.char],"age":-1,"char":f.char,"move":f.move,"face":f.face,"hits":[],"source_frame":f.action_id})
		event("projectile",f.slot)
	elif m.kind=="trousers" and t==m.s:
		entity({"kind":"projectile","owner":f.slot,"x":f.x+f.face*32*FP,"y":f.y-88*FP,"vx":f.face*5*FP,"life":100,"age":-1,"char":f.char,"move":f.move,"face":f.face,"hits":[],"source_frame":f.action_id})
	elif m.kind=="burger" and t==24:
		food("burger",f.slot,f.x+f.face*24*FP,f.y-96*FP,clampi(f.x+f.face*80*FP,32*FP,608*FP),20)
	elif m.kind=="summon" and t==28:
		entity({"kind":"summon","owner":f.slot,"x":f.target_x,"y":GROUND,"origin":f.start_x,"age":-1,"life":32,"hits":[],"move":f.move,"face":f.face,"source_frame":f.action_id})
		event("summon",f.slot,{"x":f.target_x/FP,"y":280})
	elif m.kind=="papers" and t in [18,26,34,42,50]:
		entity({"kind":"papers","owner":f.slot,"x":f.x,"y":GROUND,"face":f.face,"age":-1,"life":4,"hits":[],"move":f.move,"damage":60 if f.enhanced else 40,"source_frame":f.action_id,"wave":(t-18)/8})
		event("papers",f.slot,{"wave":(t-18)/8})

func entity(data: Dictionary) -> void:
	data.id = state.next_id
	state.next_id += 1
	data.dead = false
	state.entities.append(data)

func food(kind: String, owner: int, sx: int, sy: int, ex: int, travel: int) -> void:
	entity({"kind":kind,"owner":owner,"x":sx,"y":sy,"sx":sx,"sy":sy,"ex":ex,"travel":travel,"age":-1,"life":travel+(360 if kind=="burger" else 240)})

func advance_entities() -> void:
	for e in state.entities:
		e.age += 1
		e.life -= 1
		if e.life<0: e.dead = true
		if e.kind=="projectile":
			if e.age>0: e.x += e.vx
			if e.x < -24*FP or e.x>664*FP: e.dead = true
		elif e.kind in ["burger","pizza"]:
			var t: int = mini(e.age,e.travel)
			var total: int = e.travel
			var height: int = (24 if e.kind=="burger" else 32)*FP
			e.x = e.sx+(e.ex-e.sx)*t/total
			e.y = e.sy+(GROUND-e.sy)*t/total-4*height*t*(total-t)/(total*total)
		elif e.kind=="summon" and e.age==4:
			for offset in [-32,0,32]:
				food("pizza",e.owner,e.x,GROUND-110*FP,clampi(e.origin+offset*FP,32*FP,608*FP),24)

func rect(x: int, y: int, face: int, box: Array) -> Rect2i:
	var left: int = int(box[0])*FP
	var right: int = int(box[1])*FP
	return Rect2i(x+(left if face==1 else -right),y+int(box[2])*FP,right-left,(int(box[3])-int(box[2]))*FP)

func hurtbox(f: Dictionary) -> Rect2i:
	if f.mode in ["down","getup"]: return Rect2i()
	if f.mode=="roll" and f.age>=4 and f.age<=15: return Rect2i()
	var crouch: bool = f.mode=="crouch" or (f.mode=="guard" and f.input.dir in [1,2,3]) or (f.mode=="attack" and f.move.contains("-2"))
	var box: Array
	if crouch: box = [-25,25,-92,-6] if f.char==1 else [-18,18,-88,-6]
	else: box = [-23,23,-138,-6] if f.char==1 else [-15,15,-142,-6]
	return rect(f.x,f.y,1,box)

func attackbox(f: Dictionary) -> Rect2i:
	if f.mode!="attack": return Rect2i()
	var m: Dictionary = moves[f.move]
	if f.age<m.s or f.age>=m.s+m.a: return Rect2i()
	if m.kind=="normal": return rect(f.x,f.y,f.face,m.box)
	if m.kind=="shoulder": return rect(f.x,f.y,f.face,[8,66,-120,-34])
	if m.kind=="sonic": return rect(f.x,f.y,f.face,[4,84,-210,-48])
	if m.kind=="trousers" and f.age>=30: return rect(f.x,f.y,f.face,[8,96,-112,-32])
	if m.kind=="dance" and (f.age-m.s)%8<4:
		return rect(f.x,f.y,f.face,[8,108 if f.age>=42 else 88,-126,-30])
	if m.kind=="talk":
		if f.age<=12: return rect(f.x,f.y,f.face,[16,80,-118,-54])
		if f.age>=20: return rect(f.x,f.y,f.face,[16,100,-126,-38])
	return Rect2i()

func guardable(f: Dictionary, level: String, face: int) -> bool:
	if not grounded(f) or (not is_free(f) and f.mode!="guard"): return false
	# Defense is relative to incoming attacker, allowing cross-up reads.
	var dir: int = Commands.direction(f.input.prev,-face)
	if f.mode=="guard": dir = f.input.dir
	return (dir==4 and level!="low") or (dir==1 and level!="overhead")

func collect_attacks(f: Dictionary, target: Dictionary, contacts: Array, grabs: Array) -> void:
	if f.mode!="attack": return
	var m: Dictionary = moves[f.move]
	if f.age<m.s or f.age>=m.s+m.a: return
	if m.kind in ["throw","grab","room"]:
		var range_px: int = 88 if m.kind=="room" else 58 if m.kind=="grab" else THROW_RANGE[f.char]
		if (target.x-f.x)*f.face>=0 and absi(target.x-f.x)<=range_px*FP and throwable(target,m.kind=="room"):
			grabs.append({"owner":f.slot,"target":target.slot,"move":f.move,"kind":m.kind})
		return
	var sub: int = (f.age-m.s)/8 if m.kind=="dance" else 1 if m.kind=="talk" and f.age>=20 else 0
	var box: Rect2i = attackbox(f)
	if box.has_area() and box.intersects(hurtbox(target)) and sub not in f.hits and target.airhits<2:
		f.hits.append(sub)
		var damage: int = 75 if m.kind=="talk" and sub==1 else m.damage
		var h: int = 24 if m.kind=="talk" and sub==1 else m.h
		var b: int = 17 if m.kind=="talk" and sub==1 else m.b
		if m.kind=="dance": damage=(140 if f.enhanced else 120) if sub==3 else (60 if f.enhanced else 40)
		if m.kind=="trousers": damage=70
		var hit: Dictionary=make_hit(f,target,m,damage,h,b,sub,f.move+"/"+str(f.action_id),guardable(target,m.level,f.face))
		if m.kind=="dance" and sub==3: hit.hard=true
		contacts.append(hit)

func throwable(f: Dictionary, room: bool = false) -> bool:
	if not grounded(f) or f.invthrow>0 or f.mode in ["down","getup","jump_prepare","guard"]: return false
	return f.mode!="hurt" or room

func make_hit(f: Dictionary, target: Dictionary, m: Dictionary, damage: int, h: int, b: int, sub: int, source: String, block: bool) -> Dictionary:
	return {"owner":f.slot,"target":target.slot,"move":m.id,"kind":m.kind,"damage":damage,"h":h,"b":b,"sub":sub,"source":source,"block":block,"face":f.face,"launch":m.launch,"hard":m.hard,"x":target.x/FP,"y":(target.y/FP)-85}

func collect_entity(e: Dictionary, contacts: Array) -> void:
	if e.dead or e.kind not in ["projectile","summon","papers"]: return
	if e.kind=="summon" and e.age>3: return
	var f: Dictionary = state.fighters[e.owner]
	var target: Dictionary = state.fighters[1-e.owner]
	if target.slot in e.hits or target.airhits>=2: return
	var box: Rect2i
	if e.kind=="projectile":
		var size: int = PROJECTILE_RADIUS[e.char]
		box = rect(e.x,e.y,1,[-size,size,-size,size])
	elif e.kind=="summon": box = rect(e.x,e.y,1,[-56,56,-160,0])
	else: box = rect(e.x,e.y,e.face,[32,608,-72,-8])
	if not box.intersects(hurtbox(target)): return
	e.hits.append(target.slot)
	var m: Dictionary = moves[e.move]
	var hit: Dictionary = make_hit(f,target,m,e.get("damage",m.damage),m.h,m.b,e.get("wave",0),e.move+"/"+str(e.source_frame),guardable(target,"mid",e.face))
	hit.face = e.face
	hit.launch = e.kind=="summon"
	contacts.append(hit)
	if e.kind=="projectile": e.dead = true

func cancel_projectiles() -> void:
	for i in state.entities.size():
		var a: Dictionary = state.entities[i]
		if a.kind!="projectile" or a.dead: continue
		for j in range(i+1,state.entities.size()):
			var b: Dictionary = state.entities[j]
			if b.kind!="projectile" or b.dead or a.owner==b.owner: continue
			if abs(a.x-b.x)<18*FP and abs(a.y-b.y)<18*FP:
				a.dead = true
				b.dead = true
				event("clash",a.owner,{"x":(a.x+b.x)/(2*FP),"y":a.y/FP})

func add_energy(f: Dictionary, amount: int) -> void:
	var old: int = f.energy/100
	f.energy = mini(300,f.energy+amount)
	if f.energy/100>old: event("stock",f.slot)

func apply_hit(hit: Dictionary) -> void:
	var a: Dictionary = state.fighters[hit.owner]
	var b: Dictionary = state.fighters[hit.target]
	var m: Dictionary = moves[hit.move]
	var normal: bool = hit.kind=="normal"
	var heavy: bool = normal and (hit.move.ends_with("C") or hit.move.ends_with("D"))
	var block: bool = hit.block
	var damage: int = hit.damage
	if block:
		damage = 0 if normal else mini(maxi(0,b.hp-1),damage/10)
		b.mode = "guard"
		b.hitstun = hit.b+1
	else:
		if hit.source not in b.combo_moves:
			b.combo_moves.append(hit.source)
			b.combo += 1
			b.combo_scale = maxi(40,110-b.combo*10)
			if b.combo==1: b.combo_damage = 0
		damage = damage*b.combo_scale/100
		b.combo_damage += damage
		b.combo_age = 60
		b.combo_display = b.combo
		if not grounded(b): b.airhits += 1
		b.mode = "hurt"
		b.hitstun = hit.h+1
		b.hard = hit.hard
		if hit.launch:
			b.vy = -1536
			b.vx = hit.face*512
		if hit.hard:
			b.mode = "down"
			b.hitstun = 0
		if hit.kind=="projectile" and a.char in [0,1]:
			b.reaction = "poop" if a.char==0 else "laugh"
			b.reaction_time = 18 if a.char==0 else 22
			if a.char==0: b.stain = 45
	b.hp = maxi(0,b.hp-damage)
	b.age = 0
	b.move = ""
	b.blocked_this = true
	var push: int = (10 if heavy else 6) if block and normal else (18 if heavy else 10) if normal else 12 if block else 20
	if hit.kind=="papers" or (hit.kind=="talk" and hit.sub==0) or (hit.kind=="dance" and hit.sub<3): push = 4
	b.knock = push*FP*hit.face
	b.knock_time = 5
	if hit.kind=="papers": b.knock_time = 1; b.knock *= 5
	if a.move==hit.move:
		a.contact = true
		if not block: a.confirmed_hit = true
	if hit.source not in a.energy_awards:
		a.energy_awards.append(hit.source)
		if m.cost==0:
			add_energy(a,(6 if heavy else 4) if block and normal else (12 if heavy else 8) if normal else 5 if block else 10)
		add_energy(b,3 if block else 6)
	var pause: int = (5 if heavy else 3) if block and normal else (8 if heavy else 5) if normal else 4 if block else 7
	if hit.kind=="summon": pause = 6 if block else 10
	if hit.kind=="papers" or (hit.kind=="dance" and hit.sub<3): pause = 2 if block else 3
	state.freeze = maxi(state.freeze,pause)
	event("block" if block else "hit",hit.owner,{"target":hit.target,"x":hit.x,"y":hit.y,"damage":damage,"heavy":heavy or hit.kind in ["summon","shoulder","sonic"] or (hit.kind=="dance" and hit.sub==3),"move":hit.move,"combo":b.combo,"combo_damage":b.combo_damage,"combo_start":b.combo==1 and b.combo_damage==damage})

func finish_frame(f: Dictionary) -> void:
	f.age += 1
	match f.mode:
		"attack":
			var m: Dictionary = moves[f.move]
			if f.age >= m.s+m.a+m.r: recover(f)
		"max_start":
			if f.age>=12:
				f.max = 600
				recover(f)
		"backstep":
			if f.age>=24: recover(f)
		"roll":
			if f.age>=30: recover(f)
		"land":
			if f.age>=4: recover(f)
		"hurt","guard":
			f.hitstun = maxi(0,f.hitstun-1)
			if f.hitstun==0 and grounded(f): recover(f)
		"down":
			if f.age >= (36 if f.hard else 24): f.mode="getup"; f.age=0
		"getup":
			if f.age>=12:
				f.invthrow = 9
				recover(f)
		"recover":
			f.hitstun -= 1
			if f.hitstun<=0: recover(f)

func recover(f: Dictionary) -> void:
	f.mode = "idle" if grounded(f) else "air"
	f.move = ""
	f.age = 0
	f.run = false
	f.hits.clear()

func start_cinema(grab: Dictionary) -> void:
	var a: Dictionary = state.fighters[grab.owner]
	var b: Dictionary = state.fighters[grab.target]
	state.cinema = {"owner":grab.owner,"target":grab.target,"kind":grab.kind,"move":grab.move,"age":0,"damage":moves[grab.move].damage+(80 if a.enhanced and grab.kind=="room" else 0),"face":a.face,"back":a.throw_back,"paid":false}
	a.mode = "cinema"
	b.mode = "cinema"
	b.blocked_this = true
	event("capture",a.slot,{"text":moves[grab.move].name})

func throw_break() -> void:
	state.cinema = {}
	for f in state.fighters:
		f.mode = "recover"
		f.hitstun = 12
		f.x -= f.face*24*FP
		f.move = ""
		f.age = 0
	push_fighters()
	event("break",-1)

func advance_cinema(buttons: Array) -> void:
	var c: Dictionary = state.cinema
	var a: Dictionary = state.fighters[c.owner]
	var b: Dictionary = state.fighters[c.target]
	if c.kind=="throw" and c.age<7 and int(buttons[c.target]) & (Commands.C|Commands.D):
		throw_break()
		return
	var strike: int = 60 if c.kind=="room" else 36 if c.kind=="grab" else 18
	var total: int = 72 if c.kind=="room" else 54 if c.kind=="grab" else 30
	if c.kind=="room" and c.age in [24,36,48]: event("whip",c.owner)
	if c.age==strike and not c.paid:
		c.paid = true
		var damage: int = c.damage
		if c.kind=="room":
			b.combo += 1
			damage = damage*maxi(40,110-b.combo*10)/100
		b.hp = maxi(0,b.hp-damage)
		add_energy(b,6)
		if c.kind=="throw": add_energy(a,10)
		event("slam",c.owner,{"target":c.target,"damage":damage})
	c.age += 1
	if c.age>=total:
		var distance: int = 96 if c.kind=="room" else 88 if c.kind=="grab" else 80
		var face: int = -c.face if c.back and c.kind=="throw" else c.face
		b.x = a.x+face*distance*FP
		var w: int = BODY_WIDTH[b.char]*FP
		var clamped: int = clampi(b.x,(16*FP)+w,(624*FP)-w)
		a.x += clamped-b.x
		b.x = clamped
		b.y = GROUND
		b.mode = "down"
		b.hard = c.kind!="throw"
		b.age = 0
		b.move = ""
		a.mode = "recover"
		a.move = ""
		a.hitstun = 18 if c.kind=="room" else 16 if c.kind=="grab" else 8
		a.age = 0
		state.cinema = {}
		check_end()

func pick_food() -> void:
	var candidates: Array = []
	for e in state.entities:
		if e.kind not in ["burger","pizza"] or e.dead: continue
		if e.age<e.travel+(30 if e.kind=="burger" else 12): continue
		for f in state.fighters:
			if not is_free(f) or not grounded(f) or f.pickup>0 or f.blocked_this or f.hp<=0: continue
			if e.kind=="pizza" and e.owner!=f.slot: continue
			if e.owner==f.slot and f.hp>=1000: continue
			var distance: int = absi(f.x-e.x)
			if distance<=18*FP: candidates.append({"distance":distance,"owner_priority":0 if e.owner==f.slot else 1,"slot":f.slot,"entity":e})
	candidates.sort_custom(func(a,b):
		if a.distance!=b.distance: return a.distance<b.distance
		if a.entity.id!=b.entity.id: return a.entity.id<b.entity.id
		return a.owner_priority<b.owner_priority)
	for c in candidates:
		var f: Dictionary = state.fighters[c.slot]
		var e: Dictionary = c.entity
		if f.pickup>0 or e.dead: continue
		var amount: int = 50 if e.kind=="pizza" else 200 if e.owner==f.slot else -200
		f.hp = clampi(f.hp+amount,0,1000)
		f.pickup = 12
		e.dead = true
		event("pickup",f.slot,{"damage":-amount,"text":"+%d" % amount if amount>0 else str(amount),"y":240})

func check_end() -> void:
	if state.phase!="fight": return
	var a: Dictionary = state.fighters[0]
	var b: Dictionary = state.fighters[1]
	if a.hp>0 and b.hp>0 and state.time>0: return
	state.winner = 0 if a.hp>b.hp else 1 if b.hp>a.hp else -1
	if state.winner>=0:
		state.wins[state.winner] += 1
		state.draws = 0
	else:
		state.draws += 1
		a.energy = 0
		b.energy = 0
	state.phase = "result"
	state.phase_time = 180
	for f in state.fighters: f.max = 0
	event("ko" if state.time>0 else "time",state.winner)

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(saved: Dictionary) -> void:
	state = saved.duplicate(true)
	events.clear()

# Canonical typed encoding: sorted keys, little-endian integers, no rendering state.
func canonical(value: Variant, bytes: PackedByteArray) -> PackedByteArray:
	match typeof(value):
		TYPE_DICTIONARY:
			bytes.append(1)
			var keys: Array = value.keys()
			keys.sort()
			for key in keys:
				bytes = canonical(key,bytes)
				bytes = canonical(value[key],bytes)
			bytes.append(0)
		TYPE_ARRAY:
			bytes.append(2)
			for item in value: bytes=canonical(item,bytes)
			bytes.append(0)
		TYPE_STRING:
			bytes.append(3)
			bytes.append_array(value.to_utf8_buffer())
			bytes.append(0)
		_:
			bytes.append(4)
			var number: int = int(value)
			for k in 8: bytes.append((number >> (k*8)) & 255)
	return bytes

static func make_crc_table() -> PackedInt64Array:
	var table=PackedInt64Array()
	for i in 256:
		var c: int=i
		for k in 8: c=(c>>1)^(0xedb88320 if c&1 else 0)
		table.append(c)
	return table

func checksum() -> int:
	var bytes: PackedByteArray = canonical(state,PackedByteArray())
	var crc: int = 0xffffffff
	for byte in bytes:
		crc=(crc>>8)^CRC_TABLE[(crc^byte)&255]
	return (crc ^ 0xffffffff) & 0xffffffff
