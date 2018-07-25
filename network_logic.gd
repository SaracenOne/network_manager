extends "res://addons/entity_manager/component_node.gd"

func on_serialize(p_writer, p_initial_state):
	if p_writer == null:
		return p_writer
	
	for child in get_children():
		p_writer = child.on_serialize(p_writer, p_initial_state)
		
	return p_writer
	
func on_deserialize(p_reader, p_initial_state):
	if p_reader == null:
		return p_reader
	
	for child in get_children():
		p_reader = child.on_deserialize(p_reader, p_initial_state)
		
	return p_reader
	
func on_client_master_serialize(p_writer):
	if p_writer == null:
		return p_writer
	
	for child in get_children():
		p_writer = child.on_client_master_serialize(p_writer)
		
	return p_writer
	
func on_client_master_deserialize(p_reader):
	if p_reader == null:
		return p_reader
	
	for child in get_children():
		p_reader = child.on_client_master_deserialize(p_reader)
		
	return p_reader

func destroy_entity():
	if entity_node == null:
		printerr("Entity node could not be found")
		
	entity_node.queue_free()
	entity_node.get_parent().remove_child(entity_node)