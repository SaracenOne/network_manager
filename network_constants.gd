extends Node

const AUTHORITATIVE_SERVER_NAME = "authoritative"
const RELAY_SERVER_NAME = "relay"

const DEFAULT_PORT = 7777
const LOCALHOST_IP = "127.0.0.1"

const ALL_PEERS: int = 0
const SERVER_MASTER_PEER_ID: int = 1
const PEER_PENDING_TIMEOUT: int = 20

enum validation_state_enum {
	VALIDATION_STATE_NONE = 0,
	VALIDATION_STATE_CONNECTION,
	VALIDATION_STATE_PEERS_SENT,
	VALIDATION_STATE_INFO_SENT,
	VALIDATION_STATE_STATE_SENT,
	VALIDATION_STATE_SYNCED,
}

# A list of all the network commands which can be sent or received.
enum {
	UPDATE_ENTITY_COMMAND = 0,
	SPAWN_ENTITY_COMMAND,
	DESTROY_ENTITY_COMMAND,
	REQUEST_ENTITY_MASTER_COMMAND,
	TRANSFER_ENTITY_MASTER_COMMAND,
	ENTITY_RPC_COMMAND,
	ENTITY_RSET_COMMAND,
	VOICE_COMMAND,
	INFO_REQUEST_COMMAND,
	STATE_REQUEST_COMMAND,
	READY_COMMAND,
	DISCONNECT_COMMAND,
	MAP_CHANGING_COMMAND,
	SESSION_MASTER_COMMAND,
}

const COMMAND_STRING_TABLE: Dictionary = {
	UPDATE_ENTITY_COMMAND: "UpdateEntityCommand",
	SPAWN_ENTITY_COMMAND: "SpawnEntityCommand",
	DESTROY_ENTITY_COMMAND: "DestroyEntityCommand",
	REQUEST_ENTITY_MASTER_COMMAND: "RequestEntityMasterCommand",
	TRANSFER_ENTITY_MASTER_COMMAND: "TransferEntityMasterCommand",
	ENTITY_RPC_COMMAND: "EntityRPCCommand",
	ENTITY_RSET_COMMAND: "EntityRSetCommand",
	VOICE_COMMAND: "VoiceCommand",
	INFO_REQUEST_COMMAND: "InfoRequestCommand",
	STATE_REQUEST_COMMAND: "StateRequestCommand",
	READY_COMMAND: "ReadyCommand",
	MAP_CHANGING_COMMAND: "MapChangingCommand",
	SESSION_MASTER_COMMAND: "SessionMasterCommand"
}

# Returns a string name for a corresponding network command
static func get_string_for_command(p_id: int) -> String:
	if COMMAND_STRING_TABLE.has(p_id):
		return COMMAND_STRING_TABLE[p_id]

	return ""
