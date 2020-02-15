extends "res://addons/entity_manager/component_node.gd"
class_name NetworkLogic

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

var cached_writer : network_writer_const = network_writer_const.new()
export(int) var cached_writer_size = 0

var received_data : bool = false
var dirty_flag : bool = true

func set_dirty(p_dirty : bool) -> void:
	dirty_flag = p_dirty
	
func is_dirty() -> bool:
	return dirty_flag

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if p_initial_state:
		set_dirty(true)
	
	var writer : network_writer_const = p_writer
	if writer == null:
		writer = cached_writer
		if is_dirty():
			cached_writer.seek(0)
		else:
			return cached_writer
	
	for child in get_children():
		writer = child.on_serialize(writer, p_initial_state)
		
	if p_initial_state == false:
		set_dirty(false)
		
	return writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	if p_reader == null:
		return p_reader
	
	for child in get_children():
		p_reader = child.on_deserialize(p_reader, p_initial_state)
		
	return p_reader

func destroy_entity() -> void:
	var entity_node : Node = get_entity_node()
	if entity_node == null:
		printerr("Entity node could not be found")
		
	entity_node.queue_free()
	entity_node.get_parent().remove_child(entity_node)

func cache_nodes() -> void:
	.cache_nodes()

func _threaded_instance_setup(p_instance_id : int, p_network_reader : Reference) -> void:
	cache_nodes()
	
	for child in get_children():
		child._threaded_instance_setup(p_instance_id, p_network_reader)

func _ready() -> void:
	cached_writer.resize(cached_writer_size)
