class_name TextureLoadResult
extends RefCounted

var texture: Texture2D
var used_rect: Rect2i

func _init(p_texture: Texture2D = null, p_used_rect: Rect2i = Rect2i()) -> void:
	texture = p_texture
	used_rect = p_used_rect