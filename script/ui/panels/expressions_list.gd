extends Control

@export_category("UI References")
@export var hflow_container: HFlowContainer
@export var panel_prefab: PackedScene

func _ready() -> void:
	_setup_branch_containers()
	SignalBus.states_changed.connect(_refresh)
	_wire_branch_add_buttons()
	_refresh()

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"states_changed", _refresh)

func _branch_containers() -> Array[VBoxContainer]:
	var result: Array[VBoxContainer] = []
	for child in hflow_container.get_children():
		if not child is PanelContainer:
			continue
		var container := child.get_child(0) as VBoxContainer
		if container != null:
			result.append(container)
	return result

func _wire_branch_add_buttons() -> void:
	for container in _branch_containers():
		if not container.has_meta(&"branch_name"):
			continue
		var add_button: Button = container.get_node_or_null(NodePath("Header/AddStateButton"))
		if add_button == null:
			continue
		var branch_name: String = String(container.get_meta(&"branch_name"))
		add_button.pressed.connect(_on_add_state_pressed.bind(branch_name))

func _setup_branch_containers() -> void:
	for container in _branch_containers():
		var branch_name := String(container.get_parent().name)
		if branch_name == "Talking" or branch_name == "Silence":
			container.set_meta(&"branch_name", branch_name)
			_set_branch_title(container, branch_name)

func _set_branch_title(container: VBoxContainer, branch_name: String) -> void:
	var title: Label = container.get_node_or_null(NodePath("Header/Title"))
	if title == null:
		return
	var key := branch_name.to_upper()
	title.set_meta(&"localization_key", key)
	title.text = tr(key)

func _refresh() -> void:
	if ModelLoader.model_loaded == null:
		return
	_clear_entries(ModelState.TALKING)
	_clear_entries(ModelState.SILENCE)
	_populate_branch(ModelState.TALKING)
	_populate_branch(ModelState.SILENCE)

func _find_branch_container(branch_name: String) -> VBoxContainer:
	for container in _branch_containers():
		if container.has_meta(&"branch_name") and String(container.get_meta(&"branch_name")) == branch_name:
			return container
	return null

func _clear_entries(branch_name: String) -> void:
	var container := _find_branch_container(branch_name)
	if container == null:
		return
	var entries: Control = container.get_node_or_null(NodePath("Entries"))
	if entries == null:
		return
	NodeUtil.clear_children(entries)

func _populate_branch(branch_name: String) -> void:
	var branch: ModelState = ModelLoader.model_loaded.get_branch(branch_name)
	if branch == null:
		return

	var container := _find_branch_container(branch_name)
	if container == null:
		return
	var entries: Control = container.get_node_or_null(NodePath("Entries"))
	if entries == null:
		return

	if branch.default_entry != null:
		_create_entry_panel(branch.default_entry, entries)

	for entry in branch.emotion_entries:
		_create_entry_panel(entry, entries)

func _create_entry_panel(entry: ModelStateEntry, parent: Node) -> void:
	var panel := panel_prefab.instantiate()
	panel.set_state_entry(entry)
	parent.add_child(panel)

func _on_add_state_pressed(branch_name: String) -> void:
	FileDialogHelper.open_file(self, _on_state_image_selected.bind(branch_name))

func _on_state_image_selected(path: String, branch_name: String) -> void:
	ModelLoader.add_state_to_model(path, branch_name)
