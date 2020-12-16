extends NetworkLogic
tool

func on_serialize(p_writer: network_writer_const, p_initial_state: bool) -> network_writer_const:
	if p_initial_state:
		var path: String = entity_node.simulation_logic_node.get_model_path()
		p_writer.put_8bit_pascal_string(path, true)

	return p_writer


func on_deserialize(p_reader: network_reader_const, p_initial_state: bool) -> network_reader_const:
	received_data = true

	if p_initial_state:
		var path: String = p_reader.get_8bit_pascal_string(true)
		entity_node.simulation_logic_node.set_model_from_path(path)

	return p_reader


func _entity_ready() -> void:
	._entity_ready()
	if ! Engine.is_editor_hint():
		if received_data:
			pass
