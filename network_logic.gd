extends "res://addons/entity_manager/component_node.gd"

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if p_writer == null:
		return p_writer
	
	for child in get_children():
		p_writer = child.on_serialize(p_writer, p_initial_state)
		
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	if p_reader == null:
		return p_reader
	
	for child in get_children():
		p_reader = child.on_deserialize(p_reader, p_initial_state)
		
	return p_reader

func destroy_entity() -> void:
	if _entity_node == null:
		printerr("Entity node could not be found")
		
	_entity_node.queue_free()
	_entity_node.get_parent().remove_child(_entity_node)