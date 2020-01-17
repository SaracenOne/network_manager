extends Node
tool

const entity_const = preload("res://addons/entity_manager/entity.gd")

const network_writer_const = preload("network_writer.gd")
const network_reader_const = preload("network_reader.gd")
const network_constants_const = preload("network_constants.gd")

const SERVER_MASTER_PEER_ID : int = 1
const PEER_PENDING_TIMEOUT : int = 20

var multiplayer_signal_table : Array = [
	{"signal":"network_peer_connected", "method":"_network_peer_connected"},
	{"signal":"network_peer_disconnected", "method":"_network_peer_disconnected"},
	{"signal":"connected_to_server", "method":"_connected_to_server"},
	{"signal":"connection_failed", "method":"_connection_failed"},
	{"signal":"server_disconnected", "method":"_server_disconnected"},
	{"signal":"network_peer_packet", "method":"_network_peer_packet"},
]

onready var gameroot = get_tree().get_root()

const PACKET_SEND_RATE = 0.0
var time_passed = 0.0
var time_until_next_send = 0.0

enum validation_state_enum {
	VALIDATION_STATE_NONE,
	VALIDATION_STATE_CONNECTION,
	VALIDATION_STATE_PEERS_SENT,
	VALIDATION_STATE_INFO_SENT,
	VALIDATION_STATE_STATE_SENT,
	VALIDATION_STATE_SYNCED
}

const network_replication_manager_const = preload("network_replication_manager.gd")
const network_state_manager_const = preload("network_state_manager.gd")
const network_entity_manager_const = preload("network_entity_manager.gd")

var network_replication_manager : Node = null
var network_state_manager : Node = null
var network_entity_manager : Node = null

var server_is_disconnected = true

# Server
var host_port : int = 7777 # Configuration
var entity_root_node_path : NodePath = NodePath()
var server_dedicated : bool = false
var max_players : int  = -1

################
# Session Data #
################
# Server
var peer_server_data : Dictionary = {}
# Shared
var active_port : int = -1
var client_state : int = validation_state_enum.VALIDATION_STATE_NONE
var peers : Array = []

signal network_process(p_delta)
signal game_hosted()

signal peer_registered(p_id)
signal peer_unregistered(p_id)
signal peer_list_changed()
signal peer_registration_complete()

signal connection_failed()
signal connection_succeeded()
signal server_disconnected()
signal network_peer_packet()

signal voice_packet_compressed(p_id, p_index, p_buffer)
	
#Server
func _network_peer_connected(p_id : int) -> void:
	peer_server_data[p_id] = {"validation_state":validation_state_enum.VALIDATION_STATE_NONE, "time_since_last_update":0.0}
	print("Network peer {id} connected!".format({"id":str(p_id)}))

func _network_peer_disconnected(p_id : int) -> void:
	print("Network peer {id} disconnected!".format({"id":str(p_id)}))
	rpc("unregister_peer", p_id)

#Clients
func _connected_to_server() -> void:
	print("Connected to server...")
	rpc_id(SERVER_MASTER_PEER_ID, "register_peer", get_tree().multiplayer.get_network_unique_id())
	emit_signal("connection_succeeded")

func _connection_failed() -> void:
	print("Connection failed")
	emit_signal("connection_failed")
	
func _server_disconnected() -> void:
	print("Server disconnected")
	server_is_disconnected = true
	emit_signal("server_disconnected")
	
func get_entity_root_node() -> Node:
	return gameroot
	
#Client/Server
func _network_peer_packet(p_id : int, p_packet : PoolByteArray) -> void:
	emit_signal("network_peer_packet", p_id, p_packet)

func has_active_peer() -> bool:
	return server_is_disconnected == false and get_tree().multiplayer.has_network_peer() and get_tree().multiplayer.network_peer.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED
	
func is_server() -> bool:
	return has_active_peer() == false or get_tree().multiplayer.is_network_server()
	
func is_rpc_sender_id_server() -> bool:
	return get_tree().multiplayer.get_rpc_sender_id() == SERVER_MASTER_PEER_ID

func host_game(p_port : int, p_max_players : int, p_dedicated : bool) -> bool:
	if has_active_peer():
		printerr("Network peer already established")
		return false
	
	reset_session_data()
	server_is_disconnected = false
	
	server_dedicated = p_dedicated
	max_players = p_max_players
	
	if p_port >= 0:
		active_port = p_port
	else:
		active_port = host_port
	
	var net : NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	if (net.create_server(active_port, max_players) != OK):
		print("Cannot create a server on port {port}!".format({"port":str(active_port)}))
		return false
		
	time_passed = 0.0
	time_until_next_send = 0.0
		
	get_tree().multiplayer.set_network_peer(net)
	get_tree().multiplayer.set_allow_object_decoding(false)
	
	if server_dedicated:
		print("Server hosted on port {port}".format({"port":str(active_port)}))
		print("Max clients: {max_players}".format({"port":str(max_players)}))
	
	emit_signal("game_hosted")
	
	return true
	
func join_game(p_ip : String, p_port : int) -> bool:
	if has_active_peer():
		printerr("Network peer already established!")
		return false
	
	reset_session_data()
	server_is_disconnected = false
	
	var net : NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	
	if p_ip.is_valid_ip_address() == false:
		print("Invalid ip address!")
		return false

	if net.create_client(p_ip, p_port) != OK:
		print("Cannot create a client on ip {ip} & port {port}!".format(
		{"ip":p_ip, "port":str(p_port)}))
		return false
		
	active_port = p_port

	time_passed = 0.0
	time_until_next_send = 0.0

	get_tree().multiplayer.set_network_peer(net)
	get_tree().multiplayer.set_allow_object_decoding(false)

	print("Connecting to {ip} : {port}!".format(
		{"ip":p_ip, "port":str(p_port)}))
	return true
	
func reset_session_data() -> void:
	peer_server_data = {}
	active_port = -1
	client_state = validation_state_enum.VALIDATION_STATE_NONE
	peers = []
	
func force_close_connection() -> void:
	if has_active_peer():
		print("Closing connection...")
		server_is_disconnected = true
		get_tree().multiplayer.set_network_peer(null)

	reset_session_data()

func get_current_peer_id() -> int:
	if has_active_peer():
		var id : int = get_tree().multiplayer.get_network_unique_id()
		return id
	else:
		return SERVER_MASTER_PEER_ID

func get_peer_list() -> Array:
	return peers

remote func register_peer(p_id : int) -> void:
	var rpc_sender_id : int = get_tree().multiplayer.get_rpc_sender_id()
	
	# Client does not have direct permission to access this method
	if is_server():
		if peer_server_data[p_id].validation_state != validation_state_enum.VALIDATION_STATE_NONE:
			return
		peer_server_data[p_id].time_since_last_update = 0.0
	else:
		if is_rpc_sender_id_server():
			return
	
	# Reject if this player has already been registered
	if peers.has(p_id):
		printerr("Already has peer {peer_id}!".format({"peer_id":str(p_id)}))
		return
	
	if is_server():
		if !peer_is_connected(rpc_sender_id):
			printerr("register_peer: peer {rpc_sender_id} is invalid!".format(
			{"rpc_sender_id":str(rpc_sender_id)}))
			return
			
		rpc_id(rpc_sender_id, "register_peer", 1) # Register server player to new client
		
		for peer_id in peers: # Then, for each remote player
			rpc_id(rpc_sender_id, "register_peer", peer_id) # Send other clients to new client
			rpc_id(peer_id, "register_peer", rpc_sender_id) # Send new client to other players
			
	peers.append(p_id)
	emit_signal("peer_registered", p_id)
	emit_signal("peer_list_changed")
	
	if is_server():
		peer_server_data[p_id].validation_state = validation_state_enum.VALIDATION_STATE_PEERS_SENT
		rpc_id(rpc_sender_id, "peer_registration_complete") # Validate that all player registration has now been completed

sync func unregister_peer(p_id : int) -> void:
	# Client does not have direct permission to access this method
	if not is_server() and not is_rpc_sender_id_server():
		return
	
	peers.erase(p_id)
	if is_server():
		if peer_server_data.erase(p_id) == false:
			printerr("Could not erase peer server data!")
	
	emit_signal("peer_unregistered", p_id)
	emit_signal("peer_list_changed")
	
# Called after all other clients have been registered to the new client
puppet func peer_registration_complete() -> void:
	# Client does not have direct permission to access this method
	if not is_server() and not is_rpc_sender_id_server():
		return
	
	emit_signal("peer_registration_complete")
	
# Test to see if the peer with this id is connected
func peer_is_connected(p_id : int) -> bool:
	var connected_peers : PoolIntArray = get_connected_peers()
	for i in range(0, connected_peers.size()):
		if connected_peers[i] == p_id:
			return true
		
	return false
	
func get_connected_peers() -> PoolIntArray:
	if get_tree().multiplayer.has_network_peer():
		var connected_peers : PoolIntArray = get_tree().multiplayer.get_network_connected_peers()
		return connected_peers
	else:
		return PoolIntArray()
	
func get_synced_peers() -> Array:
	var valid_peers : Array = []
	if is_server():
		for key in peer_server_data.keys():
			if peer_server_data[key].validation_state == validation_state_enum.VALIDATION_STATE_SYNCED:
				valid_peers.append(key)
				
	return valid_peers

##########################
# Network state transfer #
##########################

signal create_server_info()
signal create_server_state()

signal peer_validation_state_error_callback()

signal requested_server_info(p_id, p_client_message)
signal received_server_info(p_info)
signal requested_server_state(p_id, p_client_message)
signal received_server_state(p_state)

master func create_server_info() -> void:
	print("create_server_info...")
	emit_signal("create_server_info")
	
master func create_server_state() -> void:
	print("create_server_state...")
	emit_signal("create_server_state")

remote func peer_validation_state_error_callback() -> void:
	print("peer_validation_state_error_callback...")
	if is_server():
		rpc("peer_validation_state_error_callback")
	else:
		# Return if the rpc sender was not the server
		if not is_rpc_sender_id_server():
			return
		
	emit_signal("peer_validation_state_error_callback")

# Called by the client once the server has confirmed they have been validated
master func requested_server_info(p_client_info: Dictionary) -> void:
	print("requested_server_info...")
	var rpc_sender_id : int = get_tree().multiplayer.get_rpc_sender_id()
	
	if peer_server_data[rpc_sender_id].validation_state != validation_state_enum.VALIDATION_STATE_PEERS_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[rpc_sender_id].validation_state = validation_state_enum.VALIDATION_STATE_INFO_SENT
		peer_server_data[rpc_sender_id].time_since_last_update = 0.0
		emit_signal("requested_server_info", rpc_sender_id)
		
# Called by the server 
puppet func received_server_info(p_server_info : Dictionary) -> void:
	print("received_server_info...")
	emit_signal("received_server_info", p_server_info)
		
# Called by client after the basic scene state for the client has been loaded and set up
master func requested_server_state(p_client_info: Dictionary) -> void:
	print("requested_server_state...")
	var rpc_sender_id : int = get_tree().multiplayer.get_rpc_sender_id()
	
	if peer_server_data[rpc_sender_id].validation_state != validation_state_enum.VALIDATION_STATE_INFO_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[rpc_sender_id].validation_state = validation_state_enum.VALIDATION_STATE_STATE_SENT
		peer_server_data[rpc_sender_id].time_since_last_update = 0.0
		emit_signal("requested_server_state", rpc_sender_id)
		
puppet func received_server_state(p_state : PoolByteArray) -> void:
	print("received_server_state...")
	emit_signal("received_server_state", p_state)
		
func confirm_client_ready_for_sync(p_network_id : int) -> void:
	print("confirm_client_ready_for_sync...")
	if peer_server_data[p_network_id].validation_state != validation_state_enum.VALIDATION_STATE_STATE_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[p_network_id].time_since_last_update = 0.0
		peer_server_data[p_network_id].validation_state = validation_state_enum.VALIDATION_STATE_SYNCED
		
func confirm_server_ready_for_sync() -> void:
	print("confirm_server_ready_for_sync...")
	client_state = validation_state_enum.VALIDATION_STATE_SYNCED
		
func server_kick_player(p_id : int) -> void:
	print("server_kick_player...")
	if is_server():
		var net : NetworkedMultiplayerPeer = get_tree().multiplayer.get_network_peer()
		if net and net is NetworkedMultiplayerENet:
			net.disconnect_peer(p_id)

			if peer_server_data.erase(p_id) == false:
				printerr("Attempted to erase invalid peer_server_data entry!")
			
			# TODO register disconnection

func decode_buffer(p_id : int, p_buffer : PoolByteArray) -> void:
	var network_reader : network_reader_const = network_reader_const.new(p_buffer)
	
	while network_reader:
		var command = network_reader.get_u8()
		if network_reader.is_eof():
			break
			
		if command == network_constants_const.SPAWN_ENTITY_COMMAND or command == network_constants_const.DESTROY_ENTITY_COMMAND or command == network_constants_const.SET_PARENT_ENTITY_COMMAND or command == network_constants_const.TRANSFER_ENTITY_MASTER_COMMAND:
			network_reader = network_replication_manager.decode_replication_buffer(p_id, network_reader, command)
		elif command == network_constants_const.UPDATE_ENTITY_COMMAND:
			network_reader = network_state_manager.decode_state_buffer(p_id, network_reader, command)
			
	network_entity_manager.scene_tree_execution_table.call_deferred("_execute_scene_tree_execution_table_unsafe")

func send_packet(p_buffer : PoolByteArray, p_id : int, p_transfer_mode : int) -> void:
	get_tree().multiplayer.get_network_peer().set_transfer_mode(p_transfer_mode)
	var send_bytes_result : int = get_tree().multiplayer.send_bytes(p_buffer, p_id)
	if send_bytes_result != OK:
		ErrorManager.error("Send bytes error: {send_bytes_result}".format({"send_bytes_result":str(send_bytes_result)}))
		
func _process(p_delta : float) -> void:
	if Engine.is_editor_hint() == false:
		time_passed += p_delta
		
		if is_server():
			for peer in get_peer_list():
				peer_server_data[peer].time_since_last_update += p_delta
				
		if has_active_peer():
			if is_server() or client_state == validation_state_enum.VALIDATION_STATE_SYNCED:
				if time_passed > time_until_next_send:
					emit_signal("network_process", get_tree().multiplayer.get_network_unique_id(), p_delta)
					time_until_next_send = time_passed + PACKET_SEND_RATE
	
func _ready() -> void:
	if Engine.is_editor_hint() == false:
		entity_root_node_path = NodePath(ProjectSettings.get_setting("network/config/entity_root_node"))
		
		for current_signal in multiplayer_signal_table:
			if get_tree().multiplayer.connect(current_signal.signal, self, current_signal.method) != OK:
				printerr("NetworkManager: {signal} could not be connected!".format(
					{"signal":str(current_signal.signal)}))
					
		network_entity_manager.cache_networked_scenes()
		
func _enter_tree() -> void:
	if Engine.is_editor_hint() == false:
		#Add sub managers to the tree
		add_child(network_replication_manager)
		add_child(network_state_manager)
		add_child(network_entity_manager)

func _init() -> void:
	if Engine.is_editor_hint() == false:
		network_replication_manager = Node.new()
		network_replication_manager.set_script(network_replication_manager_const)
		network_replication_manager.set_name("NetworkReplicationManager")
		
		network_state_manager = Node.new()
		network_state_manager.set_script(network_state_manager_const)
		network_state_manager.set_name("NetworkStateManager")
		
		network_entity_manager = Node.new()
		network_entity_manager.set_script(network_entity_manager_const)
		network_entity_manager.set_name("NetworkEntityManager")
