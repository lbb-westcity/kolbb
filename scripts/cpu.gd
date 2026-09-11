extends RefCounted
const C = preload("res://scripts/commands.gd")
var level: int = 1
var history: Array = []
var queue: Array = []
var cooldown: int = 0
var seed_value: int = 73129
var decisions: Array = []

func random_int(n: int) -> int:
	seed_value ^= (seed_value << 13) & 0xffffffff
	seed_value ^= seed_value >> 17
	seed_value ^= (seed_value << 5) & 0xffffffff
	seed_value &= 0xffffffff
	return seed_value % n

func bits(direction: int, face: int) -> int:
	var result: int = 0
	if direction in [7,8,9]: result |= C.UP
	if direction in [1,2,3]: result |= C.DOWN
	if direction in [1,4,7]: result |= C.LEFT if face==1 else C.RIGHT
	if direction in [3,6,9]: result |= C.RIGHT if face==1 else C.LEFT
	return result

func sequence(dirs: Array, attack: int, face: int) -> void:
	queue.clear()
	for d in dirs:
		queue.append(bits(d,face))
		queue.append(bits(d,face))
	if queue.is_empty(): queue.append(0)
	queue[queue.size()-1] |= attack
	# Normal buttons wait two more samples for A+B/B+C; retain the intended stance.
	var stance: int = int(queue.back()) & 15
	queue.append(stance)
	queue.append(stance)
	queue.append(0)

func sample(battle, slot: int = 1) -> int:
	var s: Dictionary = battle.state
	# Observe only public state; never copy command histories or current buttons.
	var view: Dictionary = {"frame":s.frame,"fighters":[],"warning":false,"food":[]}
	for f in s.fighters:
		view.fighters.append({"x":f.x,"y":f.y,"face":f.face,"mode":f.mode,"move":f.move,"energy":f.energy,"max":f.max,"hp":f.hp,"char":f.char,"contact":f.contact,"confirmed_hit":f.confirmed_hit})
	for f in s.fighters:
		if f.slot!=slot and f.move=="P1-S3": view.warning=true
	for e in s.entities:
		if e.kind in ["burger","pizza"] and e.owner==slot and e.age>=e.travel:
			view.food.append({"x":e.x,"kind":e.kind})
	history.append(view)
	var delay: int = [24,16,10][level]
	if history.size()<=delay: return 0
	var seen: Dictionary = history.pop_front()
	if not queue.is_empty(): return queue.pop_front()
	cooldown -= 1
	if cooldown>0: return 0
	cooldown = [18,12,8][level]
	var me: Dictionary = seen.fighters[slot]
	var foe: Dictionary = seen.fighters[1-slot]
	var distance: int = absi(me.x-foe.x)/256
	var face: int = me.face
	var roll: int = random_int(100)
	decisions.append([s.frame,seen.frame])
	if decisions.size()>60: decisions.pop_front()
	if me.mode=="attack" and me.contact and level>0 and roll<65:
		if level==2 and me.confirmed_hit and me.energy>=200 and me.max==0 and (me.move.ends_with("5C") or me.move.ends_with("5D") or me.move.ends_with("2C")):
			queue=[C.MAX,0]
		elif me.max>120 and me.move.ends_with("S1"):
			sequence([6,2] if me.char==0 else [2,4],C.B if me.char==0 else C.A,face)
		else: sequence([2,6],C.C,face)
	elif not seen.food.is_empty() and me.hp<900 and distance>85 and roll<70:
		var foodx: int=seen.food[0].x
		var d: int=5 if absi(foodx-me.x)<12*256 else 6 if (foodx-me.x)*face>0 else 4
		for i in 12: queue.append(bits(d,face))
	elif (foe.mode=="attack" or seen.warning) and roll<[35,60,80][level]:
		var d: int = 1 if foe.move.contains("-2") else 4
		if seen.warning and level==2: d=9
		for i in [18,12,8][level]: queue.append(bits(d,face))
	elif distance<105 and me.energy>=100 and roll<22:
		sequence([2,6,2,6],C.C,face)
	elif me.energy>=200 and me.max==0 and roll<13 and level>0:
		queue=[C.MAX,0]
	elif me.char==0 and me.hp<750 and me.energy>=battle.moves["P1-S2"].cost and distance>130 and roll<35:
		sequence([2,4],C.A,face)
	elif me.char==0 and me.energy>=battle.moves["P1-S3"].cost and distance>90 and distance<230 and roll<55:
		sequence([6,2],C.B,face)
	elif me.char==2 and foe.y<292*256 and distance<100 and roll<75:
		sequence([6,2],C.B,face)
	elif me.char==2 and distance>=58 and distance<145 and roll<55:
		sequence([2,4],C.B if roll<20 else C.A,face)
	elif distance>150 and roll<60:
		sequence([2,6],C.A,face)
	elif distance<58 and me.char==1 and roll<25:
		sequence([6,2,4],C.D,face)
	elif distance<95:
		if me.char in [1,2] and roll<40: sequence([2,4],C.A,face)
		else:
			sequence([2 if random_int(100)<30 else 5], [C.A,C.B,C.C,C.D][random_int(4)],face)
	elif distance<190 and roll<20:
		for i in 8: queue.append(bits(9,face))
		queue.append(bits(6,face)|C.D)
	else:
		for i in [18,12,8][level]: queue.append(bits(6,face))
	return queue.pop_front() if not queue.is_empty() else 0
