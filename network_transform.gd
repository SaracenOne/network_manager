extends "network_logic.gd"

static func write_transform(p_writer, p_transform):
	p_writer.put_vector3(p_transform.origin)
	p_writer.put_quat(Quat(p_transform.basis))
	
	return p_writer

func on_client_master_serialize(p_writer):
	var transform = entity_node.get_logic_node().get_global_transform()
	p_writer = write_transform(p_writer, transform)
		
	return p_writer
	
func on_client_master_deserialize(p_reader):
	var origin = Vector3(p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	var quat = Quat(p_reader.get_float(), p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
		
	return p_reader

func on_serialize(p_writer, p_initial_state):
	var transform = entity_node.get_logic_node().get_global_transform()
	p_writer = write_transform(p_writer, transform)
	
	return p_writer
	
func on_deserialize(p_reader, p_initial_state):
	var origin = Vector3(p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	var quat = Quat(p_reader.get_float(), p_reader.get_float(), p_reader.get_float(), p_reader.get_float())
	
	entity_node.get_logic_node().set_global_transform(Transform(Basis(quat), origin))
	
	return p_reader