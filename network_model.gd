extends NetworkLogic
class_name NetworkModel

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if p_initial_state:
		var name : String = entity_node.get_simulation_logic_node().get_model_path()
		p_writer.put_8bit_pascal_string(name, true)
	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	received_data = true
	
	if p_initial_state:
		var name : String = p_reader.get_8bit_pascal_string(true)
		entity_node.get_simulation_logic_node().load_model(name)
	
	return p_reader
	
func _process(p_delta : float) -> void:
	pass

func _ready():
	if Engine.is_editor_hint() == false:
		if received_data:
			pass
