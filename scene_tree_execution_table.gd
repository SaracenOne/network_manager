extends Reference
tool

#
enum {
	ADD_ENTITY = 0,
	REMOVE_ENTITY
	REPARENT_ENTITY
}
var scene_tree_execution_table : Array = []

func _add_entity_instance_unsafe(p_instance : Node, p_parent : Node = null) -> void:
	if p_parent:
		print("Adding entity: " + p_instance.get_name())
		p_parent.add_child(p_instance)
		
func _remove_entity_instance_unsafe(p_instance : Node) -> void:
	print("Removing entity: " + p_instance.get_name())
	p_instance.queue_free()
	p_instance.get_parent().remove_child(p_instance)
	
func _reparent_entity_instance_unsafe(p_instance : Node, p_parent : Node = null) -> void:
	print("Reparenting entity: " + p_instance.get_name())
	if !p_instance.is_inside_tree():
		ErrorManager.error("reparent_entity_instance: entity not inside tree!")
		
	var last_global_transform : Transform = Transform()
	if p_instance.logic_node:
		last_global_transform = p_instance.logic_node.get_global_transform()
		
	p_instance.get_parent().remove_child(p_instance)
	
	if p_parent:
		p_parent.add_child(p_instance)
		
	if p_instance.logic_node:
		p_instance.logic_node.set_global_transform(last_global_transform)

func _execute_scene_tree_execution_table_unsafe():
	for entry in scene_tree_execution_table:
		match entry.command:
			ADD_ENTITY:
				_add_entity_instance_unsafe(entry.instance, entry.parent)
			REMOVE_ENTITY:
				_remove_entity_instance_unsafe(entry.instance)
			REPARENT_ENTITY:
				_reparent_entity_instance_unsafe(entry.instance)
				
	scene_tree_execution_table = []
	
func cancel_scene_tree_execution_table():
	for entry in scene_tree_execution_table:
		match entry.command:
			ADD_ENTITY:
				entry.instance.queue_free()
		
	scene_tree_execution_table = []
	
func scene_tree_execution_command(p_command : int, p_entity_instance : Node, p_parent_instance : Node):
	match p_command:
		ADD_ENTITY:
			scene_tree_execution_table.push_front({"command":ADD_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
		REMOVE_ENTITY:
			scene_tree_execution_table.push_front({"command":REMOVE_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
		REPARENT_ENTITY:
			scene_tree_execution_table.push_front({"command":REPARENT_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
