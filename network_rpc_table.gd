extends "res://addons/entity_manager/component_node.gd"
class_name NetworkRPCTable

var virtual_rpc_method_table: Dictionary = {}
var virtual_rpc_property_table: Dictionary = {}


func nm_rpc_called(p_caller_id: int, p_method_id: int, p_arg_array: Array):
	var keys: Array = virtual_rpc_method_table.keys()
	if keys.size() < p_method_id and p_method_id >= 0:
		var method_name: String = keys[p_method_id]
		var rpc_mode: int = virtual_rpc_method_table[method_name].rpc_mode
		if rpc_mode == MultiplayerAPI.RPC_MODE_REMOTE or MultiplayerAPI.RPC_MODE_REMOTESYNC:
			callv(method_name, p_arg_array)
		else:
			if p_caller_id == get_network_master():
				if rpc_mode == MultiplayerAPI.RPC_MODE_PUPPET or MultiplayerAPI.RPC_MODE_PUPPETSYNC:
					callv("method_name", p_arg_array)
				else:
					NetworkLogger.error(
						"Cannot call {method_name} from peer {caller_id}!".format(
							{"method_name": method_name, "caller_id": str(p_caller_id)}
						)
					)
			else:
				if rpc_mode == MultiplayerAPI.RPC_MODE_MASTER or MultiplayerAPI.RPC_MODE_MASTERSYNC:
					callv("method_name", p_arg_array)
				else:
					NetworkLogger.error(
						"Cannot call {method_name} from peer {caller_id}!".format(
							{"method_name": method_name, "caller_id": str(p_caller_id)}
						)
					)
	else:
		NetworkLogger.error("Cannot find method for id %s!" % str(p_method_id))


func nm_rset_called(p_caller_id: int, p_property_id: int, p_value):
	var keys: Array = virtual_rpc_property_table.keys()
	if keys.size() < p_property_id and p_property_id >= 0:
		var property_name: String = keys[p_property_id]
		var rpc_mode: int = virtual_rpc_property_table[property_name].rpc_mode
		if rpc_mode == MultiplayerAPI.RPC_MODE_REMOTE or MultiplayerAPI.RPC_MODE_REMOTESYNC:
			set(property_name, p_value)
		else:
			if p_caller_id == get_network_master():
				if rpc_mode == MultiplayerAPI.RPC_MODE_PUPPET or MultiplayerAPI.RPC_MODE_PUPPETSYNC:
					set(property_name, p_value)
				else:
					NetworkLogger.error(
						"Cannot set {property_name} from peer {caller_id}!".format(
							{"property_name": property_name, "caller_id": str(p_caller_id)}
						)
					)
			else:
				if rpc_mode == MultiplayerAPI.RPC_MODE_MASTER or MultiplayerAPI.RPC_MODE_MASTERSYNC:
					set(property_name, p_value)
				else:
					NetworkLogger.error(
						"Cannot set {property_name} from peer {caller_id}!".format(
							{"property_name": property_name, "caller_id": str(p_caller_id)}
						)
					)
	else:
		NetworkLogger.error("Cannot find property for id %s!" % str(p_property_id))


func _nm_rpcp(p_peer_id: int, p_unreliable: bool, p_method: String, p_arg_array: Array):
	var keys: Array = virtual_rpc_method_table.keys()
	var id: int = -1
	for i in range(0, keys.size()):
		if keys[i] == p_method:
			var rpc_mode: int = virtual_rpc_method_table[p_method].rpc_mode
			if (
				rpc_mode == MultiplayerAPI.RPC_MODE_MASTERSYNC
				or MultiplayerAPI.RPC_MODE_PUPPETSYNC
				or MultiplayerAPI.RPC_MODE_REMOTESYNC
			):
				callv(p_method, p_arg_array)
			id = i

	if id >= 0:
		pass
	else:
		NetworkLogger.error("Could not find method id for %s!" % p_method)


func _nm_rsetp(p_peer_id: int, p_unreliable: bool, p_property: String, p_value):
	var keys: Array = virtual_rpc_property_table.keys()
	var id: int = -1
	for i in range(0, keys.size()):
		if keys[i] == p_property:
			var rpc_mode: int = virtual_rpc_property_table[p_property].rpc_mode
			if (
				rpc_mode == MultiplayerAPI.RPC_MODE_MASTERSYNC
				or MultiplayerAPI.RPC_MODE_PUPPETSYNC
				or MultiplayerAPI.RPC_MODE_REMOTESYNC
			):
				set(p_property, p_value)
			id = i

	if id >= 0:
		pass
	else:
		NetworkLogger.error("Could not find property id for %s!" % p_property)


func nm_rpc(p_method: String, p_arg_array: Array):
	_nm_rpcp(0, false, p_method, p_arg_array)


func nm_rpc_id(p_peer_id: int, p_method: String, p_arg_array: Array):
	_nm_rpcp(p_peer_id, false, p_method, p_arg_array)


func nm_rpc_unreliable(p_method: String, p_arg_array: Array):
	_nm_rpcp(0, true, p_method, p_arg_array)


func nm_rpc_unreliable_id(p_peer_id: int, p_method: String, p_arg_array: Array):
	_nm_rpcp(p_peer_id, true, p_method, p_arg_array)


func nm_rset(p_property: String, p_value):
	_nm_rsetp(0, false, p_property, p_value)


func nm_rset_id(p_peer_id: int, p_property: String, p_value):
	_nm_rsetp(p_peer_id, false, p_property, p_value)


func nm_rset_unreliable(p_property: String, p_value):
	_nm_rsetp(0, true, p_property, p_value)


func nm_rset_unreliable_id(peer_id: int, p_property: String, p_value):
	_nm_rsetp(peer_id, true, p_property, p_value)


func sanitise_rpc() -> void:
	var method_list: Array = get_method_list()
	for method in method_list:
		var rpc_mode: int = rpc_get_mode(method.name)
		if rpc_mode != MultiplayerAPI.RPC_MODE_DISABLED:
			virtual_rpc_method_table[method.name] = {"rpc_mode": rpc_mode}
			rpc_config(method, MultiplayerAPI.RPC_MODE_DISABLED)

	var property_list: Array = get_property_list()
	for property in property_list:
		var rpc_mode: int = rpc_get_mode(property.name)
		if rpc_mode != MultiplayerAPI.RPC_MODE_DISABLED:
			virtual_rpc_property_table[property.name] = {"rpc_mode": rpc_mode}
			rset_config(property, MultiplayerAPI.RPC_MODE_DISABLED)


func _init():
	sanitise_rpc()
