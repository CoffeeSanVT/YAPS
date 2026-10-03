class_name IoService

static var _pending_task_ids: Array[int] = []

static func run_io(task: Callable, on_done: Callable = Callable(), owner: Object = null) -> void:
	var id_box: Array[int] = [-1]
	var owner_ref: WeakRef = weakref(owner) if owner != null else null
	var deliver := func(result: Variant) -> void:
		_pending_task_ids.erase(id_box[0])
		if owner_ref != null and owner_ref.get_ref() == null:
			return
		if on_done.is_valid():
			on_done.call(result)
	var task_id := WorkerThreadPool.add_task(func() -> void:
		var result: Variant = task.call()
		deliver.call_deferred(result)
	)
	id_box[0] = task_id
	_pending_task_ids.append(task_id)

static func wait_for_io() -> void:
	for task_id in _pending_task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_pending_task_ids.clear()

static func request_gpu_image(path: String, done: Callable, owner: Object = null) -> void:
	run_io(func() -> Image:
		var cached := ImageUtil.load_vram_cache(path)
		if not cached.is_empty():
			return cached.image
		var image := ImageUtil.load_image(path)
		if image != null:
			ImageUtil.compress_for_gpu(image, path, image.get_used_rect())
		return image
	, done, owner)

class DeferredSaver:
	const TAG := "[DeferredSaver] "

	var _busy := false
	var _pending_task: Callable = Callable()

	func schedule(task: Callable) -> void:
		if _busy:
			_pending_task = task
			return
		_busy = true
		IoService.run_io(func() -> Error: return task.call(), func(err: Error) -> void:
			_busy = false
			if err != OK:
				push_error(TAG + "task failed: %s" % error_string(err))
			if _pending_task.is_valid():
				var next := _pending_task
				_pending_task = Callable()
				schedule(next)
		)

	func save_resource(resource: Resource, path: String, ensure_dir: String = "") -> void:
		if resource == null:
			push_error(TAG + "cannot save null resource to " + path)
			return
		var snapshot: Resource = resource.duplicate(true)
		schedule(func() -> Error:
			if not ensure_dir.is_empty():
				var dir_err := PathUtil.ensure_dir(ensure_dir)
				if dir_err != OK:
					return dir_err
			return ResourceSaver.save(snapshot, path)
		)
