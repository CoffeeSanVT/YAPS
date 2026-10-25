class_name AtlasPacker
extends RefCounted

const MIN_PAGE_SIZE := 64
const MAX_PAGE_SIZE := 4096
const DEFAULT_PADDING := 2
const MAX_FREE_RECTS := 512

static func trim_sprite(source: Image, alpha_threshold: float = 0.0) -> Dictionary:
	if source == null or source.is_empty():
		return {}
	var image := source
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
	if image.has_mipmaps():
		image.clear_mipmaps()
	var rect := Rect2i()
	if alpha_threshold <= 0.0:
		rect = image.get_used_rect()
	else:
		rect = _threshold_rect(image, alpha_threshold)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return {}
	return {
		"image": image.get_region(rect),
		"offset": rect.position,
		"size": rect.size,
	}

static func pack(sizes: Array[Vector2i], padding: int = DEFAULT_PADDING, min_page: int = MIN_PAGE_SIZE, max_page: int = MAX_PAGE_SIZE, merge_singles: bool = true) -> Dictionary:
	var order: Array[int] = []
	var valid_area := 0
	for i: int in sizes.size():
		if sizes[i].x > 0 and sizes[i].y > 0:
			order.append(i)
			valid_area += sizes[i].x * sizes[i].y
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa := sizes[a]
		var sb := sizes[b]
		if sa.y != sb.y:
			return sa.y > sb.y
		return sa.x > sb.x
	)
	var max_pot := next_pot(max_page)
	var best: Dictionary = {}
	var fallback: Dictionary = {}
	var fallback_used := -1
	var size := clampi(next_pot(min_page), 1, max_pot)
	while size <= max_pot:
		var attempt := _pack_all(order, sizes, padding, size, max_pot)
		if attempt.complete and attempt.used_area == valid_area:
			if best.is_empty() or attempt.total_area < best.total_area or (attempt.total_area == best.total_area and attempt.page_count < best.page_count):
				best = attempt
		elif attempt.used_area > fallback_used:
			fallback = attempt
			fallback_used = attempt.used_area
		size <<= 1
	if best.is_empty():
		push_error("[AtlasPacker] could not pack all sprites within page size %d" % max_pot)
		best = fallback
	var pages: Array = _merge_single_frame_pages(best.pages, sizes, padding, max_pot) if merge_singles else best.pages
	var used_area := 0
	var total_area := 0
	for page: Dictionary in pages:
		var page_size: Vector2i = page.size
		for placement: Dictionary in page.placements:
			used_area += sizes[placement.index].x * sizes[placement.index].y
		total_area += page_size.x * page_size.y
	return {
		"pages": pages,
		"used_area": used_area,
		"total_area": total_area,
		"fill_ratio": float(used_area) / float(total_area) if total_area > 0 else 0.0,
	}

static func _merge_single_frame_pages(pages: Array, sizes: Array[Vector2i], padding: int, max_pot: int) -> Array:
	var merged := pages.duplicate()
	var changed := true
	while changed:
		changed = false
		if merged.size() < 2:
			break
		for page_index: int in merged.size():
			var page_placements: Array = merged[page_index].placements
			if page_placements.size() != 1:
				continue
			var merge_with := page_index + 1 if page_index + 1 < merged.size() else page_index - 1
			var order: Array[int] = []
			for placement: Dictionary in page_placements:
				order.append(placement.index)
			for placement: Dictionary in merged[merge_with].placements:
				order.append(placement.index)
			order.sort_custom(func(a: int, b: int) -> bool:
				if sizes[a].y != sizes[b].y:
					return sizes[a].y > sizes[b].y
				return sizes[a].x > sizes[b].x
			)
			var page_a: Vector2i = merged[page_index].size
			var page_b: Vector2i = merged[merge_with].size
			var area_limit := (page_a.x * page_a.y + page_b.x * page_b.y) * 2
			var cap := next_pot(maxi(page_a.x, maxi(page_a.y, maxi(page_b.x, page_b.y))))
			var merged_page: Dictionary = {}
			while cap <= max_pot and merged_page.is_empty():
				var attempt := _best_shape(order, sizes, cap, padding)
				if attempt.fits:
					var attempt_size: Vector2i = attempt.page_size
					if attempt_size.x * attempt_size.y <= area_limit:
						merged_page = { "size": attempt.page_size, "placements": attempt.placements }
					break
				cap <<= 1
			if merged_page.is_empty():
				continue
			merged[merge_with] = merged_page
			merged.remove_at(page_index)
			changed = true
			break
	return merged

static func _pack_all(order: Array[int], sizes: Array[Vector2i], padding: int, page_cap: int, max_pot: int) -> Dictionary:
	var remaining := order.duplicate()
	var pages: Array = []
	var used_area := 0
	var total_area := 0
	while not remaining.is_empty():
		var result := _pack_page_capped(remaining, sizes, padding, page_cap, max_pot)
		pages.append(result.page)
		for placement: Dictionary in result.page.placements:
			used_area += sizes[placement.index].x * sizes[placement.index].y
		total_area += result.page.size.x * result.page.size.y
		if result.page.placements.is_empty():
			break
		remaining = result.leftover
	return {
		"pages": pages,
		"used_area": used_area,
		"total_area": total_area,
		"page_count": pages.size(),
		"complete": remaining.is_empty(),
	}

static func _pack_page_capped(order: Array[int], sizes: Array[Vector2i], padding: int, page_cap: int, max_pot: int) -> Dictionary:
	var cap := clampi(next_pot(MIN_PAGE_SIZE), 1, max_pot)
	var limit := mini(next_pot(page_cap), max_pot)
	var best := _best_shape(order, sizes, cap, padding)
	while not best.fits and cap < limit:
		cap <<= 1
		best = _best_shape(order, sizes, cap, padding)
	return {
		"page": { "size": best.page_size, "placements": best.placements },
		"leftover": best.leftover,
	}

static func is_pot(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0

static func next_pot(value: int) -> int:
	if is_pot(value):
		return value
	var pot := 1
	while pot < value:
		pot <<= 1
	return pot

static func _best_shape(order: Array[int], sizes: Array[Vector2i], cap: int, padding: int) -> Dictionary:
	var shapes: Array[Vector2i] = [Vector2i(cap, cap)]
	var half := cap >> 1
	if half >= MIN_PAGE_SIZE:
		shapes.append(Vector2i(cap, half))
		shapes.append(Vector2i(half, cap))
	var quarter := cap >> 2
	if quarter >= MIN_PAGE_SIZE:
		shapes.append(Vector2i(cap, quarter))
		shapes.append(Vector2i(quarter, cap))
	var best: Dictionary = {}
	var best_placed := -1
	var best_page_area := 0
	for shape: Vector2i in shapes:
		var attempt := _best_try(order, sizes, shape, padding)
		var placed := 0
		for placement: Dictionary in attempt.placements:
			placed += sizes[placement.index].x * sizes[placement.index].y
		if best.is_empty() or placed > best_placed or (placed == best_placed and shape.x * shape.y < best_page_area):
			best = attempt
			best["page_size"] = shape
			best_placed = placed
			best_page_area = shape.x * shape.y
	return best

static func _best_try(order: Array[int], sizes: Array[Vector2i], page: Vector2i, padding: int) -> Dictionary:
	var best: Dictionary = {}
	var best_area := -1
	for attempt: Dictionary in [_shelf_try(order, sizes, page, padding), _maxrects_try(order, sizes, page, padding), _grid_try(order, sizes, page, padding)]:
		var area := 0
		for placement: Dictionary in attempt.placements:
			area += sizes[placement.index].x * sizes[placement.index].y
		if area > best_area:
			best = attempt
			best_area = area
	return best

static func _shelf_try(order: Array[int], sizes: Array[Vector2i], page: Vector2i, padding: int) -> Dictionary:
	var placements: Array = []
	var leftover: Array[int] = []
	var x := 0
	var y := 0
	var row_height := 0
	for i: int in order:
		var size := sizes[i]
		if size.x > page.x or size.y > page.y:
			leftover.append(i)
			continue
		if x + size.x > page.x:
			y += row_height + padding
			x = 0
			row_height = 0
		if y + size.y > page.y:
			leftover.append(i)
			continue
		placements.append({ "index": i, "rect": Rect2i(x, y, size.x, size.y) })
		x += size.x + padding
		row_height = maxi(row_height, size.y)
	return { "fits": leftover.is_empty(), "placements": placements, "leftover": leftover }

static func _maxrects_try(order: Array[int], sizes: Array[Vector2i], page: Vector2i, padding: int) -> Dictionary:
	var placements: Array = []
	var leftover: Array[int] = []
	var free: Array[Rect2i] = [Rect2i(0, 0, page.x, page.y)]
	for i: int in order:
		var size := sizes[i]
		if size.x > page.x or size.y > page.y:
			leftover.append(i)
			continue
		var best_rect := Rect2i()
		var best_score := Vector2i(1 << 30, 1 << 30)
		var found := false
		for candidate: Rect2i in free:
			if candidate.size.x < size.x or candidate.size.y < size.y:
				continue
			var short_leftover := mini(candidate.size.x - size.x, candidate.size.y - size.y)
			var long_leftover := maxi(candidate.size.x - size.x, candidate.size.y - size.y)
			var score := Vector2i(short_leftover, long_leftover)
			if not found or _score_less(score, best_score) or (score == best_score and candidate.position < best_rect.position):
				found = true
				best_score = score
				best_rect = Rect2i(candidate.position, size)
		if not found:
			leftover.append(i)
			continue
		placements.append({ "index": i, "rect": best_rect })
		var occupied := Rect2i(best_rect.position, best_rect.size + Vector2i(padding, padding))
		var next_free: Array[Rect2i] = []
		for area: Rect2i in free:
			_split_free_rect(next_free, area, occupied)
		free = _dedup_free_rects(next_free)
	return { "fits": leftover.is_empty(), "placements": placements, "leftover": leftover }

static func _score_less(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

static func _split_free_rect(out: Array[Rect2i], area: Rect2i, occupied: Rect2i) -> void:
	if area.position.x >= occupied.end.x or area.position.y >= occupied.end.y or area.end.x <= occupied.position.x or area.end.y <= occupied.position.y:
		out.append(area)
		return
	if occupied.position.y > area.position.y:
		out.append(Rect2i(area.position.x, area.position.y, area.size.x, occupied.position.y - area.position.y))
	if occupied.end.y < area.end.y:
		out.append(Rect2i(area.position.x, occupied.end.y, area.size.x, area.end.y - occupied.end.y))
	if occupied.position.x > area.position.x:
		out.append(Rect2i(area.position.x, area.position.y, occupied.position.x - area.position.x, area.size.y))
	if occupied.end.x < area.end.x:
		out.append(Rect2i(occupied.end.x, area.position.y, area.end.x - occupied.end.x, area.size.y))

static func _dedup_free_rects(rects: Array[Rect2i]) -> Array[Rect2i]:
	var unique: Dictionary[Rect2i, bool] = {}
	for area: Rect2i in rects:
		if area.size.x <= 0 or area.size.y <= 0:
			continue
		unique[area] = true
	var kept: Array[Rect2i] = []
	for area: Rect2i in unique:
		kept.append(area)
		if kept.size() >= MAX_FREE_RECTS:
			break
	return kept


static func _grid_try(order: Array[int], sizes: Array[Vector2i], page: Vector2i, padding: int) -> Dictionary:
	var placements: Array = []
	var leftover: Array[int] = []
	var cell_w := 0
	var cell_h := 0
	for i: int in order:
		cell_w = maxi(cell_w, sizes[i].x)
		cell_h = maxi(cell_h, sizes[i].y)
	var cols := 0
	var rows := 0
	@warning_ignore("integer_division")
	cols = (page.x + padding) / (cell_w + padding)
	@warning_ignore("integer_division")
	rows = (page.y + padding) / (cell_h + padding)
	var capacity := cols * rows
	var placed := 0
	for i: int in order:
		if placed < capacity:
			@warning_ignore("integer_division")
			var col := placed % cols
			@warning_ignore("integer_division")
			var row := placed / cols
			placements.append({ "index": i, "rect": Rect2i(col * (cell_w + padding), row * (cell_h + padding), sizes[i].x, sizes[i].y) })
			placed += 1
		else:
			leftover.append(i)
	return { "fits": leftover.is_empty(), "placements": placements, "leftover": leftover }

static func _threshold_rect(image: Image, alpha_threshold: float) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	var data := image.get_data()
	var limit := int(roundf(clampf(alpha_threshold, 0.0, 1.0) * 255.0))
	for y: int in height:
		var row := y * width * 4
		for x: int in width:
			if data[row + x * 4 + 3] >= limit:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
