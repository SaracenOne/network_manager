extends Position3D
class_name NetworkSpawn

func _enter_tree() -> void:
	add_to_group("NetworkSpawnGroup")
	
func _exit_tree() -> void:
	remove_from_group("NetworkSpawnGroup")
