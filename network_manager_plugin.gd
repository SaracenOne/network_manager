extends EditorPlugin
tool

var editor_interface = null

func get_name(): 
	return "NetworkManager"

func _enter_tree():
	editor_interface = get_editor_interface()
	
	add_autoload_singleton("NetworkManager", "res://addons/network_manager/network_manager.gd")

func _exit_tree():
	remove_autoload_singleton("NetworkManager")
