extends "res://addons/entity_manager/component_node.gd"
class_name NetworkIdentity
tool

const network_manager_const = preload("res://addons/network_manager/network_manager.gd")
const network_replication_manager_const = preload("res://addons/network_manager/network_replication_manager.gd")

var network_manager : network_manager_const = null
var network_replication_manager : network_replication_manager_const = null

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

"""         
Network Instance ID
"""
var network_instance_id : int = network_replication_manager_const.NULL_NETWORK_INSTANCE_ID setget set_network_instance_id
var network_scene_id : int = -1 setget set_network_scene_id

func is_network_manager_valid() -> bool:
	if network_manager != null and network_replication_manager != null:
		return true
		
	return false

func set_network_instance_id(p_id : int) -> void:
	if !Engine.is_editor_hint() and is_network_manager_valid():
		if network_instance_id == network_replication_manager_const.NULL_NETWORK_INSTANCE_ID:
			network_instance_id = p_id
			network_replication_manager.register_network_instance_id(network_instance_id, self)
		else:
			printerr("network_instance_id has already been assigned")

func set_network_scene_id(p_id : int) -> void:
	if !Engine.is_editor_hint():
		if network_scene_id == -1:
			network_scene_id = p_id
		else:
			printerr("network_scene_id has already been assigned")

func on_exit() -> void:
	if !Engine.is_editor_hint() and is_network_manager_valid():
		network_replication_manager.unregister_network_instance_id(network_instance_id)
	
func get_state(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	p_writer = get_entity_node().network_logic_node.on_serialize(p_writer, p_initial_state)
	return p_writer
	
func update_state(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	p_reader = get_entity_node().network_logic_node.on_deserialize(p_reader, p_initial_state)
	return p_reader
	
func get_network_root_node() -> Node:
	if network_replication_manager:
		return network_replication_manager.get_entity_root_node()
		
	return null
	
func send_parent_entity_update() -> void:
	if network_replication_manager:
		network_replication_manager.send_parent_entity_update(get_entity_node())
	
func _ready() -> void:
	if !Engine.is_editor_hint():
		if has_node("/root/NetworkManager"):
			network_manager = get_node("/root/NetworkManager")
			
		if has_node("/root/NetworkReplicationManager"):
			network_replication_manager = get_node("/root/NetworkReplicationManager")
		
		if is_network_manager_valid():
			
			if network_manager.is_server():
				set_network_instance_id(network_replication_manager.get_next_network_id())
				
			set_network_scene_id(network_replication_manager.get_network_scene_id_from_path(get_entity_node().filename))
			
			get_entity_node().add_to_group("NetworkedEntities")
			if get_entity_node().connect("tree_exited", self, "on_exit") != OK:
				ErrorManager.error("Could not connect tree_exited!")
