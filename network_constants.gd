extends Node

# A list of all the network commands which can be sent or received.
enum {
	UPDATE_ENTITY_COMMAND = 0,
	SPAWN_ENTITY_COMMAND,
	DESTROY_ENTITY_COMMAND,
	REQUEST_ENTITY_MASTER_COMMAND,
	TRANSFER_ENTITY_MASTER_COMMAND,
	VOICE_COMMAND
}

# Returns a string name for a corresponding network command
static func get_string_for_command(p_id : int) -> String:
	var command_string_table : Dictionary = {
		UPDATE_ENTITY_COMMAND:"UpdateEntityCommand",
		SPAWN_ENTITY_COMMAND:"SpawnEntityCommand",
		DESTROY_ENTITY_COMMAND:"DestroyEntityCommand",
		REQUEST_ENTITY_MASTER_COMMAND:"RequestEntityMasterCommand",
		TRANSFER_ENTITY_MASTER_COMMAND:"TransferEntityMasterCommand",
		VOICE_COMMAND:"VoiceCommand"
	}
	
	if command_string_table.has(p_id):
		return command_string_table[p_id]
			
	return ""
