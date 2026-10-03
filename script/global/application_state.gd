extends Node

enum AppState { NORMAL, RE_MAPPING_INPUT, EDITING, LOADING }

var state: AppState = AppState.NORMAL
var _state_before_loading: AppState = AppState.NORMAL

func set_state(new_state: AppState) -> void:
	if new_state == state:
		return
	if new_state == AppState.LOADING:
		_state_before_loading = state
	state = new_state

func get_state() -> AppState:
	return state

func set_loading(loading: bool) -> void:
	if loading:
		set_state(AppState.LOADING)
		return
	if state != AppState.LOADING:
		return
	set_state(_state_before_loading)
