extends SceneTree
const Battle = preload("res://scripts/battle.gd")
func _initialize() -> void:
	var b = Battle.new()
	for i in 600: b.step([0,0])
	assert(b.state.phase=="fight")
	print("SMOKE OK ", b.checksum())
	quit()
