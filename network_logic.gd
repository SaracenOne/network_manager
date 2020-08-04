extends "res://addons/entity_manager/component_node.gd"
class_name NetworkLogic

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

# The NetworkLogic node can optionally store a network writer of a fixed
# size to save on memory reallocation
var cached_writer: network_writer_const = network_writer_const.new()
# The size of the cached writer
export (int) var cached_writer_size = 0

# Flag to indicate whether data has been loaded for this node
var received_data: bool = false

# Indicating whether reserialise entity data or use the results
# from the last serialisation
var dirty_flag: bool = true


# Sets the dirty flag
func set_dirty(p_dirty: bool) -> void:
	dirty_flag = p_dirty


# Returns the state of the dirty flag
func is_dirty() -> bool:
	return dirty_flag


# Called when requesting entity state data be serialised. 
# The p_writer is the network writer the data will be written
# to. If null, data will be written to the cached writer.
# The initial state flag indicates whether to request
# extra data primarily relevant to the first time the entity
# has spawned and is unlikely to change during its lifespan.
# Returns the network writer the data was written to.
func on_serialize(p_writer: network_writer_const, p_initial_state: bool) -> network_writer_const:
	if p_initial_state:
		set_dirty(true)

	var writer: network_writer_const = p_writer
	if writer == null:
		writer = cached_writer
		if is_dirty():
			cached_writer.seek(0)
		else:
			return cached_writer

	for child in get_children():
		writer = child.on_serialize(writer, p_initial_state)

	if ! p_initial_state:
		set_dirty(false)

	return writer


# Called when the receiving a network packet containing entity state data.
# The initial state flag indicates whether this reader is going to contain
# data primarily relevant to the first time the entity has spawned and is
# unlikely to change during its lifespan. Returns the network reader.
func on_deserialize(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	if p_reader == null:
		return p_reader

	for child in get_children():
		p_reader = child.on_deserialize(p_reader, p_initial_state)

	return p_reader


func _threaded_instance_setup(p_instance_id: int, p_network_reader: Reference) -> void:
	._threaded_instance_setup(p_instance_id, p_network_reader)

	for child in get_children():
		child._threaded_instance_setup(p_instance_id, p_network_reader)


func _network_process(_delta: float) -> void:
	for child in get_children():
		child._network_process(_delta)


func _process(_delta: float) -> void:
	if ! Engine.is_editor_hint():
		_network_process(_delta)


func _ready() -> void:
	cached_writer.resize(cached_writer_size)
