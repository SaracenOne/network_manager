extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

var signal_table : Array = [
	{"singleton":"EntityManager", "signal":"entity_added", "method":"_entity_added"},
	{"singleton":"EntityManager", "signal":"entity_removed", "method":"_entity_removed"},
	{"singleton":"NetworkManager", "signal":"network_process", "method":"_network_manager_process"},
]

signal spawn_state_for_new_client_ready(p_network_id, p_network_writer)

# Server-only
var network_entities_pending_spawn : Array = []
var network_entities_pending_reparenting : Array = []
var network_entities_pending_destruction : Array = []

func _entity_added(p_entity : entity_const) -> void:
	if NetworkManager.is_server():
		if p_entity.get_network_identity_node() != null:
			if network_entities_pending_spawn.has(p_entity):
				ErrorManager.error("Attempted to spawn two identical network entities")
				
			network_entities_pending_spawn.append(p_entity)
		
func _entity_removed(p_entity : entity_const) -> void:
	if NetworkManager.is_server():
		if p_entity.get_network_identity_node() != null:
			if network_entities_pending_spawn.has(p_entity):
				network_entities_pending_spawn.remove(network_entities_pending_spawn.find(p_entity))
			else:
				network_entities_pending_destruction.append(p_entity)

"""

"""

func get_entity_root_node() -> Node:
	return NetworkManager.get_entity_root_node()

func send_parent_entity_update(p_instance : Node) -> void:
	if NetworkManager.is_server():
		if p_instance.get_network_identity_node() != null:
			if network_entities_pending_reparenting.has(p_instance) == false:
				network_entities_pending_reparenting.append(p_instance)
	
func create_entity_instance(p_packed_scene : PackedScene, p_name : String = "Entity", p_master_id : int = NetworkManager.SERVER_MASTER_PEER_ID) -> Node:
	var instance : Node = p_packed_scene.instance()
	instance.set_name(p_name)
	instance.set_network_master(p_master_id)
	
	return instance
	
func instantiate_entity(p_packed_scene : PackedScene, p_name : String = "Entity", p_master_id : int = NetworkManager.SERVER_MASTER_PEER_ID) -> Node:
	var instance : Node = create_entity_instance(p_packed_scene, p_name, p_master_id)
	NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.ADD_ENTITY, instance, null)
	
	return instance
		
	
""" Network ids end """

"""
Server
"""

func create_entity_spawn_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	network_writer = network_entity_manager.write_entity_scene_id(p_entity, network_entity_manager.networked_scenes, network_writer)
	network_writer = network_entity_manager.write_entity_instance_id(p_entity, network_writer)
	network_writer = network_entity_manager.write_entity_parent_id(p_entity, network_writer)
	network_writer = network_entity_manager.write_entity_network_master(p_entity, network_writer)
	
	var entity_state : network_writer_const = p_entity.get_network_identity_node().get_state(network_writer_const.new(), true)
	network_writer.put_writer(entity_state)

	return network_writer

func create_entity_destroy_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	network_writer = network_entity_manager.write_entity_instance_id(p_entity, network_writer)

	return network_writer
	
func create_entity_set_parent_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	network_writer = network_entity_manager.write_entity_instance_id(p_entity, network_writer)
	network_writer = network_entity_manager.write_entity_parent_id(p_entity, network_writer)

	return network_writer
	
func create_entity_transfer_master_command(p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	network_writer = network_entity_manager.write_entity_instance_id(p_entity, network_writer)
	network_writer = network_entity_manager.write_entity_network_master(p_entity, network_writer)

	return network_writer
	
func create_entity_command(p_command : int, p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = network_writer_const.new()
	match p_command:
		network_constants_const.SPAWN_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.SPAWN_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_spawn_command(p_entity))
		network_constants_const.DESTROY_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.DESTROY_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_destroy_command(p_entity))
		network_constants_const.SET_PARENT_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.SET_PARENT_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_set_parent_command(p_entity))
		network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND:
			network_writer.put_u8(network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND)
			network_writer.put_writer(create_entity_transfer_master_command(p_entity))
		_:
			ErrorManager.error("Unknown entity message")

	return network_writer
		
			
func get_network_scene_id_from_path(p_path : String) -> int:
	var path : String = p_path
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	while(1):
		var network_scene_id : int = network_entity_manager.networked_scenes.find(path)
		
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
		
	ErrorManager.error("Could not find network scene id for {path}".format({"path":path}))
	return -1
	
func create_spawn_state_for_new_client(p_network_id : int) -> void:
	NetworkManager.network_entity_manager.scene_tree_execution_table.call("_execute_scene_tree_execution_table_unsafe")
	
	var entities : Array = get_tree().get_nodes_in_group("NetworkedEntities")
	var entity_spawn_writers : Array = []
	for entity in entities:
		if entity.is_inside_tree() and not network_entities_pending_spawn.has(entity):
			entity_spawn_writers.append(create_entity_command(network_constants_const.SPAWN_ENTITY_COMMAND, entity))
		
	var network_writer : network_writer_const = network_writer_const.new()
	for entity_spawn_writer in entity_spawn_writers:
		network_writer.put_writer(entity_spawn_writer)
		
	emit_signal("spawn_state_for_new_client_ready", p_network_id, network_writer)
	
func _network_manager_process(p_id : int, p_delta : float) -> void:
	if p_delta > 0.0:
		var synced_peers : Array = NetworkManager.get_valid_send_peers(p_id)
			
		for synced_peer in synced_peers:
			var reliable_network_writer : network_writer_const = network_writer_const.new()
			
			if p_id == NetworkManager.session_master:
				# Spawn commands
				var entity_spawn_writers : Array = []
				for entity in network_entities_pending_spawn:
					entity_spawn_writers.append(create_entity_command(network_constants_const.SPAWN_ENTITY_COMMAND, entity))
					
				# Reparent commands
				var entity_reparent_writers : Array = []
				for entity in network_entities_pending_reparenting:
					entity_reparent_writers.append(create_entity_command(network_constants_const.SET_PARENT_ENTITY_COMMAND, entity))
					
				# Destroy commands
				var entity_destroy_writers : Array = []
				for entity in network_entities_pending_destruction:
					entity_destroy_writers.append(create_entity_command(network_constants_const.DESTROY_ENTITY_COMMAND, entity))
					
				# Put spawn, reparent, and destroy commands into the reliable channel
				for entity_spawn_writer in entity_spawn_writers:
					reliable_network_writer.put_writer(entity_spawn_writer)
				for entity_reparent_writer in entity_reparent_writers:
					reliable_network_writer.put_writer(entity_reparent_writer)
				for entity_destroy_writer in entity_destroy_writers:
					reliable_network_writer.put_writer(entity_destroy_writer)
					
			if reliable_network_writer.get_size() > 0:
				NetworkManager.send_packet(reliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
			
		# Flush the pending spawn, parenting, and destruction queues
		network_entities_pending_spawn = []
		network_entities_pending_reparenting = []
		network_entities_pending_destruction = []
"""
Client
"""
func get_packed_scene_for_scene_id(p_scene_id : int) -> PackedScene:
	assert(NetworkManager.network_entity_manager.networked_scenes.size() > p_scene_id)
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	var path : String = network_entity_manager.networked_scenes[p_scene_id]
	assert(ResourceLoader.exists(path))
	
	var packed_scene : PackedScene = ResourceLoader.load(path)
	assert(packed_scene is PackedScene)
	
	return packed_scene

func decode_entity_spawn_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true
	
	if valid_sender_id == false:
		ErrorManager.error("decode_entity_spawn_command: recieved spawn command from non server ID!")
		return null
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var scene_id : int = network_entity_manager.read_entity_scene_id(p_network_reader, network_entity_manager.networked_scenes)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if instance_id <= network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var parent_id : int = network_entity_manager.read_entity_parent_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
		
	var network_master : int = network_entity_manager.read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
	
	var packed_scene : PackedScene = get_packed_scene_for_scene_id(scene_id)
	var entity_instance : entity_const = packed_scene.instance()
	
	# If this entity has a parent, try to find it
	var parent_instance : Node = null
	if parent_id > network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		var network_identity : Node = network_entity_manager.get_network_instance_identity(parent_id)
		if network_identity:
			parent_instance = network_identity.get_entity_node()
		else:
			ErrorManager.error("decode_entity_spawn_command: could not find parent entity!")
	
	entity_instance.set_name("Entity")
	entity_instance.set_network_master(network_master)
	
	var network_identity_node : Node = entity_instance.get_network_identity_node()
	network_identity_node.set_network_instance_id(instance_id)
	network_identity_node.update_state(p_network_reader, true)
	NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.ADD_ENTITY, entity_instance, parent_instance)
	
	return p_network_reader
	
func decode_entity_destroy_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true	

	if valid_sender_id == false:
		ErrorManager.error("decode_entity_destroy_command: recieved destroy command from non server ID!")
		return null
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.REMOVE_ENTITY, entity_instance, null)
	else:
		ErrorManager.error("Attempted to destroy invalid node")
	
	return p_network_reader
	
func decode_entity_set_parent_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true	

	if valid_sender_id == false:
		ErrorManager.error("decode_entity_set_parent_command: recieved set_parent command from non server ID!")
		return null
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
		
	var parent_id : int = network_entity_manager.read_entity_parent_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_set_parent_command: eof!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		# If this entity has a parent, try to find it
		var parent_instance : Node = null
		
		var network_identity : Node = network_entity_manager.get_network_instance_identity(parent_id)
		if network_identity:
			parent_instance = network_identity.get_entity_node()
		
		NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.REPARENT_ENTITY, entity_instance, parent_instance)
	else:
		ErrorManager.error("Attempted to reparent invalid node")
	
	return p_network_reader
	
func decode_entity_transfer_master_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true	

	if valid_sender_id == false:
		ErrorManager.error("decode_entity_transfer_master_command: recieved transfer master command from non server ID!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if instance_id <= network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	var network_master : int = network_entity_manager.read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		entity_instance.set_network_master(network_master)
	else:
		ErrorManager.error("Attempted to transfer master of invalid node")
	
	return p_network_reader

		
func decode_replication_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.SPAWN_ENTITY_COMMAND:
			p_network_reader = decode_entity_spawn_command(p_packet_sender_id, p_network_reader)
		network_constants_const.DESTROY_ENTITY_COMMAND:
			p_network_reader = decode_entity_destroy_command(p_packet_sender_id, p_network_reader)
		network_constants_const.SET_PARENT_ENTITY_COMMAND:
			p_network_reader = decode_entity_set_parent_command(p_packet_sender_id, p_network_reader)
		network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND:
			p_network_reader = decode_entity_transfer_master_command(p_packet_sender_id, p_network_reader)
	
	return p_network_reader
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		ConnectionUtil.connect_signal_table(signal_table, self)
