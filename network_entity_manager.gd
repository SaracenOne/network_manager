extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")


# List of all the packed scenes which can be transferred over the network
# via small spawn commands
var networked_scenes : Array = []

# The maximum amount of entities which can be active in a scene at once
var max_networked_entities : int = 4096 # Default

# Returns the root node all network entities should parented to
func get_entity_root_node() -> Node:
	return NetworkManager.get_entity_root_node()

const scene_tree_execution_table_const = preload("scene_tree_execution_table.gd")
var scene_tree_execution_table : Reference = scene_tree_execution_table_const.new()

# Dispatches a deferred add/remove entity command to the scene tree execution table 
func scene_tree_execution_command(p_command : int, p_entity_instance : Node, p_parent_instance : Node):
	var parent_instance : Node = null
	if p_parent_instance == null:
		parent_instance = get_entity_root_node()
	else:
		parent_instance = p_parent_instance
	
	scene_tree_execution_table.scene_tree_execution_command(p_command, p_entity_instance, parent_instance)

###############
# Network ids #
###############

# Invalid network instance id
const NULL_NETWORK_INSTANCE_ID = 0
# The first instance id assigned
const FIRST_NETWORK_INSTANCE_ID = 1
# The last instance id which can be assigned
# before flipping over 
const LAST_NETWORK_INSTANCE_ID = 4294967295

# The next network instance id attempted to be assigned when requested
var next_network_instance_id : int = FIRST_NETWORK_INSTANCE_ID
# Map of all currently active instance IDs
var network_instance_ids : Dictionary = {}

# Writes the index id for the p_entity's base scene as defined in the list
# of p_networked_scenes to the p_writer. The index byte length is determined
# by the number of network scenes. Returns the p_writer
static func write_entity_scene_id(p_entity : entity_const, \
	p_networked_scenes : Array, \
	p_writer : network_writer_const) -> network_writer_const:
	
	var network_identity_node = p_entity.network_identity_node
	if p_networked_scenes.size() > 0xff:
		p_writer.put_u16(network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffff:
		p_writer.put_u32(network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffffffff:
		p_writer.put_u64(network_identity_node.network_scene_id)
	else:
		p_writer.put_u8(network_identity_node.network_scene_id)
		
	return p_writer

# Reads from p_reader the index id for an entity's base scene type as defined
# in the list of p_networked_scenes. The index byte length read is determind
# by the number of network scenes. Returns the scene id.
static func read_entity_scene_id(p_reader : network_reader_const, \
	p_networked_scenes : Array) -> int:
	
	if p_networked_scenes.size() > 0xff:
		return p_reader.get_u16()
	elif p_networked_scenes.size() > 0xffff:
		return p_reader.get_u32()
	elif p_networked_scenes.size() > 0xffffffff:
		return p_reader.get_u64()
	else:
		return p_reader.get_u8()

# Writes the network master id for p_entity to p_writer. Returns the p_writer
static func write_entity_network_master(p_entity : entity_const, \
	p_writer : network_writer_const) -> network_writer_const:
	
	p_writer.put_u32(p_entity.get_network_master())
	
	return p_writer

# Reads the network master id for an entity from p_reader.
# Returns the network master id
static func read_entity_network_master(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()

# Writes the instance id for p_entity to p_writer. Returns the p_writer
static func write_entity_instance_id(p_entity : entity_const, \
p_writer : network_writer_const) -> network_writer_const:
	p_writer.put_u32(p_entity.network_identity_node.network_instance_id)
		
	return p_writer
	
# Reads the instance id for an entity from p_reader.
# Returns the instance id
static func read_entity_instance_id(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()

# Clears all active instance ids
func reset_server_instances() -> void:
	network_instance_ids = {}
	next_network_instance_id = FIRST_NETWORK_INSTANCE_ID # Reset the network id counter

# Requests a new instance id. It will flip to FIRST_NETWORK_INSTANCE_ID
# if it reaches the LAST_NETWORK_INSTANCE_ID, and if one is already in
# use, it will loop until it finds an unused one. Returns an instance ID
func get_next_network_id() -> int:
	var network_instance_id : int = next_network_instance_id
	next_network_instance_id += 1
	if next_network_instance_id >= LAST_NETWORK_INSTANCE_ID:
		NetworkLogger.printl("Maximum network instance ids used. Reverting to first")
		next_network_instance_id = FIRST_NETWORK_INSTANCE_ID
		
	# If the instance id is already in use, keep iterating until
	# we find an unused one
	while(network_instance_ids.has(network_instance_id)):
		network_instance_id = next_network_instance_id
		next_network_instance_id += 1
		if next_network_instance_id >= LAST_NETWORK_INSTANCE_ID:
			NetworkLogger.printl("Maximum network instance ids used. Reverting to first")
			next_network_instance_id = FIRST_NETWORK_INSTANCE_ID
	
	return network_instance_id

# Registers an entity's network identity in the network_instance_id map
# TODO: add more graceful error handling for exceeding maximum number of
# entities
func register_network_instance_id(p_network_instance_id : int, p_network_idenity : Node) -> void:
	if network_instance_ids.size() > max_networked_entities:
		NetworkLogger.error("EXCEEDED MAXIMUM ALLOWED INSTANCE IDS!")
		return
	
	network_instance_ids[p_network_instance_id] = p_network_idenity
	
# Unregisters a network_instance from the network_instance_id map
func unregister_network_instance_id(p_network_instance_id : int) -> void:
	if !network_instance_ids.erase(p_network_instance_id):
		NetworkLogger.error("Could not unregister network instance id: {network_instance_id}".format({"network_instance_id":str(p_network_instance_id)}))
	
# Returns the network identity node for a given network instance id
func get_network_instance_identity(p_network_instance_id : int) -> Node:
	if network_instance_ids.has(p_network_instance_id):
		return network_instance_ids[p_network_instance_id]
	
	return null
	
func get_network_scene_paths() -> Array:
	return networked_scenes
	
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
	
	if !Engine.is_editor_hint():
		var network_scenes_config = ProjectSettings.get_setting("network/config/networked_scenes")
		if typeof(network_scenes_config) != TYPE_STRING_ARRAY:
			networked_scenes = Array()
		else:
			networked_scenes = Array(network_scenes_config)
			
		max_networked_entities = ProjectSettings.get_setting("network/config/max_networked_entities")
	
	if(!ProjectSettings.has_setting("network/config/max_networked_entities")):
		ProjectSettings.set_setting("network/config/max_networked_entities", max_networked_entities)
