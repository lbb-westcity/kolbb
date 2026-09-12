extends Node2D
const Battle = preload("res://scripts/battle.gd")
const INK = Color("0d1721")
const IVORY = Color("f0e7d5")
const CYAN = Color("45cbd1")
const ORANGE = Color("f29646")
const GOLD = Color("ffd166")
const RED = Color("e55661")
var battle
var textures: Dictionary = {}
var framesets: Dictionary = {}
var font: Font
var hud_font: FontVariation
var round_font: FontVariation
var hud_logo: Texture2D = preload("res://assets/ui/kolbb-logo.png")
var bg: Texture2D
var props: Texture2D
var animated_props: Texture2D
var fx: Array = []
var seen: Dictionary = {}
var time: float = 0
var trauma: float = 0
var settings: Dictionary = {}
var countdown: float = 0
var resume_fight_left: float = 0
var hud: bool = false
var practice_mode: bool=false
var demo: bool = true
var character_select: bool = false
var debug: bool = false
var status: String = ""
var delayed_hp: Array = [1000.0,1000.0]
var damage_wait: Array = [0.0,0.0]
var combo_hits: Array = [0,0]
var message: String = ""
var message_age: float = 0
var performance_us: int = 0
var online: bool = false
var world_offset: Vector2 = Vector2.ZERO
var confirmed: int = -1
var portrait: Array = []
var littleblack_fx: Dictionary = {}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	font=load("res://assets/ui/NotoSansCJKsc-Regular.otf")
	hud_font=FontVariation.new();hud_font.base_font=font;hud_font.variation_embolden=1.0
	round_font=FontVariation.new();round_font.base_font=load("res://assets/ui/Bungee-Regular.ttf")
	round_font.variation_transform=Transform2D(Vector2(1,0.22),Vector2(0,1),Vector2.ZERO)
	bg=load("res://assets/stage/office.png")

	for who in Battle.ART:
		portrait.append(load("res://assets/ui/"+who+"_portrait.png") if ResourceLoader.exists("res://assets/ui/"+who+"_portrait.png") else null)

	prepare_fighters([0,1],false)

func prepare_fighters(characters: Array, full: bool) -> void:
	var names: Array=[]
	for character in characters:
		var who: String=Battle.ART[character]
		if who not in names: names.append(who)
	for key in textures.keys():
		if not names.any(func(who): return key.begins_with(who+"_") and (full or key in [who+"_core",who+"_core_alt"])): textures.erase(key)
	for who in framesets.keys():
		if who not in names: framesets.erase(who)
	for who in names: load_fighter(who,full)
	if full:
		props=load("res://assets/props/props.png");animated_props=load("res://assets/props/animated.png")
		if 2 in characters:
			for name in ["ball","sonic","shoulder","trousers"]: littleblack_fx[name]=load("res://assets/props/littleblack_"+name+".png")
	if not full or 2 not in characters: littleblack_fx.clear()
	if not full: props=null;animated_props=null

func load_fighter(who: String, full: bool) -> void:
	framesets[who]=load("res://assets/fighters/%s_%s.tres" % [who,"frames" if full else "preview"])
	for group in (["core","normals","specials","air","locomotion","reaction","performance","normals2","specials2","wardrobe"] if full else ["core"]):
		for suffix in ["","_alt"]:
			var key: String=who+"_"+group+suffix
			var path: String="res://assets/fighters/"+key+".png"
			if not textures.has(key) and ResourceLoader.exists(path): textures[key]=load(path)

func reset_effects() -> void:
	queue_redraw()
	if battle: prepare_fighters(battle.state.fighters.map(func(f): return f.char),hud)
	seen.clear();fx.clear();trauma=0;delayed_hp=[1000.0,1000.0];damage_wait=[0.0,0.0];combo_hits=[0,0];message_age=0

func present(events: Array, audio) -> void:
	for e in events:
		if seen.has(e.id): continue
		if online and e.kind in ["ko","time","victory","round","fight"] and int(e.id.split("/")[1])-1>confirmed: continue
		seen[e.id]=battle.state.frame
		var sound: String=e.kind
		match e.kind:
			"hit": sound="heavy" if e.heavy else "light"
			"action":
				var id: String=e.move
				if id.begins_with("P3-"): sound={"P3-S1":"basketball","P3-S2":"shoulder","P3-S3":"sonic","P3-S4":"kick"}.get(id,"super")
				elif id.ends_with("S1"): sound="poop" if id.begins_with("P1") else "coin"
				elif id.ends_with("S2"): sound="burger" if id.begins_with("P1") else "talk"
				elif id.ends_with("S3"): sound="summon" if id.begins_with("P1") else "capture"
				else: sound="kick" if id.ends_with("B") or id.ends_with("D") else "punch"
			"projectile": sound=["poop","coin","basketball"][battle.state.fighters[e.slot].char]
		if e.kind=="victory": audio.play_music("victory")
		else: audio.sound(sound,1.0+(int(e.get("slot",0))*0.025))
		if e.kind in ["hit","block","pickup","clash","land","max","summon","slam","whip","break","stock","super","projectile","papers"]:
			var effect: Dictionary=e.duplicate()
			if e.slot>=0:
				var f: Dictionary=battle.state.fighters[e.slot]
				effect.char=f.char;effect.face=f.face
				effect.move=e.get("move",f.move)
				if e.kind=="projectile":
					effect.x+=f.face*Battle.PROJECTILE_OFFSET[f.char]
					effect.y=f.y/256.0-Battle.PROJECTILE_HEIGHT[f.char]
				elif e.kind in ["slam","whip"] and not battle.state.cinema.is_empty():
					effect.x=clampf(f.x/256.0+f.face*42,120,520)
					effect.y=222 if battle.state.cinema.kind=="grab" else 210
			effect.life=0.55 if e.kind in ["pickup","stock","summon","super","slam"] else 0.32 if e.kind=="papers" else 0.28
			if not settings.get("shake",true) and e.kind in ["hit","block","clash"]: effect.life+=2.0/60.0
			effect.total=effect.life
			fx.append(effect)
		if e.kind=="hit":
			combo_hits[e.target]=1 if e.get("combo_start",false) else combo_hits[e.target]+1
			damage_wait[e.target]=0.3
			if e.heavy: trauma=minf(1,trauma+0.38)
		if e.kind in ["slam","summon","super","ko"]: trauma=minf(1,trauma+0.7)
		if e.kind in ["super","capture"] or (e.kind=="denied" and e.slot==(Net.slot if online else 0)):
			message=e.get("text","");message_age=1.4
	while fx.size()>40: fx.pop_front()
	if seen.size()>500:
		for key in seen.keys():
			if battle.state.frame-seen[key]>240: seen.erase(key)

func animate(dt: float, paused: bool) -> void:
	queue_redraw()
	if paused: return
	resume_fight_left=maxf(0,resume_fight_left-dt)
	time+=dt
	trauma=maxf(0,trauma-dt*4)
	message_age=maxf(0,message_age-dt)
	for e in fx: e.life-=dt
	fx=fx.filter(func(e): return e.life>0)
	if battle:
		for i in 2:
			damage_wait[i]=maxf(0,damage_wait[i]-dt)
			var hp: float=battle.state.fighters[i].hp
			if hp>delayed_hp[i]: delayed_hp[i]=hp
			if damage_wait[i]==0: delayed_hp[i]=move_toward(delayed_hp[i],hp,dt*3500)

func label(text: String, p: Vector2, size: int = 12, color: Color = IVORY, width: float = -1) -> void:
	draw_string(font,p+Vector2(1,1),text,HORIZONTAL_ALIGNMENT_LEFT,width,size,Color(0.02,0.04,0.07,0.9))
	draw_string(font,p,text,HORIZONTAL_ALIGNMENT_LEFT,width,size,color)
func centered(text: String,y: float,size: int=24,color: Color=IVORY) -> void:
	var w: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	label(text,Vector2((640-w)/2,y),size,color)
func box(r: Rect2, fill: Color, edge: Color = Color.TRANSPARENT) -> void:
	draw_rect(r,fill)
	if edge.a>0: draw_rect(r,edge,false,1)
func marker(p: Vector2,slot: int,color: Color) -> void:
	if slot==0:
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),color)
	else: draw_circle(p,4,color)

func _draw() -> void:
	if not bg or not battle: return
	var offset: Vector2=Vector2.ZERO
	if settings.get("shake",true): offset=Vector2(roundf(sin(time*93)*trauma*trauma*5),roundf(sin(time*71)*trauma*trauma*3))
	world_offset=offset
	draw_set_transform(offset)
	draw_texture_rect(bg,Rect2(0,0,640,360),false)
	if character_select:
		for i in 2:
			var p=Vector2(224+i*192,232)
			draw_set_transform(p,0,Vector2(1,.16))
			draw_circle(Vector2.ZERO,30,Color(0,0,0,.4))
			draw_set_transform(Vector2.ZERO)
			draw_fighter(battle.state.fighters[i],p)
		return
	# Low-frequency office lights; never consume the battle RNG.
	var phase: int=int(time*60)
	if phase%180<60: box(Rect2(194,160,20,2),Color(0.35,0.8,0.9,0.17))
	if phase%360<60: box(Rect2(379,214+(phase%60)/15,7,2),Color(0.7,0.77,0.78,0.3))
	if battle.state.freeze>=10:
		box(Rect2(0,56,640,264),Color(0,0,0,0.15 if settings.get("flash",false) else 0.35))
	for f in battle.state.fighters:
		var height: float=(Battle.GROUND-f.y)/256.0
		draw_set_transform(offset+Vector2(f.x/256.0,293),0,Vector2(1,0.18))
		draw_circle(Vector2.ZERO,maxf(12,[22,25,22][f.char]-height*.06),Color(0,0,0,.28))
	draw_set_transform(offset)
	for f in battle.state.fighters:
		var action_age: int=maxi(0,f.age-1)
		if f.move=="P1-S3" and action_age<28:
			var x: float=f.target_x/256.0
			draw_set_transform(offset+Vector2(x,292),0,Vector2(1,.16))
			draw_arc(Vector2.ZERO,56,0,TAU,32,Color(CYAN,0.6),2)
			draw_arc(Vector2.ZERO,56*(1-action_age/28.0),0,TAU,24,Color(GOLD,.7),2)
			draw_set_transform(offset)
			box(Rect2(x-56,289,112,2),Color(CYAN,0.25))
			label("!",Vector2(x-3,281),12,GOLD)
			if action_age>=24: draw_animated_prop(1 if action_age>=26 else 0,Vector2(x,292-(28-action_age)*38),Vector2(256,256))
	for e in battle.state.entities: draw_entity(e)
	if battle.state.cinema.is_empty():
		for f in battle.state.fighters: draw_skill_fx(f)
		for f in battle.state.fighters: draw_fighter(f)
	else: draw_cinema()
	draw_set_transform(offset)
	for e in fx: draw_effect(e)
	draw_set_transform(Vector2.ZERO)
	if hud: draw_hud()
	if not demo: draw_round_text()
	if message_age>0 and hud:
		box(Rect2(170,65,300,24),Color(INK,0.92))
		centered(message,83,14,GOLD)
	if settings.get("show_fps",false): label("%d FPS" % Engine.get_frames_per_second(),Vector2(296,322),9,CYAN)
	if debug:
		for f in battle.state.fighters:
			for pair in [[battle.hurtbox(f),Color(0,1,0,.35)],[battle.attackbox(f),Color(1,0,0,.5)]]:
				var r: Rect2i=pair[0]
				draw_rect(Rect2(Vector2(r.position)/256.0,Vector2(r.size)/256.0),pair[1],false)
		label("%d FPS  sim %d µs  frame %d  entities %d" % [Engine.get_frames_per_second(),performance_us,battle.state.frame,battle.state.entities.size()],Vector2(10,315),10,CYAN)

func animation(f: Dictionary) -> Array:
	# Stored fighter age points at the next simulation tick; render the tick just resolved.
	f=f.duplicate();f.age=maxi(0,f.age-1)
	var group: String="core"
	var frame: int=(int(time*60)/8)%6
	var mode: String=f.mode
	if mode=="walk":
		group="locomotion" if f.input.dir==4 else "core";frame=(0 if f.input.dir==4 else 6)+(f.age/6)%6
	elif mode=="run": group="locomotion";frame=6+(f.age/4)%6
	elif mode=="backstep": group="locomotion";frame=12+mini(3,f.age/6)
	elif mode=="crouch": group="locomotion";frame=16+mini(2,f.age/2)
	elif mode=="jump_prepare": group="locomotion";frame=16 if f.age<2 else 19
	elif mode=="land": group="locomotion";frame=22+mini(1,f.age/2)
	elif mode=="air": group="locomotion";frame=20 if f.vy<0 else 21
	elif mode=="guard": group="reaction";frame=(2 if f.input.dir==1 else 0)+mini(1,f.age/3)
	elif mode=="hurt":
		if f.y<Battle.GROUND: group="reaction";frame=7+mini(1,f.age/5)
		else: frame=21
	elif mode=="down": group="reaction";frame=9+mini(2,f.age/4)
	elif mode=="getup": group="reaction";frame=12+mini(2,f.age/4)
	elif mode=="roll": group="reaction";frame=15+(f.age/2 if f.age<4 else 2+mini(2,(f.age-4)/4) if f.age<16 else 5+mini(1,(f.age-16)/7))
	elif mode=="max_start": group="performance";frame=12+mini(3,f.age/3)
	elif mode=="cinema": frame=18
	elif mode=="attack":
		var m: Dictionary=battle.moves[f.move]
		var phase_frame: int=mini(1,f.age*2/maxi(1,m.s)) if f.age<m.s else 3 if f.age<m.s+m.a else 4+mini(1,(f.age-m.s-m.a)*2/maxi(1,m.r))
		if m.kind=="normal":
			if f.move.contains("-j"):
				group="air";frame="ABCD".find(f.move.right(1))*6+phase_frame
			else:
				group="normals"
				var row: int=0
				if f.move.contains("-2"):
					row=3 if f.move.ends_with("B") or f.move.ends_with("D") else 2
				elif f.move.ends_with("B") or f.move.ends_with("D"): row=1
				frame=row*6+phase_frame
				if f.move.ends_with("2A"):
					group="normals2";frame=12+phase_frame
				elif f.move.ends_with("2B"): group="normals2";frame=18+phase_frame
				elif f.move.ends_with("5C"): group="normals2";frame=phase_frame
				elif f.move.ends_with("5D"): group="normals2";frame=6+phase_frame
		else:
			group="specials"
			var row: int=0
			if f.char==2:
				row={"projectile":0,"shoulder":1,"throw":2,"sonic":3}.get(m.kind,0)
			elif f.char==0:
				row=1 if m.kind=="summon" else 2 if m.kind in ["room","throw"] else 0
			else:
				row=1 if m.kind=="talk" else 2 if m.kind in ["grab","throw"] else 3 if m.kind=="papers" else 0
			frame=row*6+phase_frame
			if f.char==2:
				if m.kind=="trousers":
					group="wardrobe"
					frame=mini(4,f.age*5/14) if f.age<14 else 5 if f.age<18 else 6+mini(1,(f.age-18)/6) if f.age<30 else 9 if f.age<35 else 10+mini(1,(f.age-35)/3) if f.age<41 else 12+mini(5,(f.age-41)*6/20)
				elif m.kind=="dance":
					group="specials2"
					frame=mini(1,f.age/9) if f.age<18 else 2+mini(3,(f.age-18)/8) if f.age<46 else 6+mini(1,(f.age-46)/15)
			elif f.char==0:
				if m.kind=="burger": group="specials2";frame=phase_frame
				elif m.kind=="room": group="specials2";frame=6+mini(1,f.age/8)
				elif m.kind=="throw": group="specials2";frame=14+mini(1,f.age/2)
			else:
				if m.kind=="talk":
					group="specials2"
					frame=mini(1,f.age/5) if f.age<10 else 2 if f.age<13 else 3 if f.age<20 else 4+mini(1,(f.age-20)/2) if f.age<24 else 6+mini(1,(f.age-24)/11)
				elif m.kind=="grab": group="specials2";frame=8+mini(1,f.age/4)
				elif m.kind=="papers": group="specials2";frame=16+(mini(1,f.age/9) if f.age<18 else 2+mini(3,(f.age-18)/9) if f.age<54 else 6+mini(1,(f.age-54)/15))
	if f.reaction!="" and f.reaction_time>0:
		group="performance"
		frame=18+mini(2,(18-f.reaction_time)/6) if f.reaction=="poop" else 21+mini(2,(24-f.reaction_time)/8)
	elif f.pickup>6 and battle.is_free(f): group="performance";frame=16+int(f.pickup<9)
	if battle.state.phase=="intro": group="performance";frame=mini(5,(120-battle.state.phase_time)/20)
	if battle.state.phase in ["result","done"] and f.slot==battle.state.winner: group="performance";frame=6+mini(5,(180-battle.state.phase_time)/10)
	return [group,clampi(frame,0,23)]

func draw_fighter(f: Dictionary,override_pos: Vector2=Vector2.INF,override_frame: int=-1,shadow: bool=false,override_anim: Array=[],render_scale: float=1.0,tint: Color=Color.WHITE) -> void:
	var anim: Array=animation(f)
	if override_frame>=0: anim=["core",override_frame]
	if not override_anim.is_empty(): anim=override_anim
	var who: String=Battle.ART[f.char]
	if not textures.has(who+"_core"): load_fighter(who,hud)
	var key: String=who+"_"+anim[0]
	if not textures.has(key): key=who+"_core";anim=["core",19]
	var tex: Texture2D=textures[key]
	var p: Vector2=Vector2(roundf(f.x/256.0),roundf(f.y/256.0)) if override_pos==Vector2.INF else override_pos
	var frame: int=anim[1]
	var squash: Vector2=Vector2.ONE
	if f.mode=="max_start": squash=Vector2(1.05,.95)
	if f.mode=="hurt" and f.age<=4: squash=Vector2(.93,1.04)
	squash*=render_scale
	var color: Color=(Color(0.06,0.09,0.14) if shadow else Color.WHITE) if tint==Color.WHITE else tint
	if battle.state.fighters[0].char==battle.state.fighters[1].char and f.slot==1 and not shadow:
		var alt_key: String=key+"_alt"
		if textures.has(alt_key): tex=textures[alt_key]
	var rot: float=0
	draw_set_transform(p+world_offset,rot,Vector2(f.face,1)*squash)
	if not shadow and f.max>0 and (settings.get("flash",false) or int(time*10)%2==0):
		draw_arc(Vector2(0,-2),32,PI,TAU,16,GOLD,1)
		draw_line(Vector2(-25,-105),Vector2(-25,-85),GOLD,1)
	var sequence: String=anim[0]+("_alt" if battle.state.fighters[0].char==battle.state.fighters[1].char and f.slot==1 and not shadow else "")
	var anchor: Vector2=framesets[who].get_meta("foot_anchor",Vector2(128,176)) if framesets.has(who) else Vector2(128,176)
	if framesets.has(who) and framesets[who].has_animation(sequence):
		draw_texture(framesets[who].get_frame_texture(sequence,frame),-anchor,color)
	else: draw_texture_rect_region(tex,Rect2(-128,-176,256,192),Rect2((frame%6)*256,(frame/6)*192,256,192),color)
	# The chest print faces the reader even when the body faces left.
	if f.char==1 and f.face<0 and not shadow and framesets.has(who):
		var logos: Array=framesets[who].get_meta("logo_"+anim[0],[])
		if logos.size()>frame:
			var r: Rect2=logos[frame]
			if r.has_area():
				draw_set_transform(p+world_offset,rot,squash)
				var frame_tex: AtlasTexture=framesets[who].get_frame_texture(sequence,frame)
				draw_texture_rect_region(tex,Rect2(anchor.x-r.end.x,r.position.y-anchor.y,r.size.x,r.size.y),Rect2(r.position+frame_tex.region.position,r.size))
	draw_set_transform(world_offset)
	if shadow: return
	if not shadow:
		if not character_select: marker(p+Vector2(0,8),f.slot,CYAN if f.slot==0 else ORANGE)
		if f.stain>0: box(Rect2(p+Vector2(f.face*4-5,-132),Vector2(10,6)),Color("79442b"))
	if f.char==2 and f.mode=="attack":
		var age: int=maxi(0,f.age-1)
		if f.move=="P3-S3" and age>=10 and age<16:
			draw_littleblack_fx("sonic",age-10,p+Vector2(f.face*44,-129),Vector2(84,162),f.face)
		elif f.move=="P3-S2" and age>=12 and age<20:
			draw_littleblack_fx("shoulder",mini(5,age-12),p+Vector2(f.face*45,-85),Vector2(52,64),f.face)
		elif f.move=="P3-U1" and age>=42 and age<48:
			draw_littleblack_fx("shoulder",age-42,p+Vector2(f.face*64,-85),Vector2(88,76),f.face)
	if f.mode=="attack" and f.move=="P2-S2" and f.age>=9 and f.age<=20:
		var x: float=p.x+f.face*60
		box(Rect2(x-28,p.y-143,56,24),IVORY,INK)
		label("绩效？",Vector2(x-23,p.y-125),14,INK)

func draw_prop(index: int,p: Vector2,size: Vector2,tint: Color=Color.WHITE) -> void:
	if props:
		draw_texture_rect_region(props,Rect2(p.x-size.x/2,p.y-size.y*244/256,size.x,size.y),Rect2((index%4)*256,(index/4)*256,256,256),tint)

func draw_animated_prop(index: int,p: Vector2,size: Vector2,tint: Color=Color.WHITE) -> void:
	if animated_props: draw_texture_rect_region(animated_props,Rect2(p.x-size.x/2,p.y-size.y*244/256,size.x,size.y),Rect2((index%6)*256,(index/6)*256,256,256),tint)

func draw_littleblack_fx(id: String, frame: int, p: Vector2, size: Vector2, face: int=1,tint: Color=Color.WHITE) -> void:
	if not littleblack_fx.has(id): return
	var tex: Texture2D=littleblack_fx[id]
	var cell: Vector2=Vector2(tex.get_width()/3,tex.get_height()/2)
	draw_set_transform(p+world_offset,0,Vector2(face,1))
	draw_texture_rect_region(tex,Rect2(-size/2,size),Rect2(Vector2(frame%3,frame/3)*cell,cell),tint)
	draw_set_transform(world_offset)

func draw_entity(e: Dictionary) -> void:
	var p: Vector2=Vector2(e.x/256.0,e.y/256.0)
	if e.kind=="projectile":
		var color: Color=[Color("b98c54"),GOLD,ORANGE][e.char]
		for i in range(3,0,-1):
			var lag: int=mini(e.age,i*2)
			if lag==0: continue
			var q: Vector2=p-Vector2(e.vx/256.0*lag,0)
			var tint: Color=Color(color,.24-i*.05)
			if e.char==2: draw_littleblack_fx("trousers" if e.move=="P3-S4" else "ball",(maxi(0,e.age-lag)/3)%6,q,Vector2(34,34) if e.move=="P3-S4" else Vector2(24,24),e.face,tint)
			else: draw_animated_prop(18+(maxi(0,e.age-lag)/4)%4 if e.char==0 else 22+(maxi(0,e.age-lag)/4)%2,q+Vector2(0,10),Vector2(22,22),tint)
		for i in 5:
			var tail: float=fmod(e.age*2+i*11,42)
			var q: Vector2=p+Vector2(-e.face*(10+tail),(i%3-1)*(4+tail*.12))
			box(Rect2(q,Vector2(4 if e.char==1 else 2,2)),Color(color,(1-tail/42)*.65))
	if e.kind=="projectile" and e.char==2:
		draw_littleblack_fx("trousers" if e.move=="P3-S4" else "ball",(e.age/3)%6,p,Vector2(34,34) if e.move=="P3-S4" else Vector2(24,24),e.face)
	elif e.kind=="projectile":
		var color: Color=Color("9d7040") if e.char==0 else GOLD
		for i in 3: draw_line(p-Vector2(e.face*(8+i*5),0),p-Vector2(e.face*(13+i*5),0),Color(color,0.5-i*.1),2)
		if animated_props: draw_animated_prop(18+(e.age/4)%4 if e.char==0 else 22+(e.age/4)%2,p+Vector2(0,10),Vector2(22,22))
		else: draw_prop(2 if e.char==0 else 3,p+Vector2(0,10),Vector2(25,25))
	elif e.kind in ["burger","pizza"]:
		if e.life<=30 and not settings.get("flash",false) and (e.life/4)%2==0: return
		draw_prop(0 if e.kind=="burger" else 1,p,Vector2(28,24),Color(1,1,1,.5 if e.life<=30 and settings.get("flash",false) else 1))
		var ready: bool=e.age>=e.travel+(30 if e.kind=="burger" else 12)
		var color: Color=CYAN if e.owner==0 else ORANGE
		if ready:
			for i in 3:
				var rise: float=fmod(e.age*.35+i*10,30)
				var q: Vector2=p+Vector2((i-1)*11,-8-rise)
				draw_line(q-Vector2(2,0),q+Vector2(2,0),Color(GOLD,(1-rise/30)*.6),1)
				draw_line(q-Vector2(0,2),q+Vector2(0,2),Color(GOLD,(1-rise/30)*.6),1)
		if ready: marker(p+Vector2(0,-29),e.owner,color)
		elif e.owner==0: draw_polyline(PackedVector2Array([p+Vector2(0,-33),p+Vector2(4,-29),p+Vector2(0,-25),p+Vector2(-4,-29),p+Vector2(0,-33)]),color,1)
		else: draw_arc(p+Vector2(0,-29),4,0,TAU,12,color,1)
		label(str(e.owner+1),p+Vector2(7,-25),8,color)
		if ready:
			var friendly: bool=e.owner==(Net.slot if online else 0)
			if friendly or e.kind=="burger": label("+" if friendly else "−",p+Vector2(-15,-25),10,Color("79c878") if friendly else RED)
	elif e.kind=="summon":
		if animated_props: draw_animated_prop(2+e.age if e.age<4 else 7,p-Vector2(0,maxi(0,e.age-4)*12),Vector2(256,256))
		else: draw_prop(4 if e.age<8 else 5,p,Vector2(214,214))
	elif e.kind=="papers":
		for i in 18:
			var x: float=e.x/256.0+e.face*(40+(i*31+e.age*15)%530)
			var y: float=275-((i*19)%100)
			if x>16 and x<624:
				draw_line(Vector2(x-e.face*24,y-10),Vector2(x-e.face*9,y-10),Color(IVORY,.35),1)
				draw_prop(10,Vector2(x,y),Vector2(18,23))

func skill_color(character: int) -> Color:
	return [CYAN,GOLD,ORANGE][clampi(character,0,2)]

func draw_burst(p: Vector2,color: Color,progress: float,count: int=10,radius: float=40,gravity: float=18) -> void:
	# Analytic particles: no nodes, saved simulation state, or battle RNG consumption.
	var fade: float=(1-progress)*(0.55 if settings.get("flash",false) else 1.0)
	var spread: float=1-pow(1-progress,3)
	for i in count:
		var v: Vector2=Vector2.from_angle(i*2.39996+.3)
		var q: Vector2=p+v*(6+radius*spread*(.55+(i%4)*.15))+Vector2(0,gravity*progress*progress)
		draw_line(q-v*(3+5*(1-progress)),q,Color(color,fade),2)
		if i%3==0: box(Rect2(q+Vector2(2,-2),Vector2(2,2)),Color(IVORY,fade*.7))

func draw_skill_fx(f: Dictionary) -> void:
	if f.mode!="attack" or not f.move.begins_with("P"): return
	var age: int=maxi(0,f.age-1)
	var m: Dictionary=battle.moves[f.move]
	var p: Vector2=Vector2(f.x/256.0,f.y/256.0)
	var color: Color=skill_color(f.char)
	var opacity: float=.5 if settings.get("flash",false) else .85
	# Short pose echoes follow the rush/finisher windows; interruptions remove them immediately.
	if (m.kind=="shoulder" and age>=12 and age<24) or (m.kind=="dance" and age>=42 and age<50) or (m.kind=="room" and age>=8 and age<18):
		for i in range(3,0,-1):
			draw_fighter(f,p-Vector2(f.face*i*10,0),-1,true,[],1,Color(color,opacity*(.19-i*.04)))
	draw_set_transform(p+world_offset,0,Vector2(f.face,1))
	if age<m.s:
		var charge: float=age/float(m.s)
		var hand: Vector2=Vector2(28,-94)
		for i in 5:
			var v: Vector2=Vector2.from_angle(i*TAU/5+charge*1.4)
			var q: Vector2=hand+v*(30-22*charge)
			draw_line(q,q-v*(3+charge*4),Color(color,opacity*charge),1)
		draw_arc(hand,5+charge*7,-1.8+charge,1.2+charge,12,Color(color,charge*opacity),1)
	var strike: int=m.s
	if m.kind=="talk" and age>=20: strike=20
	if m.kind=="trousers" and age>=30: strike=30
	if m.kind=="dance" and age>=18: strike=18+mini(3,(age-18)/8)*8
	var t: float=(age-strike)/10.0
	if t>=0 and t<1:
		var fade: float=(1-t)*opacity
		match m.kind:
			"shoulder","dance","trousers","talk":
				var reach: float=100 if m.kind=="dance" and strike==42 else 84 if m.kind=="trousers" else 72
				if m.kind!="trousers" or strike==30:
					for i in 3:
						draw_arc(Vector2(16,-78),reach-15+i*5,-1.0+t*.7,1.0+t*.7,18,Color(IVORY if i==2 else color,fade*(.7 if i==2 else .4)),2 if i==2 else 3)
					for i in 5:
						var y: float=-112+i*20
						draw_line(Vector2(-42-t*22,y),Vector2(12+t*24,y-4),Color(color,fade*.6),1)
				else: draw_burst(Vector2(32,-88),Color("a6b9c8"),t,8,25,12)
				if m.kind=="dance":
					for i in 3:
						var q: Vector2=Vector2(-24+i*48,-145-t*20)
						draw_circle(q,2,Color(color,fade))
						draw_line(q+Vector2(2,0),q+Vector2(2,-10),Color(color,fade),1)
			"sonic":
				for i in 4:
					var q: Vector2=Vector2(36+i*8,-82-i*25-t*26)
					draw_arc(q,16+i*6+t*12,PI*1.05,TAU-.15,18,Color(CYAN,fade*(1-i*.15)),2)
			"burger":
				draw_burst(Vector2(30,-96),GOLD,t,8,24,30)
			"grab","room":
				draw_arc(Vector2(40,-88),18+t*24,-1.8,1.8,16,Color(color,fade),2)
	if m.kind=="dance" and age>=18 and age<54:
		var beat: float=fmod(age-18,8)/8.0
		draw_set_transform(p+world_offset,0,Vector2(1,.2))
		draw_arc(Vector2.ZERO,30+beat*50,0,TAU,32,Color(color,(1-beat)*opacity*.65),2)
	draw_set_transform(world_offset)

func draw_cinema() -> void:
	var c: Dictionary=battle.state.cinema.duplicate()
	c.age=maxi(0,c.age-1)
	var a: Dictionary=battle.state.fighters[c.owner]
	var b: Dictionary=battle.state.fighters[c.target]
	var x: float=clampf(a.x/256.0+a.face*42,120,520)
	if c.kind=="room":
		box(Rect2(0,56,640,264),Color(0,0,0,.3))
		if animated_props: draw_animated_prop(8 if c.age<6 else 9 if c.age<12 else 10 if c.age<60 else 11,Vector2(x,292),Vector2(215,215))
		else: draw_prop(7 if c.age<12 or c.age>60 else 6,Vector2(x,292),Vector2(195,205))
		if c.age>=12 and c.age<=60:
			draw_fighter(a,Vector2(x-28,258),-1,true,["specials2",9+(c.age/4)%3],.42)
			draw_fighter(b,Vector2(x+28,258),21,true,[],.42)
		elif c.age>60:
			draw_fighter(a,Vector2(x-28,292),-1,false,["specials2",12])
			draw_fighter(b,Vector2(x+30+(c.age-60)*4,292),22)
		label("小黑屋",Vector2(x-23,132),14,GOLD)
	elif c.kind=="grab":
		var pose: int=8 if c.age<4 else 9 if c.age<8 else 10 if c.age<24 else 11 if c.age<36 else 12 if c.age<38 else 13 if c.age<44 else 14 if c.age<50 else 15
		draw_fighter(a,Vector2(x-a.face*43,292),-1,false,["specials2",pose])
		draw_fighter(b,Vector2(x+a.face*30,292),21)
		if animated_props: draw_animated_prop(12 if c.age<6 else 13 if c.age<36 else 14 if c.age<48 else 15,Vector2(x,292),Vector2(170,125))
		else: draw_prop(8,Vector2(x,292),Vector2(150,106))
		if c.age>=36: label("加班",Vector2(x-18,222),18,RED)
	else:
		draw_fighter(a,Vector2(x-a.face*25,292),-1,false,["specials2",14+mini(5,c.age/5)] if a.char==0 else ["specials",12+mini(5,c.age/5)])
		draw_fighter(b,Vector2(x+a.face*40,292-mini(c.age,15)*2),21 if c.age<18 else 22)

func draw_effect(e: Dictionary) -> void:
	var p: Vector2=Vector2(e.x,e.y)
	var k: float=e.life/e.total
	var color: Color=skill_color(e.get("char",0))
	if e.kind=="slam" and e.get("move","")=="P2-S3": color=RED
	var opacity: float=.55 if settings.get("flash",false) else 1.0
	if e.kind=="block":
		var angle: float=0 if e.get("face",1)==1 else PI
		for i in 2: draw_arc(p,18+(1-k)*12+i*5,angle-PI*.6,angle+PI*.6,16,Color(CYAN,k*opacity*(1-i*.5)),2-i)
		draw_burst(p,CYAN,1-k,5,24,6)
	elif e.kind in ["hit","slam","whip","clash"]:
		var heavy: bool=e.get("heavy",false) or e.kind in ["slam","whip","clash"]
		var radius: float=maxf(1,(28 if heavy else 17)*k)
		var points=PackedVector2Array()
		for i in 16:
			var r: float=radius if i%2==0 else radius*.32
			points.append(p+Vector2(cos(i*TAU/16),sin(i*TAU/16))*r)
		draw_colored_polygon(points,Color(color,k*opacity*.7))
		for i in points.size(): points[i]=p+(points[i]-p)*.62
		draw_colored_polygon(points,Color(IVORY,k*opacity))
		draw_arc(p,9+(1-k)*(42 if heavy else 26),0,TAU,24,Color(color,k*opacity*.5),1)
		draw_burst(p,color,1-k,14 if heavy else 8,52 if heavy else 32)
		if e.kind=="whip":
			var face: int=e.get("face",1)
			draw_polyline(PackedVector2Array([p+Vector2(-face*43,16),p+Vector2(-face*28,-13),p+Vector2(-face*13,-18),p]),Color(GOLD,k*opacity),2)
		elif e.kind=="slam" and e.get("move","")=="P2-S3":
			var stamp: float=22+(1-k)*18
			draw_rect(Rect2(p-Vector2(stamp,stamp*.65),Vector2(stamp*2,stamp*1.3)),Color(RED,k*opacity),false,2)
			for i in 6:
				var q: Vector2=p+Vector2((i-2.5)*(10+(1-k)*12),-sin((1-k)*PI)*28+(i%2)*18)
				box(Rect2(q,Vector2(5,7)),Color(IVORY,k*.65))
		if e.get("move","")=="P1-S1":
			for i in 6:
				var q: Vector2=p+Vector2.from_angle(i*2.4)*(8+(1-k)*23)+Vector2(0,(1-k)*14)
				draw_circle(q,1+k*3,Color("936338",k))
		elif e.get("move","")=="P2-S1":
			for i in 4:
				var q: Vector2=p+Vector2((i-1.5)*(12+(1-k)*12),-12-(1-k)*28)
				draw_arc(q,3,0,TAU,8,Color(GOLD,k*opacity),1)
		elif e.get("move","")=="P3-S3":
			for i in 3: draw_arc(p+Vector2(0,-(1-k)*i*14),16+i*9+(1-k)*12,PI,TAU,16,Color(CYAN,k*opacity*.6),1)
		if e.get("damage",0)>0: label(str(e.damage),p+Vector2(14,-20-(1-k)*15),12,Color(IVORY,k))
	elif e.kind=="super":
		var radius: float=18+pow(1-k,.6)*80
		draw_arc(p,radius,-PI*.9,PI*.8,36,Color(color,k*opacity*.6),2)
		draw_arc(p,radius*.8,PI*.15,PI*1.5,28,Color(IVORY,k*opacity*.4),1)
		draw_burst(p,color,1-k,16,95,0)
	elif e.kind=="projectile":
		draw_arc(p,8+(1-k)*20,0,TAU,20,Color(color,k*opacity*.7),2)
		draw_burst(p,color,1-k,7,26,4)
	elif e.kind=="summon" or e.kind=="land":
		var large: bool=e.kind=="summon"
		draw_set_transform(world_offset+Vector2(e.x,292),0,Vector2(1,.22))
		for i in 2: draw_arc(Vector2.ZERO,(18+(1-k)*(95 if large else 26))*(1-i*.25),0,TAU,32,Color(GOLD if large else IVORY,k*opacity*.6),2)
		draw_set_transform(world_offset)
		for i in (12 if large else 5):
			var side: int=1 if i%2==0 else -1
			var q: Vector2=Vector2(e.x+side*(12+(1-k)*(22+i*6)),289-sin((1-k)*PI)*(5+i%4*5))
			box(Rect2(q,Vector2(4+k*7,2+k*3)),Color(IVORY,k*.45))
		if large: draw_burst(Vector2(e.x,278),GOLD,1-k,14,65,12)
	elif e.kind=="papers":
		# Detached scraps outlive each four-tick wave, without obscuring the fighters.
		for i in 9:
			var q: Vector2=Vector2(e.x+e.face*(40+i*49+(1-k)*70),176+(i*23)%95+(1-k)*22)
			if q.x<20 or q.x>620: continue
			draw_set_transform(q+world_offset,e.face*((1-k)*2+i)*.35)
			box(Rect2(-4,-5,8,10),Color(IVORY,k*.5))
			draw_line(Vector2(-2,-2),Vector2(2,-2),Color(INK,k*.5),1)
		draw_set_transform(world_offset)
	elif e.kind=="pickup":
		var heal: Color=Color("79c878") if e.damage<0 else RED
		draw_burst(p,heal,1-k,8,30,-25)
		label(e.text,p+Vector2(-15,-(1-k)*15),16,heal)
	elif e.kind in ["max","stock"]:
		draw_arc(Vector2(e.x,289),24+(1-k)*30,PI,TAU,20,Color(GOLD,k),2)
		if e.kind=="max": label("MAX",Vector2(e.x-20,210-(1-k)*20),18,GOLD)
	else:
		for i in 5: box(Rect2(e.x-22+i*10,290-(1-k)*10,5*k,3*k),Color(IVORY,k*.4))

func hud_panel(points: PackedVector2Array, fill: Color, edge: Color, thickness: float=1) -> void:
	draw_colored_polygon(points,fill)
	points.append(points[0])
	draw_polyline(points,edge,thickness)

func hud_text(text: String, p: Vector2, size: int, color: Color=IVORY, align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT, width: float=-1) -> void:
	draw_string_outline(hud_font,p,text,align,width,size,2,Color(Color("071321"),color.a))
	draw_string(hud_font,p,text,align,width,size,color)

func hud_player_label(slot: int) -> String:
	if online: return "%dP · 你" % (slot+1) if slot==Net.slot else "%dP" % (slot+1)
	return status.replace(" / "," · ") if slot==1 and status!="" else "%dP" % (slot+1)

func draw_hud() -> void:
	var s: Dictionary=battle.state
	for i in 2:
		var f: Dictionary=s.fighters[i]
		var color: Color=Color("32e1ef") if i==0 else Color("ff802d")
		var danger: bool=f.hp>0 and f.hp<=250
		# Mirror the frame geometry; keep portraits and text facing the reader.
		draw_set_transform(Vector2.ZERO if i==0 else Vector2(640,0),0,Vector2(1 if i==0 else -1,1))
		hud_panel(PackedVector2Array([Vector2(23,16),Vector2(64,16),Vector2(68,20),Vector2(68,51),Vector2(27,51),Vector2(23,47)]),Color("071321"),color,1.5)
		hud_panel(PackedVector2Array([Vector2(73,32),Vector2(268,32),Vector2(277,47),Vector2(74,47),Vector2(71,43),Vector2(71,35)]),Color("071321"),RED if danger else color,2 if danger else 1.5)
		for pair in [[delayed_hp[i],RED],[f.hp,Color("fff3d2")]]:
			var end: float=75+196*clampf(float(pair[0])/1000,0,1)
			if end>75:
				draw_colored_polygon(PackedVector2Array([Vector2(75,35),Vector2(minf(end,265),35),Vector2(end,44),Vector2(75,44)]),pair[1])
		for tick in [140,205]: draw_line(Vector2(tick,43),Vector2(tick,45),Color("071321"),1)
		for j in 2:
			var p: Vector2=Vector2(36+j*17,61)
			hud_panel(PackedVector2Array([p+Vector2(0,-5),p+Vector2(5,0),p+Vector2(0,5),p+Vector2(-5,0)]),color if s.wins[i]>j else Color("071321"),IVORY,1.5)
		draw_set_transform(Vector2.ZERO)
		var headx: int=25 if i==0 else 574
		var tex: Texture2D=portrait[f.char]
		if tex: draw_texture_rect(tex,Rect2(headx,18,41,31),false)
		hud_text(Battle.NAMES[f.char],Vector2(75 if i==0 else 476,28),12,IVORY,HORIZONTAL_ALIGNMENT_LEFT if i==0 else HORIZONTAL_ALIGNMENT_RIGHT,90)
		hud_text(hud_player_label(i),Vector2(172 if i==0 else 390,28),11,GOLD if online and i==Net.slot else color,HORIZONTAL_ALIGNMENT_LEFT if i==0 else HORIZONTAL_ALIGNMENT_RIGHT,80)
		if danger: hud_text("危险",Vector2(75 if i==0 else 495,61),11,RED,HORIZONTAL_ALIGNMENT_LEFT if i==0 else HORIZONTAL_ALIGNMENT_RIGHT,70)
		var ex: int=52 if i==0 else 472
		hud_text("POW",Vector2(ex-29,334),10,RED if f.flash_meter>0 else color)
		var stock_glow: float=0
		for effect in fx:
			if effect.kind=="stock" and effect.slot==i: stock_glow=maxf(stock_glow,effect.life/effect.total)
		if settings.get("flash",false): stock_glow*=.45
		for j in 3:
			var amount: float=clampf(f.energy-j*100,0,100)/100.0
			var x: int=ex+j*45
			hud_panel(PackedVector2Array([Vector2(x,333),Vector2(x+41,333),Vector2(x+42,334),Vector2(x+42,343),Vector2(x+1,343),Vector2(x,342)]),Color("071321"),RED if f.flash_meter>0 else color.lerp(GOLD,stock_glow) if amount==1 else color,2 if f.flash_meter>0 or (amount==1 and stock_glow>0) else 1)
			if amount>0: box(Rect2(x+2,335,38*amount,6),RED if f.flash_meter>0 else GOLD if amount==1 else color)
		if f.max>0:
			hud_text("MAX",Vector2(ex,327),11,GOLD)
			box(Rect2(ex+31,319,100,6),Color("172735"))
			box(Rect2(ex+31,319,100.0*f.max/f.max_total,6),GOLD)
		var target: Dictionary=s.fighters[1-i]
		if target.combo_age>0 and combo_hits[1-i]>=2:
			var fade: float=minf(1,target.combo_age/12.0)
			var pop: float=0 if settings.get("flash",false) else roundf(sin(clampf((60-target.combo_age)/10.0,0,1)*PI)*3)
			var hits: String="%d HITS" % combo_hits[1-i]
			var damage: String="%d DAMAGE" % target.combo_damage
			var width: float=ceilf(maxf(92,maxf(hud_font.get_string_size(hits,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x,hud_font.get_string_size(damage,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x)))
			var p: Vector2=Vector2(25 if i==0 else 615-width,104-pop)
			var align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT if i==0 else HORIZONTAL_ALIGNMENT_RIGHT
			box(Rect2(p-Vector2(5,20),Vector2(width+10,39)),Color(INK,.86*fade))
			hud_text(hits,p,18,Color(color,fade),align,width)
			hud_text(damage,p+Vector2(0,14),10,Color(IVORY,fade),align,width)
	hud_panel(PackedVector2Array([Vector2(289,18),Vector2(351,18),Vector2(361,36),Vector2(351,62),Vector2(289,62),Vector2(279,36)]),Color("071321"),Color("436579"),2)
	draw_polyline(PackedVector2Array([Vector2(286,23),Vector2(279,36),Vector2(289,56)]),Color("32e1ef"),2)
	draw_polyline(PackedVector2Array([Vector2(354,23),Vector2(361,36),Vector2(351,56)]),Color("ff802d"),2)
	if practice_mode: hud_text("∞",Vector2(280,47),32,IVORY,HORIZONTAL_ALIGNMENT_CENTER,80)
	else: draw_string(round_font,Vector2(280,47),"%02d" % ceili(s.time/60.0),HORIZONTAL_ALIGNMENT_CENTER,80,32,RED if s.time<=1200 else Color("fff3d2"))
	hud_text("练习" if practice_mode else "ROUND %d" % s.round,Vector2(280,59),10,IVORY,HORIZONTAL_ALIGNMENT_CENTER,80)
	if online and status!="":
		if status=="等待网络":
			box(Rect2(365,51,96,22),Color(INK,.95),GOLD)
			hud_text("等待网络…",Vector2(372,67),11,GOLD)
		else: hud_text(status,Vector2(367,62),10,CYAN)
	draw_texture_rect(hud_logo,Rect2(296,329,48,19),false)

func arcade_word(text: String, p: Vector2, size: int, color: Color) -> void:
	draw_string_outline(round_font,p+Vector2(0,4),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color("071321"))
	draw_string(round_font,p+Vector2(0,4),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("ff802d"))
	draw_string_outline(round_font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,3,Color("071321"))
	draw_string(round_font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func draw_countdown() -> void:
	var center: Vector2=Vector2(320,205)
	draw_circle(center,58,Color("071321",.84))
	for i in 4:
		var angle: float=PI/4+i*PI/2
		draw_arc(center,62,angle-.48,angle+.48,12,Color("071321"),8)
		draw_arc(center,62,angle-.30,angle+.30,10,Color("ff802d"),4)
	var text: String=str(ceili(countdown))
	var width: float=round_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,104).x
	arcade_word(text,Vector2((640-width)/2-7,240),104,Color("fff3d2"))
	hud_text("准备开打",Vector2(265,272),16,IVORY,HORIZONTAL_ALIGNMENT_CENTER,110)

func draw_fight_callout() -> void:
	draw_set_transform(Vector2(320,208),-.08)
	var width: float=round_font.get_string_size("FIGHT!",HORIZONTAL_ALIGNMENT_LEFT,-1,68).x
	var p: Vector2=Vector2(-width/2-6,17)
	draw_colored_polygon(PackedVector2Array([Vector2(-52,25),Vector2(55,25),Vector2(48,47),Vector2(-59,47)]),Color("071321"))
	for side in [-1,1]:
		draw_line(Vector2(side*58,-53),Vector2(side*(width/2+4),-53),Color("ff802d"),3)
		draw_line(Vector2(side*57,35),Vector2(side*(width/2-8),35),Color("ff802d"),3)
	draw_string_outline(round_font,p+Vector2(0,4),"FIGHT!",HORIZONTAL_ALIGNMENT_LEFT,-1,68,6,Color("071321"))
	draw_string_outline(round_font,p+Vector2(0,3),"FIGHT!",HORIZONTAL_ALIGNMENT_LEFT,-1,68,2,IVORY)
	draw_string_outline(round_font,p,"FIGHT!",HORIZONTAL_ALIGNMENT_LEFT,-1,68,3,Color("071321"))
	draw_string(round_font,p,"FIGHT!",HORIZONTAL_ALIGNMENT_LEFT,-1,68,Color("ff802d"))
	hud_text("开打！",Vector2(-45,41),16,IVORY,HORIZONTAL_ALIGNMENT_CENTER,90)
	draw_set_transform(Vector2.ZERO)

func draw_round_text() -> void:
	if countdown>0:
		draw_countdown()
		return
	if resume_fight_left>0 or battle.state.phase=="ready":
		draw_fight_callout()
		return
	var s: Dictionary=battle.state
	var text: String=""
	var subtitle: String=""
	if s.phase=="intro":
		centered("下班之前，分个胜负。",188,20)
		return
	elif s.phase=="round":
		text="ROUND %d" % s.round
		subtitle="第 %s 回 合" % (["一","二","三","四","五"][s.round-1] if s.round>=1 and s.round<=5 else str(s.round))
	elif s.phase=="result":
		if online and s.frame-1>confirmed:
			centered("确认对局结果…",188,20)
			return
		text="DRAW" if s.winner<0 else "K.O." if s.time>0 else "TIME OVER"
		subtitle="平 局" if s.winner<0 else "回 合 结 束"
	if text=="": return
	var parts: Array=[["ROUND",48,Color("fff3d2")],[str(s.round),66,Color("ff802d")]] if s.phase=="round" else [[text,54,Color("fff3d2")]]
	var width: float=0
	for part in parts: width+=round_font.get_string_size(part[0],HORIZONTAL_ALIGNMENT_LEFT,-1,part[1]).x
	var p: Vector2=Vector2((640-width)/2,211)
	var cursor: Vector2=p
	# Orange extrusion and slanted lettering retain the reference's arcade treatment.
	for part in parts:
		arcade_word(part[0],cursor,part[1],part[2])
		cursor.x+=round_font.get_string_size(part[0],HORIZONTAL_ALIGNMENT_LEFT,-1,part[1]).x
	draw_colored_polygon(PackedVector2Array([Vector2(p.x-4,222),Vector2(274,218),Vector2(271,221),Vector2(p.x-6,225)]),Color("ff802d"))
	draw_colored_polygon(PackedVector2Array([Vector2(367,218),Vector2(p.x+width+3,214),Vector2(p.x+width+1,218),Vector2(365,221)]),Color("ff802d"))
	hud_text(subtitle,Vector2(260,225),12,IVORY,HORIZONTAL_ALIGNMENT_CENTER,120)
