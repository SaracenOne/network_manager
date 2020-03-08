extends NetworkLogic
class_name NetworkPhysics

const network_entity_manager_const = preload("res://addons/network_manager/network_entity_manager.gd")

signal mass_changed(p_mass)

func on_serialize(p_writer : network_writer_const, p_initial_state : bool) -> network_writer_const:
	var physics_node_root = entity_node.get_simulation_logic_node().physics_node_root
	
	if p_initial_state:
		p_writer.put_float(physics_node_root.mass)
	
	var sleeping : bool = physics_node_root.sleeping or physics_node_root.mode != RigidBody.MODE_RIGID
	p_writer.put_8(sleeping)
	if sleeping == false:
		var linear_velocity : Vector3 = physics_node_root.linear_velocity
		var angular_velocity : Vector3 = physics_node_root.angular_velocity
		p_writer.put_vector3(linear_velocity)
		p_writer.put_vector3(angular_velocity)
	
	return p_writer
	
func on_deserialize(p_reader : network_reader_const, p_initial_state : bool) -> network_reader_const:
	received_data = true
	
	var physics_node_root = entity_node.get_simulation_logic_node().physics_node_root
	
	if p_initial_state:
		physics_node_root.mass = p_reader.get_float()
	
	var sleeping : bool = p_reader.get_8()
	physics_node_root.sleeping = sleeping
	
	var linear_velocity : Vector3 = Vector3()
	var angular_velocity : Vector3 = Vector3()
	if sleeping == false:
		linear_velocity = math_funcs_const.sanitise_vec3(p_reader.get_vector3())
		angular_velocity = math_funcs_const.sanitise_vec3(p_reader.get_vector3())
	
	physics_node_root.linear_velocity = linear_velocity
	physics_node_root.angular_velocity = angular_velocity
	
	return p_reader

func _network_process(_delta: float) -> void:
	._network_process(_delta)

func _ready():
	if Engine.is_editor_hint() == false:
		if received_data:
			pass
