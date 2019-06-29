extends "network_logic.gd"

static func write_transform(p_writer : network_writer_const, p_transform : Transform) -> network_writer_const:
	p_writer.put_vector3(p_transform.origin)
	p_writer.put_quat(Quat(p_transform.basis))
	
	return p_writer

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if _entity_node.get_logic_node() == null:
		_entity_node._ready()
		
	if p_initial_state:
		pass
		
	var transform = _entity_node.get_logic_node().get_transform()
	p_writer = write_transform(p_writer, transform)
	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	var origin = Vector3(p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	var quat = Quat(p_reader.get_float(), p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	
	if p_initial_state:
		pass
	
	if is_network_master() == false:
		_entity_node.get_logic_node().set_transform(Transform(Basis(quat), origin))
	
	return p_reader
