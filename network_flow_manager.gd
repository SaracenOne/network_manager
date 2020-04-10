extends Node
tool

const ref_pool_const = preload("res://addons/gdutil/ref_pool.gd")

var internal_timer = 0.0

# Network latency simulation
var simulate_network_conditions : bool = false
var min_latency : float = 0.0
var max_latency : float = 0.0
var drop_rate : float = 0.0
var dup_rate : float = 0.0

class PendingPacket extends Reference:
	var id : int = -1
	var ref_pool : Reference = null
	
	func _init(p_id : int, p_ref_pool : Reference) -> void:
		id = p_id
		ref_pool = p_ref_pool
		
class PendingPacketTimed extends PendingPacket:
	var time : float = 0.0
	
	func _init(p_id : int, p_ref_pool : Reference, p_time : float).(p_id, p_ref_pool) -> void:
		time = p_time

var unreliable_packet_queue : Array = []
var unreliable_ordered_packet_queue : Array = []
var reliable_packet_queue : Array = []

# For network simulation
var unreliable_packet_queue_time_sorted : Array = []
var unreliable_ordered_packet_queue_time_sorted : Array = []
var reliable_packet_queue_time_sorted : Array = []

var packet_peer_target : Dictionary = {}

func queue_packet_for_send(p_ref_pool : ref_pool_const, p_id : int, p_transfer_mode : int) -> void:
	match p_transfer_mode:
		NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE:
			unreliable_packet_queue.push_back(PendingPacket.new(p_id, p_ref_pool))
		NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
			unreliable_ordered_packet_queue.push_back(PendingPacket.new(p_id, p_ref_pool))
		NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE:
			reliable_packet_queue.push_back(PendingPacket.new(p_id, p_ref_pool))
		_:
			printerr("Attempted to queue packet with invalid transfer mode!")

func send_packet_queue(p_packet_queue : Array, p_transfer_mode : int):
	if get_tree().multiplayer.get_network_peer():
		get_tree().multiplayer.get_network_peer().set_transfer_mode(p_transfer_mode)
		for packet in p_packet_queue:
			if packet.id == NetworkManager.ALL_PEERS \
			or packet.id == NetworkManager.SERVER_MASTER_PEER_ID \
			or NetworkManager.peers.has(packet.id):
				var send_bytes_result : int = get_tree().multiplayer.send_bytes(packet.ref_pool.pool_byte_array, packet.id)
				if send_bytes_result != OK:
					ErrorManager.error("Send bytes error: {send_bytes_result}".format({"send_bytes_result":str(send_bytes_result)}))

func sort_packet_queue_by_time(a, b):
	return a.time <= b.time

func ordered_inserted(p_packet : Reference, p_time_sorted_queue : Array, p_packet_time : float):
	if p_time_sorted_queue.size():
		var packet_inserted : bool = false
		for i in range(0, p_time_sorted_queue.size()):
			if p_packet_time < p_time_sorted_queue[i].time:
				p_time_sorted_queue.insert(i, p_packet)
				packet_inserted = true
				break
				
		# If the packet was not inserted, put it in the end of the queue
		if packet_inserted == false:
			p_time_sorted_queue.append(p_packet)
	else:
		p_time_sorted_queue.append(p_packet)

func setup_and_send_ordered_queue(p_time : float, p_queue : Array, p_time_sorted_queue : Array, p_packet_type : int) -> Array:
	for packet in p_queue:
		if p_packet_type != NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE:
			if randf() < drop_rate:
				continue
			
		var first_packet_time : float = p_time + min_latency + randf() * (max_latency-min_latency)
		match p_packet_type:
			NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE:
				var new_packet : Reference = PendingPacketTimed.new(packet.id, packet.ref_pool, first_packet_time)
				ordered_inserted(new_packet, p_time_sorted_queue, first_packet_time)
			NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
				var latest_time : float = 0.0
				if p_time_sorted_queue.size() > 0:
					latest_time = p_time_sorted_queue.back().time
				if first_packet_time >= latest_time:
					p_time_sorted_queue.append(PendingPacketTimed.new(packet.id, packet.ref_pool, first_packet_time))
			NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE:
				var latest_time : float = 0.0
				if p_time_sorted_queue.size() > 0:
					latest_time = p_time_sorted_queue.back().time
				p_time_sorted_queue.append(PendingPacketTimed.new(packet.id, packet.ref_pool, max(latest_time, first_packet_time)))
			
		while(randf() < dup_rate):
			var dup_packet_time : float = p_time + min_latency + randf() * (max_latency-min_latency)
			match p_packet_type:
				NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE:
					var new_packet : Reference = PendingPacketTimed.new(packet.id, packet.ref_pool, dup_packet_time)
					ordered_inserted(new_packet, p_time_sorted_queue, dup_packet_time)
				NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED:
					var latest_time : float = 0.0
					if p_time_sorted_queue.size() > 0:
						latest_time = p_time_sorted_queue.back().time
					if dup_packet_time >= latest_time:
						p_time_sorted_queue.append(PendingPacketTimed.new(packet.id, packet.ref_pool, dup_packet_time))

	var current_queue : Array = p_time_sorted_queue.duplicate()
	for packet in current_queue:
		if p_time >= packet.time:
			var index : int = p_time_sorted_queue.find(packet)
			assert(index >= 0)
			if packet.id == NetworkManager.ALL_PEERS \
			or packet.id == NetworkManager.SERVER_MASTER_PEER_ID \
			or NetworkManager.peers.has(packet.id):
				var send_bytes_result : int = get_tree().multiplayer.send_bytes(packet.ref_pool.pool_byte_array, packet.id)
				if send_bytes_result != OK:
					ErrorManager.error("Send bytes error: {send_bytes_result}".format({"send_bytes_result":str(send_bytes_result)}))
			p_time_sorted_queue.remove(index)
			
	return p_time_sorted_queue

func process_network_packets(p_delta : float) -> void:
	internal_timer += p_delta
	
	if simulate_network_conditions:
		reliable_packet_queue_time_sorted = setup_and_send_ordered_queue(internal_timer, reliable_packet_queue, reliable_packet_queue_time_sorted, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
		unreliable_packet_queue_time_sorted = setup_and_send_ordered_queue(internal_timer, unreliable_packet_queue, unreliable_packet_queue_time_sorted, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
		unreliable_ordered_packet_queue_time_sorted = setup_and_send_ordered_queue(internal_timer, unreliable_ordered_packet_queue, unreliable_ordered_packet_queue_time_sorted, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	else:
		send_packet_queue(reliable_packet_queue, NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE)
		send_packet_queue(unreliable_packet_queue, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
		send_packet_queue(unreliable_ordered_packet_queue, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	
	clear_packet_queues()

	
func clear_packet_queues() -> void:
	unreliable_packet_queue = []
	unreliable_ordered_packet_queue = []
	reliable_packet_queue = []
	
	
func clear_time_sorted_packet_queues() -> void:
	unreliable_packet_queue_time_sorted = []
	unreliable_ordered_packet_queue_time_sorted = []
	reliable_packet_queue_time_sorted = []
	
func reset():
	internal_timer = 0.0
	clear_packet_queues()
	clear_time_sorted_packet_queues()

func _ready() -> void:
	if ProjectSettings.has_setting("network/config/simulate_network_conditions"):
		simulate_network_conditions = ProjectSettings.get_setting("network/config/simulate_network_conditions")
	else:
		ProjectSettings.set_setting("network/config/simulate_network_conditions", simulate_network_conditions)
		
	if ProjectSettings.has_setting("network/config/min_latency"):
		min_latency = ProjectSettings.get_setting("network/config/min_latency")
	else:
		ProjectSettings.set_setting("network/config/min_latency", min_latency)

	if ProjectSettings.has_setting("network/config/max_latency"):
		max_latency = ProjectSettings.get_setting("network/config/max_latency")
	else:
		ProjectSettings.set_setting("network/config/max_latency", max_latency)
		
	if ProjectSettings.has_setting("network/config/drop_rate"):
		drop_rate = ProjectSettings.get_setting("network/config/drop_rate")
	else:
		ProjectSettings.set_setting("network/config/drop_rate", drop_rate)

	if ProjectSettings.has_setting("network/config/dup_rate"):
		dup_rate = ProjectSettings.get_setting("network/config/dup_rate")
	else:
		ProjectSettings.set_setting("network/config/dup_rate", dup_rate)
