extends Node
tool

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

const MAXIMUM_REPLICATION_PACKET_SIZE = 1024

var dummy_replication_writer = network_writer_const.new(MAXIMUM_REPLICATION_PACKET_SIZE) # For debugging purposes
var replication_writers = {}

var signal_table : Array = [
	{"singleton":"NetworkManager", "signal":"peer_unregistered", "method":"_reclaim_peers_entities"},
	{"singleton":"EntityManager", "signal":"entity_added", "method":"_entity_added"},
	{"singleton":"EntityManager", "signal":"entity_removed", "method":"_entity_removed"},
	{"singleton":"NetworkManager", "signal":"network_process", "method":"_network_manager_process"},
	{"singleton":"NetworkManager", "signal":"network_flush", "method":"_network_manager_flush"},
	
	{"singleton":"NetworkManager", "signal":"game_hosted", "method":"_game_hosted"},
	{"singleton":"NetworkManager", "signal":"connection_succeeded", "method":"_connected_to_server"},
	
	{"singleton":"NetworkManager", "signal":"server_peer_connected", "method":"_server_peer_connected"},
	{"singleton":"NetworkManager", "signal":"server_peer_disconnected", "method":"_server_peer_disconnected"},
]

signal spawn_state_for_new_client_ready(p_network_id, p_network_writer)

# Server-only
var network_entities_pending_spawn : Array = []
var network_entities_pending_destruction : Array = []

# Client/Server
var network_entities_pending_request_transfer_master : Array = []

func _entity_added(p_entity : entity_const) -> void:
	if NetworkManager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_spawn.has(p_entity):
				ErrorManager.error("Attempted to spawn two identical network entities")
				
			network_entities_pending_spawn.append(p_entity)
		
func _entity_removed(p_entity : entity_const) -> void:
	if NetworkManager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_request_transfer_master.has(p_entity):
				network_entities_pending_request_transfer_master.remove(network_entities_pending_request_transfer_master.find(p_entity))
			
			if network_entities_pending_spawn.has(p_entity):
				network_entities_pending_spawn.remove(network_entities_pending_spawn.find(p_entity))
			else:
				network_entities_pending_destruction.append(p_entity)

func _entity_request_transfer_master(p_entity : entity_const) -> void:
	if network_entities_pending_destruction.has(network_entities_pending_destruction.find(p_entity)):
		return
	else:
		if network_entities_pending_request_transfer_master.has(p_entity) == false:
			network_entities_pending_request_transfer_master.push_back(p_entity)

"""

"""

func get_entity_root_node() -> Node:
	return NetworkManager.get_entity_root_node()
	
func create_entity_instance(p_packed_scene : PackedScene, p_name : String = "NetEntity", p_master_id : int = NetworkManager.SERVER_MASTER_PEER_ID) -> Node:
	print_debug("Creating entity instance " + p_name + " of type " + p_packed_scene.resource_path)
	var instance : Node = p_packed_scene.instance()
	instance.set_name(p_name)
	instance.set_network_master(p_master_id)
	
	return instance
	
func instantiate_entity(p_packed_scene : PackedScene, p_name : String = "NetEntity", p_master_id : int = NetworkManager.SERVER_MASTER_PEER_ID) -> Node:
	var instance : Node = create_entity_instance(p_packed_scene, p_name, p_master_id)
	NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.ADD_ENTITY, instance, null)
	
	return instance
		
	
""" Network ids end """

"""
Server
"""

func write_entity_spawn_command(p_entity : entity_const, p_network_writer : network_writer_const) -> network_writer_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_scene_id(p_entity, network_entity_manager.networked_scenes, p_network_writer)
	p_network_writer = network_entity_manager.write_entity_instance_id(p_entity, p_network_writer)
	p_network_writer = network_entity_manager.write_entity_network_master(p_entity, p_network_writer)
	
	var entity_state : network_writer_const = p_entity.network_identity_node.get_state(null, true)
	p_network_writer.put_writer(entity_state, entity_state.get_position())

	return p_network_writer

func write_entity_destroy_command(p_entity : entity_const, p_network_writer : network_writer_const) -> network_writer_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_instance_id(p_entity, p_network_writer)

	return p_network_writer

func write_entity_request_master_command(p_entity : entity_const, p_network_writer : network_writer_const) -> network_writer_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_instance_id(p_entity, p_network_writer)

	return p_network_writer
	
func write_entity_transfer_master_command(p_entity : entity_const, p_network_writer : network_writer_const) -> network_writer_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager

	p_network_writer = network_entity_manager.write_entity_instance_id(p_entity, p_network_writer)
	p_network_writer = network_entity_manager.write_entity_network_master(p_entity, p_network_writer)

	return p_network_writer
	
func create_entity_command(p_command : int, p_entity : entity_const) -> network_writer_const:
	var network_writer : network_writer_const = NetworkManager.network_entity_command_writer_cache
	network_writer.seek(0)
	
	match p_command:
		network_constants_const.SPAWN_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.SPAWN_ENTITY_COMMAND)
			network_writer = write_entity_spawn_command(p_entity, network_writer)
		network_constants_const.DESTROY_ENTITY_COMMAND:
			network_writer.put_u8(network_constants_const.DESTROY_ENTITY_COMMAND)
			network_writer = write_entity_destroy_command(p_entity, network_writer)
		network_constants_const.REQUEST_ENTITY_MASTER_COMMAND:
			network_writer.put_u8(network_constants_const.REQUEST_ENTITY_MASTER_COMMAND)
			network_writer = write_entity_request_master_command(p_entity, network_writer)
		network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND:
			network_writer.put_u8(network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND)
			network_writer = write_entity_transfer_master_command(p_entity, network_writer)
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
	
	print("Spawn state = [")
	for entity in entities:
		if entity.is_inside_tree() and not network_entities_pending_spawn.has(entity):
			print("{ " + entity.get_name() + " }")
	print("] for " + str(p_network_id))
	
	for entity in entities:
		if entity.is_inside_tree() and not network_entities_pending_spawn.has(entity):
			entity_spawn_writers.append(create_entity_command(network_constants_const.SPAWN_ENTITY_COMMAND, entity))
		
	var network_writer : network_writer_const = network_writer_const.new()
	for entity_spawn_writer in entity_spawn_writers:
		network_writer.put_writer(entity_spawn_writer)
		
	print("Spawn state size : " + str(network_writer.get_size()))
		
	emit_signal("spawn_state_for_new_client_ready", p_network_id, network_writer)
	
func flush() -> void:
	network_entities_pending_spawn = []
	network_entities_pending_destruction = []
	network_entities_pending_request_transfer_master = []
	
func _network_manager_flush() -> void:
	flush()
	
func _network_manager_process(p_id : int, p_delta : float) -> void:
	if p_delta > 0.0:
		if network_entities_pending_spawn.size() > 0 or network_entities_pending_destruction.size() or network_entities_pending_request_transfer_master.size() > 0:
			
			# Debugging information
			if network_entities_pending_spawn.size():
				print("Spawning entities = [")
				for entity in network_entities_pending_spawn:
					print("{ " + entity.get_name() + " }")
				print("]")
				
			if network_entities_pending_destruction.size():
				print("Destroying entities = [")
				for entity in network_entities_pending_destruction:
					print("{ " + entity.get_name() + " }")
				print("]")
			# Debugging end
			
			var synced_peers : Array = NetworkManager.copy_valid_send_peers(p_id, true)
				
			for synced_peer in synced_peers:
				var network_writer_state : network_writer_const = null
				
				if synced_peer != -1:
					network_writer_state = replication_writers[synced_peer]
				else:
					network_writer_state = dummy_replication_writer
				
				network_writer_state.seek(0)
				
				if p_id == NetworkManager.session_master:
					# Spawn commands
					for entity in network_entities_pending_spawn:
						network_writer_state.put_writer(create_entity_command(network_constants_const.SPAWN_ENTITY_COMMAND, entity))
						
					# Destroy commands
					for entity in network_entities_pending_destruction:
						network_writer_state.put_writer(create_entity_command(network_constants_const.DESTROY_ENTITY_COMMAND, entity))
						
					# Transfer master commands
					for entity in network_entities_pending_request_transfer_master:
						network_writer_state.put_writer(create_entity_command(network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND, entity))
				else:
					# Request master commands
					for entity in network_entities_pending_request_transfer_master:
						network_writer_state.put_writer(create_entity_command(network_constants_const.REQUEST_ENTITY_MASTER_COMMAND, entity))
						
				if network_writer_state.get_position() > 0:
					var raw_data : PoolByteArray = network_writer_state.get_raw_data(network_writer_state.get_position())
					NetworkManager.network_flow_manager.queue_packet_for_send(ref_pool_const.new(raw_data), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
				
			# Flush the pending spawn, parenting, and destruction queues
			flush()
"""
Client
"""
func get_scene_path_for_scene_id(p_scene_id : int) -> String:
	if NetworkManager.network_entity_manager.networked_scenes.size() > p_scene_id:
		var network_entity_manager : Node = NetworkManager.network_entity_manager
		var path : String = network_entity_manager.networked_scenes[p_scene_id]
	
		return path
	else:
		return ""

func get_packed_scene_for_path(p_path : String) -> PackedScene:
	if ResourceLoader.exists(p_path):
		var packed_scene : PackedScene = ResourceLoader.load(p_path)
		assert(packed_scene is PackedScene)
	
		return packed_scene
	else:
		return null

func decode_entity_spawn_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true
	
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
		
	var network_master : int = network_entity_manager.read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_spawn_command: eof!")
		return null
	
	# If this was not from a valid send, return null
	if valid_sender_id == false:
		ErrorManager.error("decode_entity_spawn_command: received spawn command from non server ID!")
		return null
	
	var scene_path : String = get_scene_path_for_scene_id(scene_id)
	if scene_path == "":
		ErrorManager.error("decode_entity_spawn_command: received invalid scene id {scene_id}!".format({"scene_id":scene_id}))
		return null
	
	var packed_scene : PackedScene = get_packed_scene_for_path(scene_path)
	if packed_scene == null:
		ErrorManager.error("decode_entity_spawn_command: received invalid packed_scene for path {scene_path}!".format({"scene_path":scene_path}))
		return null
		
	var entity_instance : entity_const = packed_scene.instance()
	if entity_instance == null:
		ErrorManager.error("decode_entity_spawn_command: null instance!")
		return null
	
	entity_instance._threaded_instance_setup(instance_id, p_network_reader)
	
	entity_instance.set_name("NetEntity_{instance_id}".format({"instance_id":entity_instance.network_identity_node.network_instance_id}))
	entity_instance.set_network_master(network_master)
	
	entity_instance._threaded_instance_post_setup()
	
	NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.ADD_ENTITY, entity_instance, null)
	
	return p_network_reader
	
func decode_entity_destroy_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true	
	
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_destroy_command: eof!")
		return null
		
	# If this was not from a valid send, return null
	if valid_sender_id == false:
		ErrorManager.error("decode_entity_destroy_command: received destroy command from non server ID!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		NetworkManager.network_entity_manager.scene_tree_execution_command(NetworkManager.network_entity_manager.scene_tree_execution_table_const.REMOVE_ENTITY, entity_instance, null)
	else:
		ErrorManager.error("Attempted to destroy invalid node")
	
	return p_network_reader

	
func decode_entity_request_master_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	var valid_sender_id = false

	if NetworkManager.is_session_master():
		valid_sender_id = true
		
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_request_master_command: eof!")
		return null
		
	var instance_id : int = network_entity_manager.read_entity_instance_id(p_network_reader)
	if instance_id <= network_entity_manager.NULL_NETWORK_INSTANCE_ID:
		ErrorManager.error("decode_entity_request_master_command: eof!")
		return null
	
	# If this was not from a valid send, return null
	if valid_sender_id == false:
		ErrorManager.error("decode_entity_request_master_command: request master command sent directly to client!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		if entity_instance.can_request_master_from_peer(p_packet_sender_id):
			request_to_become_master(entity_instance, p_packet_sender_id)
		else:
			# The request was denied, but queue an update message anyway to
			# at least inform the client (possible optimisation, only send this
			# to the requesting client)
			_entity_request_transfer_master(entity_instance)
	else:
		ErrorManager.error("Attempted to request master of invalid node")
	
	return p_network_reader
	
	
# Parse an entity transfer master command. Will only be accepted
func decode_entity_transfer_master_command(p_packet_sender_id : int, p_network_reader : network_reader_const) -> network_reader_const:
	var network_entity_manager : Node = NetworkManager.network_entity_manager
	
	var valid_sender_id = false

	if p_packet_sender_id == NetworkManager.session_master or p_packet_sender_id == NetworkManager.SERVER_MASTER_PEER_ID:
		valid_sender_id = true
		
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
		
	var new_network_master : int = network_entity_manager.read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		ErrorManager.error("decode_entity_transfer_master_command: eof!")
		return null
		
	# If this was not from a valid send, return null
	if valid_sender_id == false:
		ErrorManager.error("decode_entity_transfer_master_command: received transfer master command from non server ID!")
		return null
	
	if network_entity_manager.network_instance_ids.has(instance_id):
		var entity_instance : Node = network_entity_manager.network_instance_ids[instance_id].get_entity_node()
		if entity_instance.can_transfer_master_from_session_master(new_network_master):
			entity_instance.process_master_request(new_network_master)
	else:
		ErrorManager.error("Attempted to transfer master of invalid node")
	
	return p_network_reader

# Called me the network manager to process replication messages
func decode_replication_buffer(p_packet_sender_id : int, p_network_reader : network_reader_const, p_command : int) -> network_reader_const:
	match p_command:
		network_constants_const.SPAWN_ENTITY_COMMAND:
			p_network_reader = decode_entity_spawn_command(p_packet_sender_id, p_network_reader)
		network_constants_const.DESTROY_ENTITY_COMMAND:
			p_network_reader = decode_entity_destroy_command(p_packet_sender_id, p_network_reader)
		network_constants_const.REQUEST_ENTITY_MASTER_COMMAND:
			p_network_reader = decode_entity_request_master_command(p_packet_sender_id, p_network_reader)
		network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND:
			p_network_reader = decode_entity_transfer_master_command(p_packet_sender_id, p_network_reader)
		_:
			ErrorManager.error("Unknown Entity replication command")
	
	return p_network_reader
	
# Called to claim mastership over an entity. Mastership
# will be immediately claimed an a request/transfer request
# will go into the queue
func request_to_become_master(p_entity : Node, p_id : int) -> void:
	p_entity.process_master_request(p_id)
	_entity_request_transfer_master(p_entity)

# Called when peer disconnects. If the peer is currently the session master,
# they will attempt to claim mastership over all entities owned by the
# disconnecting peer
func _reclaim_peers_entities(p_id : int) -> void:
	if NetworkManager.is_session_master():
		var entities : Array = EntityManager.get_all_entities()
		for entity_instance in entities:
			if entity_instance.get_network_master() == p_id:
				if entity_instance.can_request_master_from_peer(NetworkManager.get_current_peer_id()):
					entity_instance.request_to_become_master()
	
func _game_hosted() -> void:
	replication_writers = {}
	
func _connected_to_server() -> void:
	replication_writers = {}
	var network_writer : network_writer_const = network_writer_const.new(MAXIMUM_REPLICATION_PACKET_SIZE)
	replication_writers[NetworkManager.SERVER_MASTER_PEER_ID] = network_writer
	
func _server_peer_connected(p_id : int) -> void:
	var network_writer : network_writer_const = network_writer_const.new(MAXIMUM_REPLICATION_PACKET_SIZE)
	replication_writers[p_id] = network_writer

func _server_peer_disconnected(p_id : int) -> void:
	if replication_writers.erase(p_id) == false:
		printerr("network_state_manager: attempted disconnect invalid peer!")
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		ConnectionUtil.connect_signal_table(signal_table, self)
