extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")

const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")
const network_constants_const = preload("network_constants.gd")

var multiplayer_signal_table: Array = [
	{"signal": "network_peer_connected", "method": "_network_peer_connected"},
	{"signal": "network_peer_disconnected", "method": "_network_peer_disconnected"},
	{"signal": "connected_to_server", "method": "_connected_to_server"},
	{"signal": "connection_failed", "method": "_connection_failed"},
	{"signal": "server_disconnected", "method": "_server_disconnected"},
	{"signal": "network_peer_packet", "method": "_network_peer_packet"},
]

var network_process_timestep: float = 0.0
var network_process_frame_timeslice: float = 0.0

var network_fps: int = 60
var packets_received_this_frame: int = 0
var is_relay: bool = false

var kill_flag: bool = false
onready var gameroot = get_tree().get_root()

const network_replication_manager_const = preload("network_replication_manager.gd")
const network_state_manager_const = preload("network_state_manager.gd")
const network_voice_manager_const = preload("network_voice_manager.gd")
const network_entity_manager_const = preload("network_entity_manager.gd")
const network_flow_manager_const = preload("network_flow_manager.gd")
const network_handshake_manager_const = preload("network_handshake_manager.gd")

var server_state_ready: bool = false

var network_replication_manager: Node = null
var network_state_manager: Node = null
var network_voice_manager: Node = null
var network_entity_manager: Node = null
var network_flow_manager: Node = null
var network_handshake_manager: Node = null

var compression_mode: int = NetworkedMultiplayerENet.COMPRESS_NONE

var received_packet_buffer_count: Dictionary = {}

var entity_root_node_path: NodePath = NodePath()
var server_dedicated: bool = false
var max_players: int = -1

################
# Session Data #
################
# Server
var peer_data: Dictionary = {}

func received_peer_validation_state_update(p_peer_id: int, p_validation_state: int) -> void:
	peer_data[p_peer_id]["time_since_last_update_received"] = 0.0
	peer_data[p_peer_id]["validation_state"] = p_validation_state

# Shared
var default_port: int = network_constants_const.DEFAULT_PORT

var active_port: int = -1
var active_ip: String = ""

var client_state: int = network_constants_const.validation_state_enum.VALIDATION_STATE_NONE
var active_peers: Array = []  # Peers requesting state updates

const DUMMY_PEER_COUNT: int = 0

var session_master: int = -1
var session_master_reassigned: bool = false

var network_entity_command_writer_cache: network_writer_const = network_writer_const.new(1024)

signal network_process(p_delta)
signal network_flush
signal session_data_reset
signal game_hosted

signal peer_registered(p_id)
signal peer_unregistered(p_id)
signal peer_list_changed
signal peer_registration_complete

signal server_peer_connected(p_id)
signal server_peer_disconnected(p_id)

signal connection_failed
signal connection_succeeded
signal server_disconnected
signal network_peer_packet

signal connection_killed

signal server_state_ready

signal voice_packet_compressed(p_peer_id, p_sequence_id, p_buffer)

signal peer_became_active(p_network_id)


#Server
func server_peer_ready(p_network_id: int) -> void:
	attempt_to_reassign_session_master()


func _network_peer_connected(p_id: int) -> void:
	register_peer(p_id)

	NetworkLogger.printl("Network peer {id} connected!".format({"id": str(p_id)}))
	if ! is_relay():
		if client_state == network_constants_const.validation_state_enum.VALIDATION_STATE_SYNCED:
			network_handshake_manager.ready_command(p_id)
		if is_server():
			network_handshake_manager.current_master_id()
			emit_signal("server_peer_connected", p_id)


func _network_peer_disconnected(p_id: int) -> void:
	NetworkLogger.printl("Network peer {id} disconnected!".format({"id": str(p_id)}))
	if ! is_relay():
		if is_server():
			network_handshake_manager.disconnect_command(p_id)
			unregister_peer(p_id)
	else:
		NetworkLogger.error("Disconnected peer for relay mode not implemented!")


#Clients
func _connected_to_server() -> void:
	var network_connected_peers: PoolIntArray = get_tree().multiplayer.get_network_connected_peers()

	emit_signal("connection_succeeded")

	emit_signal("peer_registration_complete")


func _connection_failed() -> void:
	NetworkLogger.printl("Connection failed")
	emit_signal("connection_failed")


func _server_disconnected() -> void:
	NetworkLogger.printl("Server disconnected")
	emit_signal("server_disconnected")


func get_entity_root_node() -> Node:
	return gameroot


#Client/Server
func _network_peer_packet(p_id: int, p_packet: PoolByteArray) -> void:
	packets_received_this_frame += 1
	
	# Reset the timer for this peer
	peer_data[p_id]["time_since_last_update_received"] = 0.0
	
	emit_signal("network_peer_packet", p_id, p_packet)


func has_active_peer() -> bool:
	return (
		get_tree().multiplayer.has_network_peer()
		and (
			get_tree().multiplayer.network_peer.get_connection_status()
			!= NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED
		)
	)


func is_server() -> bool:
	return ! has_active_peer() or get_tree().multiplayer.is_network_server()


func is_session_master() -> bool:
	if ! is_relay():
		return is_server()
	else:
		return session_master == get_current_peer_id()


func request_network_kill() -> void:
	kill_flag = true
	force_close_connection()


# If this is true, the sessions allows packets to be sent directly to other
# peers and peers will be automatically notified when new peers have joined
func is_relay() -> bool:
	return is_relay


func set_relay(p_is_relay: bool) -> void:
	is_relay = p_is_relay


func is_rpc_sender_id_server() -> bool:
	return (
		get_tree().multiplayer.get_rpc_sender_id()
		== network_constants_const.SERVER_MASTER_PEER_ID
	)


# Returns the number of connected (not just active) peers
# The inclusive argument means the host should be included in this count
func get_peer_count(p_inclusive: bool) -> int:
	var peer_count: int = peer_data.size()
	if p_inclusive:
		if is_server():
			if ! server_dedicated:
				peer_count += 1
		else:
			peer_count += 1

	return peer_count


func host_game(p_port: int, p_max_players: int, p_dedicated: bool, p_relay: bool = true, p_retry_max: int = 0) -> bool:
	if has_active_peer():
		NetworkLogger.error("Network peer already established!")
		return false

	reset_session_data()

	server_dedicated = p_dedicated
	max_players = p_max_players

	active_port = p_port
	active_ip = network_constants_const.LOCALHOST_IP

	var net: NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	net.compression_mode = compression_mode
	net.server_relay = p_relay
	set_relay(p_relay)

	if net.server_relay:
		NetworkLogger.printl("Attempting to host relay server...")
	else:
		NetworkLogger.printl("Attempting to host authoritative server...")

	var retry_count : int = 0
	while net.create_server(active_port, max_players) != OK:
		if (retry_count % 10) == 0:
			NetworkLogger.printl(
				"Cannot create a server on port {port}! (Try {try}/{trymax})".format(
				{"port": str(active_port), "try": str(retry_count), "trymax": str(p_retry_max)})
			)
		retry_count += 1
		if retry_count > p_retry_max:
			return false
		OS.delay_msec(100)

	get_tree().multiplayer.set_network_peer(net)
	get_tree().multiplayer.set_allow_object_decoding(false)

	if server_dedicated:
		NetworkLogger.printl("Server hosted on port {port}".format({"port": str(active_port)}))
		NetworkLogger.printl("Max clients: {max_players}".format({"port": str(max_players)}))

	emit_signal("game_hosted")

	return true


func join_game(p_ip: String, p_port: int) -> bool:
	if has_active_peer():
		NetworkLogger.error("Network peer already established!")
		return false

	reset_session_data()

	var net: NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	net.compression_mode = compression_mode

	if ! p_ip.is_valid_ip_address():
		NetworkLogger.printl("Invalid ip address!")
		return false

	if net.create_client(p_ip, p_port) != OK:
		NetworkLogger.printl(
			"Cannot create a client on ip {ip} & port {port}!".format(
				{"ip": p_ip, "port": str(p_port)}
			)
		)
		return false

	active_ip = p_ip
	active_port = p_port

	get_tree().multiplayer.set_network_peer(net)
	get_tree().multiplayer.set_allow_object_decoding(false)

	NetworkLogger.printl("Connecting to {ip} : {port}!".format({"ip": p_ip, "port": str(p_port)}))

	return true


func reset_session_data() -> void:
	NetworkLogger.printl("Resetting session data")

	server_state_ready = false
	peer_data = {}
	active_port = -1
	client_state = network_constants_const.validation_state_enum.VALIDATION_STATE_NONE
	var peers: PoolIntArray = get_connected_peers()
	for peer_id in peers:
		emit_signal("peer_unregistered", peer_id)
	active_peers = []
	session_master = -1

	network_flow_manager.reset()

	emit_signal("session_data_reset")


func force_close_connection() -> void:
	if has_active_peer():
		NetworkLogger.printl("Closing connection...")
		if get_tree().multiplayer.has_network_peer():
			get_tree().multiplayer.set_network_peer(null)

	emit_signal("network_flush")
	reset_session_data()
	emit_signal("connection_killed")


func attempt_to_reassign_session_master() -> void:
	if is_server():
		if is_relay():
			var peers: PoolIntArray = get_connected_peers()
			if session_master == network_constants_const.SERVER_MASTER_PEER_ID:
				if peers.size() > 0:
					session_master = peers[0]
					session_master_reassigned = true
			else:
				var session_master_valid: bool = false
				for i in range(0, peers.size()):
					if session_master == peers[i]:
						session_master_valid = true
						break

				if ! session_master_valid:
					if peers.size() > 0:
						session_master = peers[0]
					else:
						session_master = network_constants_const.SERVER_MASTER_PEER_ID

					session_master_reassigned = true


func get_current_peer_id() -> int:
	if has_active_peer():
		var id: int = get_tree().multiplayer.get_network_unique_id()
		return id
	else:
		return network_constants_const.SERVER_MASTER_PEER_ID


# Test to see if the peer with this id is connected
func peer_is_connected(p_id: int) -> bool:
	var connected_peers: PoolIntArray = get_connected_peers()
	for i in range(0, connected_peers.size()):
		if connected_peers[i] == p_id:
			return true

	return false


func get_connected_peers() -> PoolIntArray:
	if has_active_peer():
		var connected_peers: PoolIntArray = get_tree().multiplayer.get_network_connected_peers()
		return connected_peers
	else:
		return PoolIntArray()


func copy_active_peers() -> Array:
	return active_peers.duplicate()


##########################
# Network state transfer #
##########################

signal create_server_info
signal create_server_state

signal requesting_server_info
signal requesting_server_state

signal peer_validation_state_error_callback

signal requested_server_info(p_id, p_client_message)
signal received_server_info(p_info)
signal requested_server_state(p_id)
signal received_server_state(p_state)

signal received_client_info(p_id, p_info)

master func create_server_info() -> void:
	NetworkLogger.printl("create_server_info...")
	emit_signal("create_server_info")

master func create_server_state() -> void:
	NetworkLogger.printl("create_server_state...")
	emit_signal("create_server_state")

remote func peer_validation_state_error_callback() -> void:
	NetworkLogger.printl("peer_validation_state_error_callback...")
	if is_server():
		rpc("peer_validation_state_error_callback")
	else:
		# Return if the rpc sender was not the server
		if not is_rpc_sender_id_server():
			return

	emit_signal("peer_validation_state_error_callback")


func confirm_client_ready_for_sync(p_network_id: int) -> void:
	NetworkLogger.printl("confirm_client_ready_for_sync...")
	if (
		peer_data[p_network_id].validation_state
		!= network_constants_const.validation_state_enum.VALIDATION_STATE_STATE_SENT
	):
		peer_validation_state_error_callback()
	else:
		received_peer_validation_state_update(p_network_id,\
		network_constants_const.validation_state_enum.VALIDATION_STATE_SYNCED)

		active_peers.push_back(p_network_id)
		
	emit_signal("peer_became_active", p_network_id)


func confirm_server_ready_for_sync() -> void:
	NetworkLogger.printl("confirm_server_ready_for_sync...")
	client_state = network_constants_const.validation_state_enum.VALIDATION_STATE_SYNCED


func server_kick_player(p_id: int) -> void:
	NetworkLogger.printl("server_kick_player...")
	if is_server():
		var net: NetworkedMultiplayerPeer = get_tree().multiplayer.get_network_peer()
		if net and net is NetworkedMultiplayerENet:
			net.disconnect_peer(p_id)

			# TODO register disconnection


func decode_buffer(p_id: int, p_buffer: PoolByteArray) -> void:
	if OS.is_stdout_verbose():
		ErrorManager.printl("--- Packet received from {id} ---".format({"id": p_id}))

	var network_reader: network_reader_const = network_reader_const.new(p_buffer)

	while network_reader:
		var command = network_reader.get_u8()
		if network_reader.is_eof():
			break

		var start_position: int = network_reader.get_position()

		if network_replication_manager.is_command_valid(command):
			network_reader = network_replication_manager.decode_replication_buffer(
				p_id, network_reader, command
			)
		elif network_state_manager.is_command_valid(command):
			network_reader = network_state_manager.decode_state_buffer(
				p_id, network_reader, command
			)
		elif network_voice_manager.is_command_valid(command):
			network_reader = network_voice_manager.decode_voice_buffer(
				p_id, network_reader, command
			)
		elif network_handshake_manager.is_command_valid(command):
			network_reader = network_handshake_manager.decode_handshake_buffer(
				p_id, network_reader, command
			)
		else:
			ErrorManager.error("Invalid command: {command}".format({"command": str(command)}))

		if OS.is_stdout_verbose():
			if network_reader:
				var end_position: int = network_reader.get_position()
				var command_string: String = network_constants_const.get_string_for_command(command)
				var command_size: int = end_position - start_position

				ErrorManager.printl(
					"Processed {command_string}: {command_size} bytes".format(
						{"command_string": command_string, "command_size": str(command_size)}
					)
				)
			else:
				NetworkLogger.printl("Processed NULL")

	network_entity_manager.scene_tree_execution_table.call_deferred(
		"_execute_scene_tree_execution_table_unsafe"
	)

	if ! received_packet_buffer_count.has(p_id):
		received_packet_buffer_count[p_id] = 0

	if OS.is_stdout_verbose():
		var size: int = network_reader.get_position()
		ErrorManager.printl(
			"--- Finished processing packet {count} from peer {id}, packet size: {size} ---".format(
				{"count": received_packet_buffer_count[p_id], "id": p_id, "size": size}
			)
		)

	received_packet_buffer_count[p_id] += 1


func _process(p_delta: float) -> void:
	if ! Engine.is_editor_hint():
		packets_received_this_frame = 0
		network_process_timestep += p_delta
		
		if network_process_timestep > network_process_frame_timeslice:
			while network_process_timestep > network_process_frame_timeslice:
				network_process_timestep -= network_process_frame_timeslice
			
			if has_active_peer():
				if is_server():
					var peers: PoolIntArray = get_connected_peers()
					for peer in peers:
						peer_data[peer]["time_since_last_update_received"] += p_delta
				
				if (
					is_server()
					or (
						client_state
						== network_constants_const.validation_state_enum.VALIDATION_STATE_SYNCED
					)
				):
					emit_signal(
						"network_process", get_tree().multiplayer.get_network_unique_id(), p_delta
					)
					
				network_flow_manager.process_network_packets(p_delta)


func copy_valid_send_peers(p_id: int, p_include_dummy_peers: bool = false) -> Array:
	var synced_peers: Array = []
	if p_id == session_master or p_id == network_constants_const.SERVER_MASTER_PEER_ID:
		synced_peers = copy_active_peers()
	else:
		if is_relay():
			synced_peers = [network_constants_const.ALL_PEERS]
		else:
			synced_peers = [network_constants_const.SERVER_MASTER_PEER_ID]

	# For debugging purposes
	if ! is_relay():
		if p_include_dummy_peers:
			for i in range(0, DUMMY_PEER_COUNT):
				synced_peers.push_back(-1)

	return synced_peers


func get_default_server_info() -> Dictionary:
	var server_type: String
	if is_relay():
		server_type = network_constants_const.RELAY_SERVER_NAME
	else:
		server_type = network_constants_const.AUTHORITATIVE_SERVER_NAME

	return {
		"server_type": server_type,
	}


func get_network_scene_paths() -> Array:
	return network_entity_manager.get_network_scene_paths()


func client_request_server_info(p_client_info: Dictionary) -> void:
	emit_signal("requesting_server_info")
	network_handshake_manager.rpc_id(
		NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID,
		"requested_server_info",
		p_client_info
	)


func client_request_server_state(p_client_state: Dictionary) -> void:
	emit_signal("requesting_server_state")
	network_handshake_manager.rpc_id(
		NetworkManager.network_constants_const.SERVER_MASTER_PEER_ID, "requested_server_state", {}
	)


func server_send_server_info(p_network_id: int, p_server_info: Dictionary) -> void:
	network_handshake_manager.rpc_id(p_network_id, "received_server_info", p_server_info)


func server_send_server_state(p_network_id: int, p_server_state: Dictionary) -> void:
	network_handshake_manager.rpc_id(p_network_id, "received_server_state", p_server_state)

func server_send_client_info(p_network_id: int, p_client_id: int, p_client_info: Dictionary) -> void:
	network_handshake_manager.rpc_id(p_network_id, "received_client_info", p_client_id, p_client_info)

func register_peer(p_id) -> void:
	peer_data[p_id] = {
		"validation_state": network_constants_const.validation_state_enum.VALIDATION_STATE_NONE,
		"time_since_last_update_received": 0.0,
		"time_since_last_update_sent": 0.0
	}

	NetworkLogger.printl("peer_registered:{id}".format({"id": str(p_id)}))
	emit_signal("peer_registered", p_id)
	emit_signal("peer_list_changed")


func unregister_peer(p_id) -> void:
	if active_peers.has(p_id):
		active_peers.erase(p_id)
	
	peer_data.erase(p_id)
	NetworkLogger.printl("peer_unregistered:{id}".format({"id": str(p_id)}))
	emit_signal("peer_unregistered", p_id)
	emit_signal("peer_list_changed")

func setup_project_settings() -> void:
	var should_save: bool = false
	
	if ProjectSettings.has_setting("network/config/network_fps"):
		network_fps = ProjectSettings.get_setting("network/config/network_fps")
	else:
		ProjectSettings.set_setting("network/config/network_fps", network_fps)
		should_save = true
	
	if ProjectSettings.has_setting("network/config/entity_root_node"):
		entity_root_node_path = NodePath(
			ProjectSettings.get_setting("network/config/entity_root_node")
		)
	else:
		ProjectSettings.set_setting("network/config/entity_root_node", entity_root_node_path)
		should_save = true

	if ! ProjectSettings.has_setting("network/config/compression_mode"):
		ProjectSettings.set_setting("network/config/compression_mode", compression_mode)
		
		var compression_mode_property_info: Dictionary = {
			"name": "network/config/compression_mode",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "None,Range Coder,FastLZ,zlib,Zstandard"
		}
	
		ProjectSettings.add_property_info(compression_mode_property_info)
	else:
		compression_mode = ProjectSettings.get_setting("network/config/compression_mode")
		should_save = true
		
	if ! ProjectSettings.has_setting("network/config/default_port"):
		ProjectSettings.set_setting("network/config/default_port", default_port)
	else:
		default_port = ProjectSettings.get_setting("network/config/default_port")
		should_save = true
	
	if Engine.is_editor_hint() and should_save:
		ProjectSettings.save()
		
func confirm_server_state_ready() -> void:
	server_state_ready = true
	emit_signal("server_state_ready")

########
# Node #
########

func _ready() -> void:
	setup_project_settings()

	if ! Engine.is_editor_hint():
		network_process_frame_timeslice = 1.0 / network_fps
		for current_signal in multiplayer_signal_table:
			if (
				get_tree().multiplayer.connect(current_signal.signal, self, current_signal.method)
				!= OK
			):
				NetworkLogger.error(
					"NetworkManager: {signal} could not be connected!".format(
						{"signal": str(current_signal.signal)}
					)
				)


func _enter_tree() -> void:
	#Add sub managers to the tree
	add_child(network_replication_manager)
	add_child(network_state_manager)
	add_child(network_voice_manager)
	add_child(network_entity_manager)
	add_child(network_flow_manager)
	add_child(network_handshake_manager)


func _init() -> void:
	network_replication_manager = Node.new()
	network_replication_manager.set_script(network_replication_manager_const)
	network_replication_manager.set_name("NetworkReplicationManager")

	network_state_manager = Node.new()
	network_state_manager.set_script(network_state_manager_const)
	network_state_manager.set_name("NetworkStateManager")

	network_voice_manager = Node.new()
	network_voice_manager.set_script(network_voice_manager_const)
	network_voice_manager.set_name("NetworkVoiceManager")

	network_entity_manager = Node.new()
	network_entity_manager.set_script(network_entity_manager_const)
	network_entity_manager.set_name("NetworkEntityManager")

	network_flow_manager = Node.new()
	network_flow_manager.set_script(network_flow_manager_const)
	network_flow_manager.set_name("NetworkFlowManager")

	network_handshake_manager = Node.new()
	network_handshake_manager.set_script(network_handshake_manager_const)
	network_handshake_manager.set_name("NetworkHandshakeManager")
