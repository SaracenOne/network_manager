extends Node
tool

const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

var max_networked_entities = 4096 # Default

# List of all the packed scenes which can be transferred over the network
# via small spawn commands
var networked_scenes = []

enum {
	SPAWN_ENTITY_COMMAND = 0,
	UPDATE_ENTITY_COMMAND,
	DESTROY_ENTITY_COMMAND,
}

static func write_entity_scene_id(p_entity, p_networked_scenes, p_writer):
	if p_networked_scenes.size() > 0xff:
		p_writer.put_u16(p_entity.network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffff:
		p_writer.put_u32(p_entity.network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffffffff:
		p_writer.put_u64(p_entity.network_identity_node.network_scene_id)
	else:
		p_writer.put_u8(p_entity.network_identity_node.network_scene_id)
		
	return p_writer
	
static func read_entity_scene_id(p_reader, p_networked_scenes):
	if p_networked_scenes.size() > 0xff:
		return p_reader.get_u16()
	elif p_networked_scenes.size() > 0xffff:
		return p_reader.get_u32()
	elif p_networked_scenes.size() > 0xffffffff:
		return p_reader.get_u64()
	else:
		return p_reader.get_u8()
		
static func write_entity_instance_id(p_entity, p_writer):
	p_writer.put_u32(p_entity.network_identity_node.network_instance_id)
		
	return p_writer
	
static func read_entity_instance_id(p_reader):
	return p_reader.get_u32()
		
static func write_entity_network_master(p_entity, p_writer):
	p_writer.put_u32(p_entity.get_network_master())
		
	return p_writer
	
static func read_entity_network_master(p_reader):
	return p_reader.get_u32()

signal spawn_state_for_new_client_ready(p_network_id, p_network_writer)

# Server-only
var network_entities_pending_spawn = []
var network_entities_pending_destruction = []

func _entity_added(p_entity):
	if NetworkManager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_spawn.has(p_entity):
				ErrorManager.fatal_error("Attempted to spawn two identical network entities")
				
			network_entities_pending_spawn.append(p_entity)
		

func _entity_removed(p_entity):
	if NetworkManager.is_server():
		if p_entity.network_identity_node != null:
			if network_entities_pending_spawn.has(p_entity):
				network_entities_pending_spawn.remove(p_entity)
			else:
				network_entities_pending_destruction.append(p_entity)

""" Network ids """

var next_network_instance_id = 0
var network_instance_ids = {}

func reset_server_instances():
	network_instance_ids = {}
	next_network_instance_id = 0 # Reset the network id counter

"""

"""

func add_entity_instance(p_instance):
	get_tree().get_root().add_child(p_instance)
	
	return p_instance
	
func create_entity_instance(p_packed_scene, p_name = "Entity", p_master_id = NetworkManager.SERVER_PEER_ID):
	var instance = p_packed_scene.instance()
	instance.set_name(p_name)
	instance.set_network_master(p_master_id)
	
	return instance
	
func instantiate_entity(p_packed_scene, p_name = "Entity", p_master_id = NetworkManager.SERVER_PEER_ID):
	var instance = create_entity_instance(p_packed_scene, p_name, p_master_id)
	instance = add_entity_instance(instance)
	return instance
		
	
func instantiate_entity_transformed(p_packed_scene, p_name = "Entity", p_master_id = NetworkManager.SERVER_PEER_ID, p_transform = Transform()):
	var instance = instantiate_entity(p_packed_scene, p_name, p_master_id)
	if instance:
		instance.set_global_transform(p_transform)
	
	return instance
	
func instantiate_entity_replicated(p_scene_id, p_instance_id, p_name = "Entity", p_master_id = NetworkManager.SERVER_PEER_ID, p_transform = Transform()):
	pass
	
func get_next_network_id():
	# TODO: validate overflow and duplicates
	var network_instance_id = next_network_instance_id
	next_network_instance_id += 1
	return network_instance_id
	
func register_network_instance_id(p_network_instance_id, p_node):
	network_instance_ids[p_network_instance_id] = p_node
	
func unregister_network_instance_id(p_network_instance_id):
	network_instance_ids.erase(p_network_instance_id)
	
func get_instance_network_instance_id(p_network_instance_id):
	if network_instance_ids.has(p_network_instance_id):
		return network_instance_ids[p_network_instance_id] 
	
	return null
	
""" Network ids end """

"""
Server
"""

func create_entity_spawn_command(p_entity):
	var network_writer = network_writer_const.new()

	network_writer = write_entity_scene_id(p_entity, networked_scenes, network_writer)
	network_writer = write_entity_instance_id(p_entity, network_writer)
	network_writer = write_entity_network_master(p_entity, network_writer)
	
	var entity_state = p_entity.network_identity_node.get_state(network_writer_const.new(), true)
	network_writer.put_writer(entity_state)

	return network_writer
	
func create_entity_update_command(p_entity):
	var network_writer = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)
	var entity_state = p_entity.network_identity_node.get_state(network_writer_const.new(), false)
	network_writer.put_u32(entity_state.get_size())
	network_writer.put_writer(entity_state)

	return network_writer
	
func create_entity_destroy_command(p_entity):
	var network_writer = network_writer_const.new()

	network_writer = write_entity_instance_id(p_entity, network_writer)

	return network_writer
	
func create_entity_command(p_command, p_entity):
	var network_writer = network_writer_const.new()
	match p_command:
		SPAWN_ENTITY_COMMAND:
			network_writer.put_u8(SPAWN_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_spawn_command(p_entity))
		UPDATE_ENTITY_COMMAND:
			network_writer.put_u8(UPDATE_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_update_command(p_entity))
		DESTROY_ENTITY_COMMAND:
			network_writer.put_u8(DESTROY_ENTITY_COMMAND)
			network_writer.put_writer(create_entity_destroy_command(p_entity))
		_:
			ErrorManager.fatal_error("Unknown entity message")

	return network_writer
		
			
func get_network_scene_id_from_path(p_path):
	var network_scene_id = networked_scenes.find(p_path)
	
	if network_scene_id == -1:
		ErrorManager.fatal_error("Could not find network scene id for " + p_path)
	
	return network_scene_id
	
func create_spawn_state_for_new_client(p_network_id):
	var entities = get_tree().get_nodes_in_group("NetworkedEntities")
	var entity_spawn_writers = []
	for entity in entities:
		if entity.is_inside_tree() and not network_entities_pending_spawn.has(entity):
			entity_spawn_writers.append(create_entity_command(SPAWN_ENTITY_COMMAND, entity))
		
	var network_writer = network_writer_const.new()
	for entity_spawn_writer in entity_spawn_writers:
		network_writer.put_writer(entity_spawn_writer)
		
	emit_signal("spawn_state_for_new_client_ready", p_network_id, network_writer)
	
func _network_manager_process(p_delta):
	# Spawn commands
	var entity_spawn_writers = []
	for entity in network_entities_pending_spawn:
		entity_spawn_writers.append(create_entity_command(SPAWN_ENTITY_COMMAND, entity))
		
	# Destroy commands
	var entity_destroy_writers = []
	for entity in network_entities_pending_destruction:
		entity_destroy_writers.append(create_entity_command(DESTROY_ENTITY_COMMAND, entity))
		
	# Put Spawn and destroy commands into the reliable channel
	var reliable_network_writer = network_writer_const.new()
	for entity_spawn_writer in entity_spawn_writers:
		reliable_network_writer.put_writer(entity_spawn_writer)
	for entity_destroy_writer in entity_destroy_writers:
		reliable_network_writer.put_writer(entity_destroy_writer)
	
	# Update commands
	var entities = get_tree().get_nodes_in_group("NetworkedEntities")
	var entity_update_writers = []
	for entity in entities:
		if entity.is_inside_tree():
			entity_update_writers.append(create_entity_command(UPDATE_ENTITY_COMMAND, entity))
		
	# Put the update commands into the unreliable channel
	var unreliable_network_writer = network_writer_const.new()
	for entity_update_writer in entity_update_writers:
		unreliable_network_writer.put_writer(entity_update_writer)
		
	# Flush the pending spawn and destruction queues
	network_entities_pending_spawn = []
	network_entities_pending_destruction = []
		
	var synced_peers = NetworkManager.get_synced_peers()
	for synced_peer in synced_peers:
		if reliable_network_writer.get_size() > 0:
			NetworkManager.send_packet(reliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
		if unreliable_network_writer.get_size() > 0:
			NetworkManager.send_packet(unreliable_network_writer.get_raw_data(), synced_peer, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
"""
Client
"""
func get_packed_scene_for_scene_id(p_scene_id):
	assert(networked_scenes.size() > p_scene_id)
	
	var path = networked_scenes[p_scene_id]
	assert(ResourceLoader.has(path))
	
	var packed_scene = ResourceLoader.load(path)
	assert(packed_scene is PackedScene)
	
	return packed_scene

func decode_entity_spawn_command(p_network_reader):
	if p_network_reader.is_eof():
		return null
	var scene_id = read_entity_scene_id(p_network_reader, networked_scenes)
	if p_network_reader.is_eof():
		return null
	var instance_id = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		return null
	var network_master = read_entity_network_master(p_network_reader)
	if p_network_reader.is_eof():
		return null
	
	var packed_scene = get_packed_scene_for_scene_id(scene_id)
	var instance = packed_scene.instance()
	instance.set_name("Entity")
	instance.set_network_master(network_master)
	
	add_entity_instance(instance)
	instance.network_identity_node.set_network_instance_id(instance_id)
	instance.network_identity_node.update_state(p_network_reader, true)
	
	return p_network_reader
	
func decode_entity_update_command(p_network_reader):
	if p_network_reader.is_eof():
		return null
	var instance_id = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		return null
	
	var entity_state_size = p_network_reader.get_u32()
	if network_instance_ids.has(instance_id):
		var instance = network_instance_ids[instance_id]
		instance.update_state(p_network_reader, false)
	else:
		p_network_reader.seek(p_network_reader.get_position() + entity_state_size)
	
	return p_network_reader
	
func decode_entity_destroy_command(p_network_reader):
	if p_network_reader.is_eof():
		return null
	var instance_id = read_entity_instance_id(p_network_reader)
	if p_network_reader.is_eof():
		return null
	
	if network_instance_ids.has(instance_id):
		var instance = network_instance_ids[instance_id]
		instance.entity_node.queue_free()
		instance.entity_node.get_parent().remove_child(instance.entity_node)
	else:
		ErrorManager.fatal_error("Attempted to destroy invalid node")
	
	return p_network_reader
	
func decode_replication_buffer(p_buffer):
	var network_reader = network_reader_const.new(p_buffer)
	
	while network_reader and network_reader.is_eof() == false:
		var command = network_reader.get_u8()
		match command:
			SPAWN_ENTITY_COMMAND:
				network_reader = decode_entity_spawn_command(network_reader)
			UPDATE_ENTITY_COMMAND:
				network_reader = decode_entity_update_command(network_reader)
			DESTROY_ENTITY_COMMAND:
				network_reader = decode_entity_destroy_command(network_reader)
			_:
				break

	return network_reader
	
func _ready():
	if(!ProjectSettings.has_setting("network/config/networked_scenes")):
		ProjectSettings.set_setting("network/config/networked_scenes", PoolStringArray())
		
	var networked_objects_property_info = {
		"name": "network/config/networked_scenes",
		"type": TYPE_STRING_ARRAY,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": ""
	}
	
	if(!ProjectSettings.has_setting("network/config/max_networked_entities")):
		ProjectSettings.set_setting("network/config/max_networked_entities", max_networked_entities)
	
	if Engine.is_editor_hint() == false:
		EntityManager.connect("entity_added", self, "_entity_added")
		EntityManager.connect("entity_removed", self, "_entity_removed")
		
		NetworkManager.connect("network_process", self, "_network_manager_process")
		
		var network_scenes_config = ProjectSettings.get_setting("network/config/networked_scenes")
		if typeof(network_scenes_config) != TYPE_STRING_ARRAY:
			networked_scenes = []
		else:
			networked_scenes = Array(network_scenes_config)
			
		max_networked_entities = ProjectSettings.get_setting("network/config/max_networked_entities")