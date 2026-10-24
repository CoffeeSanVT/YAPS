class_name IoService

const IO_WAIT_TIMEOUT_MS := 15000

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

## Waits for every pending task to finish, giving up after timeout_ms so a
## stuck (or very long) background task can never block app shutdown forever.
static func wait_for_io(timeout_ms: int = IO_WAIT_TIMEOUT_MS) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	var pending: Array[int] = _pending_task_ids.duplicate()
	for task_id in pending:
		while not WorkerThreadPool.is_task_completed(task_id):
			if Time.get_ticks_msec() >= deadline:
				push_warning("[IoService] wait_for_io timed out with %d task(s) pending" % _pending_task_ids.size())
				_pending_task_ids.clear()
				return
			OS.delay_msec(10)
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
	var _pending_tasks: Array[Callable] = []
	var _pending_saves: Dictionary = {}

	func schedule(task: Callable) -> void:
		if _busy:
			_pending_tasks.append(task)
			return
		_busy = true
		IoService.run_io(func() -> Error: return task.call(), _on_done)

	## Coalesces bursts: while a save is running (or queued), only the latest
	## state per destination path is kept, so N rapid events cost one snapshot
	## + one disk write instead of N.
	func save_resource(resource: Resource, path: String, ensure_dir: String = "") -> void:
		if resource == null:
			push_error(TAG + "cannot save null resource to " + path)
			return
		if _busy:
			_pending_saves[path] = [resource, ensure_dir]
			return
		_busy = true
		_dispatch(resource, path, ensure_dir)

	func _dispatch(resource: Resource, path: String, ensure_dir: String) -> void:
		var original_path: String = resource.resource_path
		resource.resource_path = ""
		var snapshot: Resource = resource.duplicate(true)
		resource.resource_path = original_path
		IoService.run_io(func() -> Error:
			if not ensure_dir.is_empty():
				var dir_err := PathUtil.ensure_dir(ensure_dir)
				if dir_err != OK:
					return dir_err
			return ResourceSaver.save(snapshot, path)
		, _on_done)

	func _on_done(err: Error) -> void:
		_busy = false
		if err != OK:
			push_error(TAG + "task failed: %s" % error_string(err))
		if not _pending_tasks.is_empty():
			var next: Callable = _pending_tasks.pop_front()
			_busy = true
			IoService.run_io(func() -> Error: return next.call(), _on_done)
			return
		if _pending_saves.is_empty():
			return
		var next_path: String = _pending_saves.keys()[0]
		var entry: Array = _pending_saves[next_path]
		_pending_saves.erase(next_path)
		_busy = true
		_dispatch(entry[0], next_path, entry[1])
