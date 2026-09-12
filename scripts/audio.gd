extends Node
var music: AudioStreamPlayer
var urgency: AudioStreamPlayer
var voices: Array = []
var clips: Dictionary = {}
var track: String = ""
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
var last_sounds: Dictionary = {}
# Headless simulations validate clips without starting audio decoder playbacks.
var silent: bool = DisplayServer.get_name()=="headless"
func _exit_tree() -> void:
	for player in voices+[music,urgency]:
		if is_instance_valid(player): player.stop();player.stream=null
	clips.clear()
func _ready() -> void:
	music=AudioStreamPlayer.new();add_child(music)
	urgency=AudioStreamPlayer.new();add_child(urgency)
	for i in 4:
		var p=AudioStreamPlayer.new();add_child(p);voices.append(p)
	for filename in ResourceLoader.list_directory("res://assets/audio"):
		if filename.ends_with(".wav") or filename.ends_with(".ogg"):
			clips[filename.get_basename()]=load("res://assets/audio/"+filename)
	for id in ["menu","battle","urgency"]:
		if clips.has(id):
			if clips[id] is AudioStreamOggVorbis: clips[id].loop=true
			elif clips[id] is AudioStreamWAV:
				clips[id].loop_mode=AudioStreamWAV.LOOP_FORWARD
				clips[id].loop_end=int(clips[id].get_length()*clips[id].mix_rate)
func configure(settings: Dictionary) -> void:
	master_volume=settings.master/100.0;music_volume=settings.music/100.0;sfx_volume=settings.sfx/100.0
	if music:
		music.volume_db=linear_to_db(maxf(0.0001,master_volume*music_volume))
		urgency.volume_db=music.volume_db-7
func play_music(id: String) -> void:
	if silent or id==track or not clips.has(id): return
	track=id;music.stream=clips[id];music.play()
	urgency.stop()
func urgent(value: bool) -> void:
	if silent: return
	if value and not urgency.playing and clips.has("urgency"):
		urgency.stream=clips.urgency;urgency.play()
	elif not value: urgency.stop()
func pause_music(value: bool) -> void:
	music.stream_paused=value;urgency.stream_paused=value
func voice_for(id: String) -> AudioStreamPlayer:
	var priority: int=3 if id in ["ko","time","victory","round","fight"] else 2 if id in ["super","slam","heavy"] else 1 if id in ["light","block","max"] else 0
	var candidate: AudioStreamPlayer=null
	for player in voices:
		if not player.playing:
			candidate=player;break
		if candidate==null or int(player.get_meta("priority",0))<int(candidate.get_meta("priority",0)) or (player.get_meta("priority",0)==candidate.get_meta("priority",0) and player.get_meta("started",0)<candidate.get_meta("started",0)):
			candidate=player
	if candidate.playing and int(candidate.get_meta("priority",0))>priority: return null
	candidate.set_meta("priority",priority);candidate.set_meta("started",Time.get_ticks_usec())
	return candidate

func sound(id: String, pitch: float = 1.0) -> void:
	if silent or not clips.has(id) or last_sounds.get(id,-1)==Engine.get_process_frames(): return
	last_sounds[id]=Engine.get_process_frames()
	var player: AudioStreamPlayer=voice_for(id)
	if player==null: return
	player.stream=clips[id];player.pitch_scale=pitch
	player.volume_db=linear_to_db(maxf(0.0001,master_volume*sfx_volume))-3
	player.play()
