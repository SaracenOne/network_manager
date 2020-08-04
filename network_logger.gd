extends Node
tool

var message_printl_func: FuncRef = FuncRef.new()
var message_error_func: FuncRef = FuncRef.new()


func assign_printl_func(p_instance: Object, p_function: String) -> void:
	message_printl_func.set_instance(p_instance)
	message_printl_func.set_function(p_function)


func assign_error_func(p_instance: Object, p_function: String) -> void:
	message_error_func.set_instance(p_instance)
	message_error_func.set_function(p_function)


func printl(p_text) -> void:
	if message_printl_func.is_valid():
		message_printl_func.call_func("NetworkLogger: %s" % p_text)
	else:
		print(p_text)


func error(p_text) -> void:
	if message_error_func.is_valid():
		message_error_func.call_func("NetworkLogger: %s" % p_text)
	else:
		printerr(p_text)
