extends Reference
tool

const runtime_entity_const = preload("res://addons/entity_manager/runtime_entity.gd")

const mutex_lock_const = preload("res://addons/gdutil/mutex_lock.gd")

#
enum {
	ADD_ENTITY = 0,
	REMOVE_ENTITY
}
var scene_tree_execution_table : Array = []
var _scene_tree_table_mutex : Mutex = Mutex.new()

# Adds an entity to the tree. Called exclusively in the main thread
func _add_entity_instance_unsafe(p_instance : Node, p_parent : Node = null) -> void:
	if p_parent:
		NetworkLogger.printl("Adding entity: %s" % p_instance.get_name())
		if p_instance.is_inside_tree():
			NetworkLogger.error("Entity is already inside tree!")
		else:
			p_parent.add_child(p_instance)
			p_parent.set_script(runtime_entity_const)

# Deletes an entity to the tree. Called exclusively in the main thread
func _remove_entity_instance_unsafe(p_instance : Node) -> void:
	NetworkLogger.printl("Removing entity: %s" % p_instance.get_name())
	if p_instance.is_inside_tree():
		p_instance.queue_free()
		p_instance.get_parent().remove_child(p_instance)
	else:
		NetworkLogger.fatal_error("Entity is not inside tree!")

func copy_and_clear_scene_tree_execution_table() -> Array:
	var mutex_lock : mutex_lock_const = mutex_lock_const.new(_scene_tree_table_mutex)
	var table : Array = []
	if scene_tree_execution_table.size():
		table = scene_tree_execution_table.duplicate()
		
	scene_tree_execution_table = []
	
	return table

# Executes all the add/delete commands. Called exclusively in the main thread
func _execute_scene_tree_execution_table_unsafe():
	var table : Array = copy_and_clear_scene_tree_execution_table()
	for entry in table:
		match entry.command:
			ADD_ENTITY:
				_add_entity_instance_unsafe(entry.instance, entry.parent)
			REMOVE_ENTITY:
				_remove_entity_instance_unsafe(entry.instance)
	
# Clears the scene tree execution table. Add entities marked
# scheduled to be added will be queued to be freed
func cancel_scene_tree_execution_table():
	var mutex_lock : mutex_lock_const = mutex_lock_const.new(_scene_tree_table_mutex)
	
	for entry in scene_tree_execution_table:
		match entry.command:
			ADD_ENTITY:
				entry.instance.queue_free()
		
	scene_tree_execution_table = []
	
# Adds a command to add or remove an entity from the scene.
# The commands will later be executed on the scene tree
func scene_tree_execution_command(p_command : int, p_entity_instance : Node, p_parent_instance : Node):
	var mutex_lock : mutex_lock_const = mutex_lock_const.new(_scene_tree_table_mutex)
	
	match p_command:
		ADD_ENTITY:
			NetworkLogger.printl("Scene Tree: Add Entity Command...%s" % p_entity_instance.get_name())
			scene_tree_execution_table.push_front({"command":ADD_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
		REMOVE_ENTITY:
			NetworkLogger.printl("Scene Tree: Remove Entity Command...%s" % p_entity_instance.get_name())
			scene_tree_execution_table.push_front({"command":REMOVE_ENTITY, "instance":p_entity_instance, "parent":p_parent_instance})
