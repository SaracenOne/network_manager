extends "res://addons/entity_manager/component_node.gd"
class_name NetworkIdentity
tool

const network_manager_const = preload("res://addons/network_manager/network_manager.gd")
const network_entity_manager_const = preload("res://addons/network_manager/network_entity_manager.gd")

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

"""         
Network Instance ID
"""
var network_instance_id : int = network_entity_manager_const.NULL_NETWORK_INSTANCE_ID setget set_network_instance_id
var network_scene_id : int = -1 setget set_network_scene_id


func set_network_instance_id(p_id : int) -> void:
	if !Engine.is_editor_hint():
		if network_instance_id == network_entity_manager_const.NULL_NETWORK_INSTANCE_ID:
			network_instance_id = p_id
			NetworkManager.network_entity_manager.register_network_instance_id(network_instance_id, self)
		else:
			printerr("network_instance_id has already been assigned")

func set_network_scene_id(p_id : int) -> void:
	if !Engine.is_editor_hint():
		if network_scene_id == -1:
			network_scene_id = p_id
		else:
			printerr("network_scene_id has already been assigned")

func on_exit() -> void:
	if !Engine.is_editor_hint():
		NetworkManager.network_entity_manager.unregister_network_instance_id(network_instance_id)
	
func get_state(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	p_writer = get_entity_node().get_network_logic_node().on_serialize(p_writer, p_initial_state)
	return p_writer
	
func update_state(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	p_reader = get_entity_node().get_network_logic_node().on_deserialize(p_reader, p_initial_state)
	return p_reader
	
func get_network_root_node() -> Node:
	return NetworkManager.get_entity_root_node()
	
func send_parent_entity_update() -> void:
	NetworkManager.network_replication_manager.send_parent_entity_update(get_entity_node())
	
func _ready() -> void:
	if !Engine.is_editor_hint():
		if NetworkManager.is_server():
			set_network_instance_id(NetworkManager.network_entity_manager.get_next_network_id())
			
		set_network_scene_id(NetworkManager.network_replication_manager.get_network_scene_id_from_path(get_entity_node().filename))
		
		get_entity_node().add_to_group("NetworkedEntities")
		if get_entity_node().connect("tree_exited", self, "on_exit") != OK:
			ErrorManager.error("Could not connect tree_exited!")
