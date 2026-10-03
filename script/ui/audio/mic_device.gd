extends SettingsOptionButton

var default_key: StringName = &"DEFAULT"

func _ready() -> void:
	super()
	get_popup().about_to_popup.connect(_refresh_devices)

func _populate() -> void:
	_refresh_devices()

func _refresh_devices() -> void:
	var devices := AudioServer.get_input_device_list()
	var current := AudioServer.get_input_device()

	clear()

	for device in devices:
		var index := devices.find(device)
		add_item(_display_name(device), index)
		set_item_metadata(index, device)

	if devices.is_empty():
		add_item(tr(&"DEFAULT"))
		set_item_metadata(0, "Default")
		selected = 0
	elif current in devices:
		selected = devices.find(current)
	elif current.is_empty() or current == "Default":
		selected = 0
	else:
		add_item(_display_name(current))
		set_item_metadata(item_count - 1, current)
		selected = item_count - 1

	set_item_text(0, tr(default_key))

func _display_name(device: String) -> String:
	if device == "Default":
		return tr(default_key)
	var open := device.find(" (")
	var close := device.rfind(")")
	if open != -1 and close == device.length() - 1:
		device = device.substr(open + 2, close - open - 2)
	if device.length() > 24:
		device = device.substr(0, 24) + "…"
	return device

func _on_locale_refresh() -> void:
	set_item_text(0, tr(default_key))

func _on_item_selected(index: int) -> void:
	var device: String = get_item_metadata(index)
	AudioServer.set_input_device(device)
	SignalBus.mic_device_changed.emit(device)
