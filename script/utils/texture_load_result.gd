class_name TextureLoadResult
extends RefCounted

var texture: Texture2D
var used_rect: Rect2i
var vram_bytes: int = -1

func _init(p_texture: Texture2D = null, p_used_rect: Rect2i = Rect2i(), p_vram_bytes: int = -1) -> void:
	texture = p_texture
	used_rect = p_used_rect
	vram_bytes = p_vram_bytes