extends "network_logic.gd"

const network_reader_const = preload("res://addons/network_manager/network_reader.gd")
const network_writer_const = preload("res://addons/network_manager/network_writer.gd")

static func write_transform(p_writer : network_writer_const, p_transform : Transform) -> network_writer_const:
	p_writer.put_vector3(p_transform.origin)
	p_writer.put_quat(Quat(p_transform.basis))
	
	return p_writer

func on_client_master_serialize(p_writer : network_writer_const) -> network_writer_const:
	var transform = _entity_node.get_logic_node().get_transform()
	p_writer = write_transform(p_writer, transform)
		
	return p_writer
	
func on_client_master_deserialize(p_reader : network_reader_const) -> network_reader_const:
	var origin = Vector3(p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	var quat = Quat(p_reader.get_float(), p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
		
	return p_reader

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	if _entity_node.get_logic_node() == null:
		_entity_node._ready()
		
	var transform = _entity_node.get_logic_node().get_transform()
	p_writer = write_transform(p_writer, transform)
	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	var origin = Vector3(p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	var quat = Quat(p_reader.get_float(), p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	
	_entity_node.get_logic_node().set_transform(Transform(Basis(quat), origin))
	
	return p_reader