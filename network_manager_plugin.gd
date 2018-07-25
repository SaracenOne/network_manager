extends EditorPlugin
tool

var editor_interface = null

func get_name(): 
	return "NetworkManager"

func _enter_tree():
	editor_interface = get_editor_interface()
	
	add_autoload_singleton("NetworkManager", "res://addons/network_manager/network_manager.gd")
	add_autoload_singleton("NetworkReplicationManager", "res://addons/network_manager/network_replication_manager.gd")
	add_custom_type("NetworkSpawn", "Position3D", preload("network_spawn.gd"), editor_interface.get_base_control().get_icon("Position3D", "EditorIcons"))
	add_custom_type("NetworkIdentity", "Node", preload("network_identity.gd"), editor_interface.get_base_control().get_icon("Node", "EditorIcons"))
	add_custom_type("NetworkLogic", "Node", preload("network_logic.gd"), editor_interface.get_base_control().get_icon("Node", "EditorIcons"))
	add_custom_type("NetworkTransform", "Node", preload("network_transform.gd"), editor_interface.get_base_control().get_icon("Node", "EditorIcons"))

func _exit_tree():
	remove_autoload_singleton("NetworkManager")
	remove_autoload_singleton("NetworkReplicationManager")
	remove_custom_type("NetworkSpawn")
	remove_custom_type("NetworkIdentity")
	remove_custom_type("NetworkLogic")
	remove_custom_type("NetworkTransform")