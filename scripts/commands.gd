extends RefCounted
# Input state is part of each rollback snapshot. Directions are facing-relative.
const UP = 1
const DOWN = 2
const LEFT = 4
const RIGHT = 8
const A = 16
const B = 32
const C = 64
const D = 128
const ROLL = 256
const MAX = 512

static func fresh() -> Dictionary:
	return {"prev":0,"dir":5,"history":[],"motions":[],"clock":0,"pending":0,"wait":0,"buffer":"","ttl":0,"dash":0}

static func direction(bits: int, facing: int) -> int:
	var x: int = int(bool(bits & RIGHT)) - int(bool(bits & LEFT))
	var y: int = int(bool(bits & UP)) - int(bool(bits & DOWN))
	return 5 + x * facing + y * 3

static func motion(history: Array, sequence: Array, clock: int, window: int) -> bool:
	var k: int = sequence.size() - 1
	var last: int = clock
	var end: int = clock
	for j in range(history.size() - 1, -1, -1):
		var item: Array = history[j]
		var d: int = item[0]
		var t: int = item[1]
		if clock - t > window or last - t > 20:
			return false
		# Simultaneous direction presses do not establish a cardinal order.
		if d in [1,3,5,7,9]:
			continue
		if d == sequence[k]:
			if k == sequence.size()-1:
				end = t
			last = t
			k -= 1
			if k < 0:
				return end-t <= window
		elif k < sequence.size()-1:
			return false
	return false

static func sample(c: Dictionary, bits: int, facing: int, char_id: int, frozen: bool) -> void:
	bits &= 1023
	var edge: int = bits & ~int(c.prev)
	var d: int = direction(bits, facing)
	c.dash = 0
	if not frozen:
		c.clock += 1
		c.ttl = maxi(0, c.ttl-1)
		if c.ttl == 0:
			c.buffer = ""
	if d != c.dir:
		if d in [4,6]:
			for j in range(c.history.size()-1, -1, -1):
				var old: Array = c.history[j]
				if c.clock-old[1] > 20: break
				if old[0] == d:
					c.dash = d
					break
				if old[0] != 5: break
		c.history.append([d,c.clock])
		c.dir = d
	while not c.history.is_empty() and c.clock-c.history[0][1] > 30:
		c.history.pop_front()
	# Specials follow key-down order, even while a previous direction stays held.
	var pressed: int = edge & 15
	if pressed: c.motions.append([direction(pressed,facing),c.clock])
	while not c.motions.is_empty() and c.clock-c.motions[0][1] > 60:
		c.motions.pop_front()
	var attack: int = edge & 240
	var command: String = ""
	if attack:
		var punch: bool = bool(attack & (A|C))
		var kick: bool = bool(attack & (B|D))
		if punch and motion(c.motions,[2,6,2,6],c.clock,60): command = "U1"
		elif char_id == 1 and kick and motion(c.motions,[6,2,4],c.clock,40): command = "S3"
		elif char_id in [0,2,3] and kick and motion(c.motions,[6,2],c.clock,40): command = "S3"
		elif punch and motion(c.motions,[2,6],c.clock,40): command = "S1"
		elif punch and motion(c.motions,[2,4],c.clock,40): command = "S2"
		elif char_id == 2 and kick and motion(c.motions,[2,4],c.clock,40): command = "S4"
	if command != "":
		c.pending = 0
		c.history.clear()
		c.motions.clear()
	elif edge & MAX or ((edge | c.pending) & (B|C) == (B|C) and (edge & (B|C))):
		command = "MAX"
		c.pending = 0
	elif edge & ROLL or ((edge | c.pending) & (A|B) == (A|B) and (edge & (A|B))):
		command = "ROLL"
		c.pending = 0
	else:
		if attack:
			c.pending |= attack
			if c.wait == 0: c.wait = 3
		if c.pending and not frozen:
			c.wait -= 1
			if c.wait <= 0:
				for pair in [[D,"D"],[C,"C"],[B,"B"],[A,"A"]]:
					if c.pending & pair[0]:
						command = pair[1]
						break
				c.pending = 0
	if command != "":
		c.buffer = command
		c.ttl = 5
		c.wait = 0
	c.prev = bits

static func consume(c: Dictionary) -> void:
	c.buffer = ""
	c.ttl = 0
