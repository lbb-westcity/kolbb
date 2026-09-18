extends SceneTree

func _initialize() -> void:
	for who in preload("res://scripts/battle.gd").ART:
		var frames: SpriteFrames=load("res://assets/fighters/"+who+"_frames.tres").duplicate()
		for animation in frames.get_animation_names():
			if animation not in ["core","core_alt"]: frames.remove_animation(animation)
		for key in frames.get_meta_list():
			if key not in ["foot_anchor","logo_core"]: frames.remove_meta(key)
		assert(ResourceSaver.save(frames,"res://assets/fighters/"+who+"_preview.tres")==OK)
	quit()
