@tool
extends EditorPlugin

var _exporter: DataExportPlugin


func _enter_tree() -> void:
	_exporter = DataExportPlugin.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null


# The data folders carry .gdignore (so the importer leaves the raw files alone), which also hides them
# from the exporter. Desktop builds read them next to the executable; Android and Web have no such folder,
# so the raw files are added straight into the .pck where DataPaths finds them under res://.
class DataExportPlugin extends EditorExportPlugin:
	const FOLDERS := ["Assets", "bin", "Sounds", "Midi"]
	const SKIP_EXTENSIONS := ["gdignore", "max", "import", "uid"]
	# The web build has no music (Midi is skipped) and only packs the file types the game reads, to keep
	# the browser download small.
	const WEB_FOLDERS := {
		"Assets": ["jpg", "png", "md2", "3ds"],
		"bin": ["dat", "map", "mod", "cmp", "snd", "txt"],
		"Sounds": ["wav"],
	}

	func _get_name() -> String:
		return "DungeonStompDataExport"

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var count := 0
		if features.has("android"):
			for folder: String in FOLDERS:
				count += _add_dir("res://" + folder)
		elif features.has("web"):
			for folder: String in WEB_FOLDERS:
				count += _add_dir("res://" + folder, WEB_FOLDERS[folder])
		else:
			return
		print("DungeonStompDataExport: packed %d data files" % count)

	# allowed: when non-empty, only files with these (lower-case) extensions are packed.
	func _add_dir(dir_path: String, allowed: Array = []) -> int:
		if not DirAccess.dir_exists_absolute(dir_path):
			push_error("DungeonStompDataExport: missing data directory " + dir_path)
			return 0
		var count := 0
		for f in DirAccess.get_files_at(dir_path):
			var ext := f.get_extension().to_lower()
			if f.begins_with(".") or SKIP_EXTENSIONS.has(ext):
				continue
			if not allowed.is_empty() and not allowed.has(ext):
				continue
			var file_path := dir_path.path_join(f)
			add_file(file_path, FileAccess.get_file_as_bytes(file_path), false)
			count += 1
		for d in DirAccess.get_directories_at(dir_path):
			if not d.begins_with("."):
				count += _add_dir(dir_path.path_join(d), allowed)
		return count