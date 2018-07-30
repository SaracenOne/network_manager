extends "res://addons/entity_manager/component_node.gd"
tool

const network_manager_const = preload("res://addons/network_manager/network_manager.gd")
const network_replication_manager_const = preload("res://addons/network_manager/network_replication_manager.gd")

var network_manager : network_manager_const = null
var network_replication_manager : network_replication_manager_const = null

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

var writer : network_writer_const = network_writer_const.new()

export(bool) var server_only : bool = false
export(bool) var local_player_authority : bool = false

signal network_update_complete(p_identity)

"""         
Network Instance ID
"""
var network_instance_id : int = -1 setget set_network_instance_id
var network_scene_id : int= -1 setget set_network_scene_id

func is_network_manager_valid():
	if network_manager != null and network_replication_manager != null:
		return true
		
	return false

func set_network_instance_id(p_id : int) -> void:
	if !Engine.is_editor_hint() and is_network_manager_valid():
		if network_instance_id == -1:
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
	p_writer = entity_node.network_logic_node.on_serialize(p_writer, p_initial_state)
	return p_writer
	
func update_state(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	p_reader = entity_node.network_logic_node.on_deserialize(p_reader, p_initial_state)
	return p_reader
	
func _ready() -> void:
	if !Engine.is_editor_hint():
		if has_node("/root/NetworkManager"):
			network_manager = get_node("/root/NetworkManager")
			
		if has_node("/root/NetworkReplicationManager"):
			network_replication_manager = get_node("/root/NetworkReplicationManager")
		
		if is_network_manager_valid():
			
			if network_manager.is_server():
				set_network_instance_id(network_replication_manager.get_next_network_id())
				
			set_network_scene_id(network_replication_manager.get_network_scene_id_from_path(entity_node.filename))
			
			entity_node.add_to_group("NetworkedEntities")
			entity_node.connect("tree_exited", self, "on_exit")