extends Position3D

func _enter_tree():
	add_to_group("NetworkSpawnGroup")
	
func _exit_tree():
	remove_from_group("NetworkSpawnGroup")