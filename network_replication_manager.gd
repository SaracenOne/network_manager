extends Node
tool

const network_manager_const = preload("res://addons/network_manager/network_manager.gd")
const entity_manager_const = preload("res://addons/entity_manager/entity_manager.gd")
const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

var network_manager : network_manager_const = null
var entity_manager : entity_manager_const = null
var max_networked_entities : int = 4096 # Default

"""
List of all the packed scenes which can be transferred over the network
via small spawn commands
"""
var networked_scenes : Array = []

enum {
	UPDATE_ENTITY_COMMAND = 0,
	SPAWN_ENTITY_COMMAND,
	DESTROY_ENTITY_COMMAND,
	SET_PARENT_ENTITY_COMMAND,
	TRANSFER_ENTITY_MASTER_COMMAND
}

""" Network ids """

const NULL_NETWORK_INSTANCE_ID = 0
const FIRST_NETWORK_INSTANCE_ID = 1

var next_network_instance_id : int = FIRST_NETWORK_INSTANCE_ID
var network_instance_ids : Dictionary = {}

static func write_entity_scene_id(p_entity : entity_const, p_networked_scenes : Array, p_writer : network_writer_const) -> network_writer_const:
	if p_networked_scenes.size() > 0xff:
		p_writer.put_u16(p_entity.network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffff:
		p_writer.put_u32(p_entity.network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffffffff:
		p_writer.put_u64(p_entity.network_identity_node.network_scene_id)
	else:
		p_writer.put_u8(p_entity.network_identity_node.network_scene_id)
		
	return p_writer
	
static func read_entity_scene_id(p_reader : network_reader_const, p_networked_scenes : Array) -> int:
	if p_networked_scenes.size() > 0xff:
		return p_reader.get_u16()
	elif p_networked_scenes.size() > 0xffff:
		return p_reader.get_u32()
	elif p_networked_scenes.size() > 0xffffffff:
		return p_reader.get_u64()
	else:
		return p_reader.get_u8()
		
static func write_entity_instance_id(p_entity : entity_const, p_writer : network_writer_const) -> network_writer_const:
	p_writer.put_u32(p_entity.network_identity_node.network_instance_id)
		
	return p_writer
	
static func read_entity_instance_id(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()
	
static func write_entity_parent_id(p_entity : entity_const, p_writer : network_writer_const) -> network_writer_const:
	if p_entity.entity_parent:
		p_writer.put_u32(p_entity.entity_parent.network_identity_node.network_instance_id)
	else:
		p_writer.put_u32(NULL_NETWORK_INSTANCE_ID)
		
	return p_writer
	
static func read_entity_parent_id(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()
		
static func write_entity_network_master(p_entity : entity_const, p_writer : network_writer_const) -> network_writer_const:
	p_writer.put_u32(p_entity.get_network_master())
		
	return p_writer
	
static func read_entity_network_master(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()

signal spawn_state_for_new_client_ready(p_network_id, p_network_writer)

# Server-only
var network_entities_pending_spawn : Array = []
var network_entities_pending_reparenting : Array = []
var network_entities_pending_destruction : Array = []

func _entity_added(p_entity : entity_const) -> void:
	if network_manager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_spawn.has(p_entity):
				ErrorManager.error("Attempted to spawn two identical network entities")
				
			network_entities_pending_spawn.append(p_entity)
		

func _entity_removed(p_entity : entity_const) -> void:
	if network_manager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_spawn.has(p_entity):
				network_entities_pending_spawn.remove(network_entities_pending_spawn.find(p_entity))
			else:
				network_entities_pending_destruction.append(p_entity)

func reset_server_instances() -> void:
	network_instance_ids = {}
	next_network_instance_id = FIRST_NETWORK_INSTANCE_ID # Reset the network id counter

"""

"""

func get_entity_root_node() -> Node:
	return get_tree().get_root()

func send_parent_entity_update(p_instance : Node) -> void:
	if network_manager.is_server():
		if p_instance.network_identity_node != null:
			if network_entities_pending_reparenting.has(p_instance) == false:
				network_entities_pending_reparenting.append(p_instance)

func add_entity_instance(p_instance : Node, p_parent : Node = null) -> Node:
	if p_parent:
		p_parent.add_child(p_instance)
	else:
		get_entity_root_node().add_child(p_instance)
	
	return p_instance
	
func reparent_entity_instance(p_instance : Node, p_parent : Node = null) -> void:
	if !p_instance.is_inside_tree():
		ErrorManager.error("reparent_entity_instance: entity not inside tree!")
		
	var last_global_transform : Transform = Transform()
	if p_instance.logic_node:
		last_global_transform = p_instance.logic_node.get_global_transform()
		
	p_instance.get_parent().remove_child(p_instance)
	
	if p_parent:
		p_parent.add_child(p_instance)
	else:
		get_entity_root_node().add_child(p_instance)
		
	if p_instance.logic_node:
		p_instance.logic_node.set_global_transform(last_global_transform)
	
func create_entity_instance(p_packed_scene : PackedScene, p_name : String = "Entity", p_master_id : int = network_manager_const.SERVER_MASTER_PEER_ID) -> Node:
	var instance : Node = p_packed_scene.instance()
	instance.set_name(p_name)
	instance.set_network_master(p_master_id)
	
	return instance
	
func instantiate_entity(p_packed_scene : PackedScene, p_name : String = "Entity", p_master_id : int = network_manager_const.SERVER_MASTER_PEER_ID) -> Node:
	var instance : Node = create_entity_instance(p_packed_scene, p_name, p_master_id)
	return add_entity_instance(instance)
		
	
func instantiate_entity_transformed(p_packed_scene : PackedScene, p_name : String = "Entity", p_master_id : int = network_manager_const.SERVER_MASTER_PEER_ID, p_transform : Transform = Transform()) -> Node:
	var instance : Node = instantiate_entity(p_packed_scene, p_name, p_master_id)
	if instance:
		instance.set_global_transform(p_transform)
	
	return instance
	
func get_next_network_id() -> int:
	# TODO: validate overflow and duplicates
	var network_instance_id : int = next_network_instance_id
	next_network_instance_id += 1
	return network_instance_id
	
func register_network_instance_id(p_network_instance_id : int, p_node : Node) -> void:
	network_instance_ids[p_network_instance_id] = p_node
	
func unregister_network_instance_id(p_network_instance_id : int) -> void:
	if network_instance_ids.erase(p_network_instance_id) == false:
		printerr("Could not unregister network instance id " + str(p_network_instance_id))
	
func get_network_instance_identity(p_network_instance_id : int) -> Node:
	if network_instance_ids.has(p_network_instance_id):
		return network_instance_ids[p_network_instance_id]
	
	return null
	
""" Network ids end """

"""
Server
"""

func create_entity_spawn_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = write_entity_scene_id(p_entity, networked_scenes, network_writer)
	network_writer = write_entity_instance_id(p_entity, network_writer)
	network_writer = write_entity_parent_id(p_entity, network_writer)
	network_writer = write_entity_network_master(p_entity, network_writer)
	
	var entity_state : network_writer_const = p_entity.network_identity_node.get_state(network_writer_const.new(), true)
	network_writer.put_writer(entity_state)

	return network_writer
	
func create_entity_update_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)
	var entity_state : network_writer_const = p_entity.network_identity_node.get_state(network_writer_const.new(), false)
	network_writer.put_u32(entity_state.get_size())
	network_writer.put_writer(entity_state)

	return network_writer
	
func create_entity_destroy_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)

	return network_writer
	
func create_entity_set_parent_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)
	network_writer = write_entity_parent_id(p_entity, network_writer)

	return network_writer
	
func create_entity_transfer_master_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)
	network_writer = write_entity_network_master(p_entity, network_writer)

	return network_writer
	
func create_entity_command(p_command : int, p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	match p_command:
		UPDATE_ENTITY_COMMAND:
			network_writer.put_u8(UPDATE_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_update_command(p_entity))
		SPAWN_ENTITY_COMMAND:
			network_writer.put_u8(SPAWN_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_spawn_command(p_entity))
		DESTROY_ENTITY_COMMAND:
			network_writer.put_u8(DESTROY_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_destroy_command(p_entity))
		SET_PARENT_ENTITY_COMMAND:
			network_writer.put_u8(SET_PARENT_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_set_parent_command(p_entity))
		TRANSFER_ENTITY_MASTER_COMMAND:
			network_writer.put_u8(TRANSFER_ENTITY_MASTER_COMMAND)
			network_writer.put_writer(create_entity_transfer_master_command(p_entity))
		_:
			ErrorManager.error("Unknown entity message")

	return network_writer
		
			
func get_network_scene_id_from_path(p_path : String) -> int:
	var path : String = p_path
	
	while(1):
		var network_scene_id : int = networked_scenes.find(path)
		
		# If a valid packed scene was not found, try next to search for it via its inheritance chain
		if network_scene_id == -1:
			if ResourceLoader.exists(path):
				var packed_scene : PackedScene = ResourceLoader.load(path)
				if packed_scene:
					var scene_state : SceneState = packed_scene.get_state()
					if scene_state.get_node_count() > 0:
						var sub_packed_scene : PackedScene = scene_state.get_node_instance(0)
						if sub_packed_scene:
							path = sub_packed_scene.resource_path
							continue
			break
		else:
			return network_scene_id
		
	ErrorManager.error("Could not find network scene id for " + path)
	return -1
	
func create_spawn_state_for_new_client(p_network_id : int) -> void:
	var entities : Array = get_tree().get_nodes_in_group("NetworkedEntities")
	var entity_spawn_writers : Array = []
	for entity in entities:
		if entity.is_inside_tree() and not network_entities_pending_spawn.has(entity):
			entity_spawn_writers.append(create_entity_command(SPAWN_ENTITY_COMMAND, entity))
		
	var network_writer : network_writer_const = network_writer_const.new()
	for entity_spawn_writer in entity_spawn_writers:
		network_writer.put_writer(entity_spawn_writer)
		
	emit_signal("spawn_state_for_new_client_ready", p_network_id, network_writer)
	
func _network_manager_process(p_id : int, p_delta : float) -> void:
	if p_delta > 0.0:
		var synced_peers : Array = []
		if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
			synced_peers = network_manager.get_synced_peers()
		else:
			synced_peers = [NetworkManager.SERVER_MASTER_PEER_ID]
			
		for synced_peer in synced_peers:
			var reliable_network_writer : network_writer_const = network_writer_const.new()
			var unreliable_network_writer : network_writer_const = network_writer_const.new()
			
			if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
				# Spawn commands
				var entity_spawn_writers : Array = []
				for entity in network_entities_pending_spawn:
					entity_spawn_writers.append(create_entity_command(SPAWN_ENTITY_COMMAND, entity))
					
				# Reparent commands
				var entity_reparent_writers : Array = []
				for entity in network_entities_pending_reparenting:
					entity_reparent_writers.append(create_entity_command(SET_PARENT_ENTITY_COMMAND, entity))
					
				# Destroy commands
				var entity_destroy_writers : Array = []
				for entity in network_entities_pending_destruction:
					entity_destroy_writers.append(create_entity_command(DESTROY_ENTITY_COMMAND, entity))
					
				# Put spawn, reparent, and destroy commands into the reliable channel
				for entity_spawn_writer in entity_spawn_writers:
					reliable_network_writer.put_writer(entity_spawn_writer)
				for entity_reparent_writer in entity_reparent_writers:
					reliable_network_writer.put_writer(entity_reparent_writer)
				for entity_destroy_writer in entity_destroy_writers:
					reliable_network_writer.put_writer(entity_destroy_writer)
				
			# Update commands
			var entities : Array = get_tree().get_nodes_in_group("NetworkedEntities")
			var entity_update_writers : Array = []
			for entity in entities:
				if entity.is_inside_tree():
					### get this working
					if p_id == NetworkManager.SERVER_MASTER_PEER_ID:
						entity_update_writers.append(create_entity_command(UPDATE_ENTITY_COMMAND, entity))
					else:
						if (entity.get_network_master() == p_id):
							entity_update_writers.append(create_entity_command(UPDATE_ENTITY_COMMAND, entity))
							
			# Put the update commands into the unreliable channel
			for entity_update_writer in entity_update_writers:
				unreliable_network_writer.put_writer(entity_update_writer)
					
			if reliable_network_writer.get_size() > 0:
				network_manager.send_packet(reliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
			if unreliable_network_writer.get_size() > 0:
				network_manager.send_packet(unreliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
			
		# Flush the pending spawn, parenting, and destruction queues
		network_entities_pending_spawn = []
		network_entities_pending_reparenting = []
		network_entities_pending_destruction = []
"""
Client
"""
func get_packed_scene_for_scene_id(p_scene_id : int) -> PackedScene:
	assert(networked_scenes.size() > p_scene_id)
	
	var path : String = networked_scenes[p_scene_id]
	assert(ResourceLoader.exists(path))
	
	var packed_scene : PackedScene = ResourceLoader.load(path)
	assert(packed_scene is PackedScene)
	
	return packed_scene
	
func decode_entity_update_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_update_command: eof!")
		return null
		
	var instance_id : int = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_update_command: eof!")
		return null
	
	var entity_state_size : int = p_network_reader.get_u32()
	if network_instance_ids.has(instance_id):
		var network_identity_instance : Node = network_instance_ids[instance_id]
		if (network_manager.is_server() and network_identity_instance.get_network_master() == p_packet_sender_id) or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
			network_identity_instance.update_state(p_network_reader, false)
	else:
		p_network_reader.seek(p_network_reader.get_position() + entity_state_size)
	
	return p_network_reader

func decode_entity_spawn_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	if p_packet_sender_id != NetworkManager.SERVER_MASTER_PEER_ID:
		ErrorManager.error("decode_entity_spawn_command: recieved spawn command from non server ID!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var scene_id : int = read_entity_scene_id(p_network_reader, networked_scenes)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var instance_id : int = read_entity_instance_id(p_network_reader)
	if instance_id <= NULL_NETWORK_INSTANCE_ID:
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var parent_id : int = read_entity_parent_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var network_master : int = read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
	
	var packed_scene : PackedScene = get_packed_scene_for_scene_id(scene_id)
	var entity_instance : entity_const = packed_scene.instance()
	
	# If this entity has a parent, try to find it
	var parent_instance : Node = null
	if parent_id > NULL_NETWORK_INSTANCE_ID:
		var network_identity : Node = get_network_instance_identity(parent_id)
		if network_identity:
			parent_instance = network_identity.get_entity_node()
		else:
			ErrorManager.error("decode_entity_spawn_command: could not find parent entity!")
	
	entity_instance.set_name("Entity")
	if network_manager.peers.has(network_master):
		entity_instance.set_network_master(network_master)
	else:
		ErrorManager.error("decode_entity_spawn_command: could not find master id!")
	
	entity_instance = add_entity_instance(entity_instance, parent_instance)
	entity_instance.network_identity_node.set_network_instance_id(instance_id)
	entity_instance.network_identity_node.update_state(p_network_reader, true)
	
	return p_network_reader
	
func decode_entity_destroy_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	if p_packet_sender_id != NetworkManager.SERVER_MASTER_PEER_ID:
		ErrorManager.error("decode_entity_destroy_command: recieved destroy command from non server ID!")
		return null
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
		
	var instance_id : int = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
	
	if network_instance_ids.has(instance_id):
		var entity_instance : Node = network_instance_ids[instance_id].get_entity_node()
		entity_instance.queue_free()
		entity_instance.get_parent().remove_child(entity_instance.get_entity_node())
	else:
		ErrorManager.error("Attempted to destroy invalid node")
	
	return p_network_reader
	
func decode_entity_set_parent_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	if p_packet_sender_id != NetworkManager.SERVER_MASTER_PEER_ID:
		ErrorManager.error("decode_entity_set_parent_command: recieved set_parent command from non server ID!")
		return null
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
		
	var instance_id : int = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
		
	var parent_id : int = read_entity_parent_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
	
	if network_instance_ids.has(instance_id):
		var entity_instance : Node = network_instance_ids[instance_id].get_entity_node()
		# If this entity has a parent, try to find it
		var parent_instance : Node = null
		
		var network_identity : Node = get_network_instance_identity(parent_id)
		if network_identity:
			parent_instance = network_identity.get_entity_node()
		
		reparent_entity_instance(entity_instance, parent_instance) 
	else:
		ErrorManager.error("Attempted to reparent invalid node")
	
	return p_network_reader
	
func decode_entity_transfer_master_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	if p_packet_sender_id != NetworkManager.SERVER_MASTER_PEER_ID:
		ErrorManager.error("decode_entity_transfer_master_command: recieved transfer master command from non server ID!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	var instance_id : int = read_entity_instance_id(p_network_reader)
	if instance_id <= NULL_NETWORK_INSTANCE_ID:
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	var network_master : int = read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
	
	if network_instance_ids.has(instance_id):
		var entity_instance : Node = network_instance_ids[instance_id].get_entity_node()
		if network_manager.peers.has(network_master):
			entity_instance.set_network_master(network_master)
		else:
			ErrorManager.error("decode_entity_transfer_master_command: could not find master id!")
	else:
		ErrorManager.error("Attempted to transfer master of invalid node")
	
	return p_network_reader
	
func decode_replication_buffer(p_packet_sender_id : int, p_buffer : PoolByteArray) -> void:
	var network_reader : network_reader_const = network_reader_const.new(p_buffer)
	
	while network_reader and network_reader.is_eof() == false:
		var command = network_reader.get_u8()
		match command:
			UPDATE_ENTITY_COMMAND:
				network_reader = decode_entity_update_command(p_packet_sender_id, network_reader)
			SPAWN_ENTITY_COMMAND:
				network_reader = decode_entity_spawn_command(p_packet_sender_id, network_reader)
			DESTROY_ENTITY_COMMAND:
				network_reader = decode_entity_destroy_command(p_packet_sender_id, network_reader)
			SET_PARENT_ENTITY_COMMAND:
				network_reader = decode_entity_set_parent_command(p_packet_sender_id, network_reader)
			TRANSFER_ENTITY_MASTER_COMMAND:
				network_reader = decode_entity_transfer_master_command(p_packet_sender_id, network_reader)
			_:
				break
	
func _ready() -> void:
	if(!ProjectSettings.has_setting("network/config/networked_scenes")):
		ProjectSettings.set_setting("network/config/networked_scenes", PoolStringArray())
		
	var networked_objects_property_info : Dictionary = {
		"name": "network/config/networked_scenes",
		"type": TYPE_STRING_ARRAY,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": ""
	}
	
	ProjectSettings.add_property_info(networked_objects_property_info)
	
	if(!ProjectSettings.has_setting("network/config/max_networked_entities")):
		ProjectSettings.set_setting("network/config/max_networked_entities", max_networked_entities)
	
	if Engine.is_editor_hint() == false and has_node("/root/NetworkManager") and has_node("/root/EntityManager"):
		network_manager = get_node("/root/NetworkManager")
		entity_manager = get_node("/root/EntityManager")
		
		var connect_result : int = OK
		
		connect_result = entity_manager.connect("entity_added", self, "_entity_added")
		if connect_result != OK:
			printerr("NetworkReplicationManager: entity_added could not be connected")
		connect_result = entity_manager.connect("entity_removed", self, "_entity_removed")
		if connect_result != OK:
			printerr("NetworkReplicationManager: entity_removed could not be connected")
		
		connect_result = network_manager.connect("network_process", self, "_network_manager_process")
		if connect_result != OK:
			printerr("NetworkReplicationManager: network_process could not be connected")
		
		var network_scenes_config = ProjectSettings.get_setting("network/config/networked_scenes")
		if typeof(network_scenes_config) != TYPE_STRING_ARRAY:
			networked_scenes = []
		else:
			networked_scenes = Array(network_scenes_config)
			
		max_networked_entities = ProjectSettings.get_setting("network/config/max_networked_entities")
