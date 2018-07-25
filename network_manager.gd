extends Node
tool

const SERVER_PEER_ID = 1
const PEER_PENDING_TIMEOUT = 20

enum  {
	VALIDATION_STATE_NONE,
	VALIDATION_STATE_CONNECTION,
	VALIDATION_STATE_PEERS_SENT,
	VALIDATION_STATE_INFO_SENT,
	VALIDATION_STATE_STATE_SENT,
	VALIDATION_STATE_SYNCED
}

# Version (used to validate if client and server are using compatible version of the game)
var network_protocol_version_major = 0
var network_protocol_version_minor = 1

# Server
var entity_root_node_path = NodePath()
var server_dedicated = false
var port = -1
var max_players  = -1
var peer_server_data = {}

# Client/Server
var private_encryption_key = ""
var client_state = VALIDATION_STATE_NONE

var current_peer_id = -1
var peers = []

# Universal Plug-and-Play
var upnp = null

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

signal game_ended()
signal game_error(what)

#Server
func _network_peer_connected(p_id):
	peer_server_data[p_id] = {"validation_state":VALIDATION_STATE_NONE, "time_since_last_update":0.0}
	print("Network peer " + str(p_id) + " connected!")

func _network_peer_disconnected(p_id):
	print("Network peer " + str(p_id) + " disconnected!")
	rpc("unregister_peer", p_id)

#Clients
func _connected_to_server():
	print("Connected to server...")
	rpc_id(SERVER_PEER_ID, "register_peer", get_tree().multiplayer.get_network_unique_id())
	emit_signal("connection_succeeded")

func _connection_failed():
	print("Connection failed")
	emit_signal("connection_failed")
	
func _server_disconnected():
	print("Server disconnected")
	emit_signal("server_disconnected")
	
#Client/Server
func _network_peer_packet(p_id, p_packet):
	print("Peer packet")
	emit_signal("network_peer_packet", p_id, p_packet)

func has_peer():
	return get_tree().multiplayer.has_network_peer()
	
func is_server():
	return has_peer() == false or get_tree().multiplayer.is_network_server()
	
func is_rpc_sender_id_server():
	return get_tree().multiplayer.get_rpc_sender_id() == SERVER_PEER_ID
	
func set_up_upnp():
	upnp = UPNP.new()
	var upnp_discovery_result = upnp.discover()
	var upnp_result = upnp.add_port_mapping(1234)
	if upnp_result == UPNP.UPNP_RESULT_SUCCESS:
		pass
	else:
		pass
		
	return

func host_game(p_port, p_max_players, p_dedicated):
	if get_tree().multiplayer.has_network_peer():
		printerr("Network peer already established")
		return false
	
	current_peer_id = SERVER_PEER_ID
	port = p_port
	server_dedicated = p_dedicated
	max_players = p_max_players
	
	var net = NetworkedMultiplayerENet.new()
	if (net.create_server(port, max_players) != OK):
		print("Cannot create a server on port " + str(port) + "!")
		return false
		
	get_tree().multiplayer.set_network_peer(net)
	
	if server_dedicated:
		print("Server hosted on port " + str(port) + ".")
		print("Max clients: " + str(max_players))
	
	emit_signal("game_hosted")
	
	return true
	
func join_game(p_ip, p_port):
	if get_tree().multiplayer.has_network_peer():
		printerr("Network peer already established!")
		return
	
	var net = NetworkedMultiplayerENet.new()
	
	if p_ip.is_valid_ip_address() == false:
		print("Invalid ip address!")
		return false

	if net.create_client(p_ip, p_port) != OK:
		print("Cannot create a client on ip " + p_ip + " & port " + str(p_port) + "!")
		return false

	get_tree().multiplayer.set_network_peer(net)

	print("Connecting to " + p_ip + ":" + str(p_port) + "..")
	return true
	
func close_connection():
	if get_tree().multiplayer.has_network_peer():
		var net = get_tree().multiplayer.get_network_peer()
		net.close_connection()
		get_tree().set_network_peer(null)

func get_peer_list():
	return peers

remote func register_peer(p_id):
	var rpc_sender_id = get_tree().multiplayer.get_rpc_sender_id()
	
	# Client does not have direct permission to access this method
	if is_server():
		if peer_server_data[p_id].validation_state != VALIDATION_STATE_NONE:
			return
		peer_server_data[p_id].time_since_last_update = 0.0
	else:
		if is_rpc_sender_id_server():
			return
	
	# Reject if this player has already been registered
	if peers.has(p_id):
		return
	
	if is_server():
		if !peer_is_connected(rpc_sender_id):
			printerr("register_peer: peer " + str(rpc_sender_id) + " is invalid!")
			return
			
		rpc_id(rpc_sender_id, "register_peer", 1) # Register server player to new client
		
		for peer_id in peers: # Then, for each remote player
			rpc_id(rpc_sender_id, "register_peer", peer_id) # Send other clients to new client
			rpc_id(peer_id, "register_peer", rpc_sender_id) # Send new client to other players
			
	peers.append(p_id)
	emit_signal("peer_registered", p_id)
	emit_signal("peer_list_changed")
	
	if is_server():
		peer_server_data[p_id].validation_state = VALIDATION_STATE_PEERS_SENT
		rpc_id(rpc_sender_id, "peer_registration_complete") # Validate that all player registration has now been completed

sync func unregister_peer(p_id):
	# Client does not have direct permission to access this method
	if not is_server() and not is_rpc_sender_id_server():
		return
	
	peers.erase(p_id)
	if is_server():
		peer_server_data.erase(p_id)
	
	emit_signal("peer_unregistered", p_id)
	emit_signal("peer_list_changed")
	
# Called after all other clients have been registered to the new client
slave func peer_registration_complete():
	# Client does not have direct permission to access this method
	if not is_server() and not is_rpc_sender_id_server():
		return
	
	emit_signal("peer_registration_complete")
	
# Test to see if the peer with this id is connected
func peer_is_connected(p_id):
	var connected_peers = get_tree().multiplayer.get_network_connected_peers()
	for i in range(0, connected_peers.size()):
		connected_peers[i] == p_id
		return true
		
	return false
	
func get_synced_peers():
	var valid_peers = []
	if is_server():
		for key in peer_server_data.keys():
			if peer_server_data[key].validation_state == VALIDATION_STATE_SYNCED:
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

signal update_server_entities()

master func create_server_info():
	emit_signal("create_server_info")
	
master func create_server_state():
	emit_signal("create_server_state")

remote func peer_validation_state_error_callback():
	if is_server():
		rpc("peer_validation_state_error_callback")
	else:
		# Return if the rpc sender was not the server
		if not is_rpc_sender_id_server():
			return
		
	emit_signal("peer_validation_state_error_callback")

# Called by the client once the server has confirmed they have been validated
master func requested_server_info(p_client_message):
	var rpc_sender_id = get_tree().multiplayer.get_rpc_sender_id()
	
	if peer_server_data[rpc_sender_id].validation_state != VALIDATION_STATE_PEERS_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[rpc_sender_id].validation_state = VALIDATION_STATE_INFO_SENT
		peer_server_data[rpc_sender_id].time_since_last_update = 0.0
		emit_signal("requested_server_info", rpc_sender_id, p_client_message)
		
# Called by the server 
slave func received_server_info(p_info):
	emit_signal("received_server_info", p_info)
		
# Called by client after the basic scene state for the client has been loaded and set up
master func requested_server_state(p_client_message):
	var rpc_sender_id = get_tree().multiplayer.get_rpc_sender_id()
	
	if peer_server_data[rpc_sender_id].validation_state != VALIDATION_STATE_INFO_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[rpc_sender_id].validation_state = VALIDATION_STATE_STATE_SENT
		peer_server_data[rpc_sender_id].time_since_last_update = 0.0
		emit_signal("requested_server_state", rpc_sender_id, p_client_message)
		
slave func received_server_state(p_state):
	emit_signal("received_server_state", p_state)
		
func confirm_client_ready_for_sync(p_network_id):
	if peer_server_data[p_network_id].validation_state != VALIDATION_STATE_STATE_SENT:
		peer_validation_state_error_callback()
	else:
		peer_server_data[p_network_id].time_since_last_update = 0.0
		peer_server_data[p_network_id].validation_state = VALIDATION_STATE_SYNCED
		
func server_kick_player(p_id):
	if is_server():
		var net = get_tree().multiplayer.get_network_peer()
		if net and net is NetworkedMultiplayerENet:
			net.disconnect_peer(p_id)
			# TODO register disconnection

func send_packet(p_buffer, p_id, p_transfer_mode):
	get_tree().multiplayer.get_network_peer().set_transfer_mode(p_transfer_mode)
	get_tree().multiplayer.send_bytes(p_buffer, p_id)
		
func _process(p_delta):
	if Engine.is_editor_hint() == false:
		if is_server():
			for peer in get_peer_list():
				peer_server_data[peer].time_since_last_update += p_delta
			emit_signal("network_process", p_delta)
	
func _ready():
	if Engine.is_editor_hint() == false:
		#Server and Clients
		get_tree().multiplayer.connect("network_peer_connected", self, "_network_peer_connected")
		get_tree().multiplayer.connect("network_peer_disconnected", self,"_network_peer_disconnected")
		
		#Clients
		get_tree().multiplayer.connect("connected_to_server", self, "_connected_to_server")
		get_tree().multiplayer.connect("connection_failed", self, "_connection_failed")
		get_tree().multiplayer.connect("server_disconnected", self, "_server_disconnected")
		
		###
		get_tree().multiplayer.connect("network_peer_packet", self, "_network_peer_packet")
		
		entity_root_node_path = NodePath(ProjectSettings.get_setting("network/config/entity_root_node"))