extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")
const network_constants_const = preload("network_constants.gd")
const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")

"""
List of all the packed scenes which can be transferred over the network
via small spawn commands
"""
var networked_scenes : Array = []

var max_networked_entities : int = 4096 # Default

func get_entity_root_node() -> Node:
	return NetworkManager.get_entity_root_node()

const scene_tree_execution_table_const = preload("scene_tree_execution_table.gd")
var scene_tree_execution_table : Reference = scene_tree_execution_table_const.new()

func scene_tree_execution_command(p_command : int, p_entity_instance : Node, p_parent_instance : Node):
	var parent_instance : Node = null
	if p_parent_instance == null:
		parent_instance = get_entity_root_node()
	else:
		parent_instance = p_parent_instance
	
	scene_tree_execution_table.scene_tree_execution_command(p_command, p_entity_instance, parent_instance)

""" Network ids """

const NULL_NETWORK_INSTANCE_ID = 0
const FIRST_NETWORK_INSTANCE_ID = 1
const LAST_NETWORK_INSTANCE_ID = 4294967295

var next_network_instance_id : int = FIRST_NETWORK_INSTANCE_ID
var network_instance_ids : Dictionary = {}

static func write_entity_scene_id(p_entity : entity_const, p_networked_scenes : Array, p_writer : network_writer_const) -> network_writer_const:
	var network_identity_node = p_entity.get_network_identity_node()
	if p_networked_scenes.size() > 0xff:
		p_writer.put_u16(network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffff:
		p_writer.put_u32(network_identity_node.network_scene_id)
	elif p_networked_scenes.size() > 0xffffffff:
		p_writer.put_u64(network_identity_node.network_scene_id)
	else:
		p_writer.put_u8(network_identity_node.network_scene_id)
		
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
		
static func write_entity_network_master(p_entity : entity_const, p_writer : network_writer_const) -> network_writer_const:
	p_writer.put_u32(p_entity.get_network_master())
		
	return p_writer
	
static func read_entity_network_master(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()

static func write_entity_instance_id(p_entity : entity_const, p_writer : network_writer_const) -> network_writer_const:
	p_writer.put_u32(p_entity.get_network_identity_node().network_instance_id)
		
	return p_writer
	
static func read_entity_instance_id(p_reader : network_reader_const) -> int:
	return p_reader.get_u32()

func reset_server_instances() -> void:
	network_instance_ids = {}
	next_network_instance_id = FIRST_NETWORK_INSTANCE_ID # Reset the network id counter

func get_next_network_id() -> int:
	var network_instance_id : int = next_network_instance_id
	next_network_instance_id += 1
	if next_network_instance_id >= LAST_NETWORK_INSTANCE_ID:
		print("Maximum network instance ids used. Reverting to first")
		next_network_instance_id = FIRST_NETWORK_INSTANCE_ID
		
	# If the instance id is already in use, keep iterating until
	# we find an unused one
	while(network_instance_ids.has(network_instance_id)):
		network_instance_id = next_network_instance_id
		next_network_instance_id += 1
		if next_network_instance_id >= LAST_NETWORK_INSTANCE_ID:
			print("Maximum network instance ids used. Reverting to first")
			next_network_instance_id = FIRST_NETWORK_INSTANCE_ID
	
	return network_instance_id

func register_network_instance_id(p_network_instance_id : int, p_node : Node) -> void:
	if network_instance_ids.size() > max_networked_entities:
		printerr("EXCEEDED MAXIMUM ALLOWED INSTANCE IDS!")
		return
	
	network_instance_ids[p_network_instance_id] = p_node
	
func unregister_network_instance_id(p_network_instance_id : int) -> void:
	if network_instance_ids.erase(p_network_instance_id) == false:
		ErrorManager.error("Could not unregister network instance id: {network_instance_id}".format({"network_instance_id":str(p_network_instance_id)}))
	
func get_network_instance_identity(p_network_instance_id : int) -> Node:
	if network_instance_ids.has(p_network_instance_id):
		return network_instance_ids[p_network_instance_id]
	
	return null
	
# TODO: thread this
func cache_networked_scenes() -> void:
	for i in range(0, networked_scenes.size()):
		var packed_scene : PackedScene = null
		
		if ResourceLoader.exists(networked_scenes[i]):
			packed_scene = ResourceLoader.load(networked_scenes[i])
	
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
	
	if Engine.is_editor_hint() == false:
		var network_scenes_config = ProjectSettings.get_setting("network/config/networked_scenes")
		if typeof(network_scenes_config) != TYPE_STRING_ARRAY:
			networked_scenes = Array()
		else:
			networked_scenes = Array(network_scenes_config)
			
		max_networked_entities = ProjectSettings.get_setting("network/config/max_networked_entities")
	
	if(!ProjectSettings.has_setting("network/config/max_networked_entities")):
		ProjectSettings.set_setting("network/config/max_networked_entities", max_networked_entities)
