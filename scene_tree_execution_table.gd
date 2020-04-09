extends Reference
tool

const runtime_entity_const = preload("res://addons/entity_manager/runtime_entity.gd")

#
enum {
	ADD_ENTITY = 0,
	REMOVE_ENTITY
}
var scene_tree_execution_table : Array = []

# Adds an entity to the tree. Called exclusively in the main thread
func _add_entity_instance_unsafe(p_instance : Node, p_parent : Node = null) -> void:
	if p_parent:
		print("Adding entity: " + p_instance.get_name())
		p_parent.add_child(p_instance)
		p_parent.set_script(runtime_entity_const)

# Deletes an entity to the tree. Called exclusively in the main thread
func _remove_entity_instance_unsafe(p_instance : Node) -> void:
	print("Removing entity: " + p_instance.get_name())
	p_instance.queue_free()
	p_instance.get_parent().remove_child(p_instance)

# Executes all the add/delete commands. Called exclusively in the main thread
func _execute_scene_tree_execution_table_unsafe():
	for entry in scene_tree_execution_table:
		match entry.command:
			ADD_ENTITY:
				_add_entity_instance_unsafe(entry.instance, entry.parent)
			REMOVE_ENTITY:
				_remove_entity_instance_unsafe(entry.instance)
				
	scene_tree_execution_table = []
	
# Clears the scene tree execution table. Add entities marked
# scheduled to be added will be queued to be freed
func cancel_scene_tree_execution_table():
	for entry in scene_tree_execution_table:
		match entry.command:
			ADD_ENTITY:
				entry.instance.queue_free()
		
	scene_tree_execution_table = []
	
# Adds a command to add or remove an entity from the scene.
# The commands will later be executed on the scene tree
func scene_tree_execution_command(p_command : int, p_entity_instance : Node, p_parent_instance : Node):
	match p_command:
		ADD_ENTITY:
			scene_tree_execution_table.push_front({"command":ADD_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
		REMOVE_ENTITY:
			scene_tree_execution_table.push_front({"command":REMOVE_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
