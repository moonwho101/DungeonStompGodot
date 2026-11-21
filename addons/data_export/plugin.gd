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
# from the exporter. Desktop builds read them next to the executable; Android has no such folder, so the
# raw files are added straight into the .pck where DataPaths finds them under res://.
class DataExportPlugin extends EditorExportPlugin:
	const FOLDERS := ["Assets", "bin", "Sounds", "Midi"]
	const SKIP_EXTENSIONS := ["gdignore", "max", "import", "uid"]

	func _get_name() -> String:
		return "DungeonStompDataExport"

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android"):
			return
		var count := 0
		for folder: String in FOLDERS:
			count += _add_dir("res://" + folder)
		print("DungeonStompDataExport: packed %d data files" % count)

	func _add_dir(dir_path: String) -> int:
		var count := 0
		for f in DirAccess.get_files_at(dir_path):
			if f.begins_with(".") or SKIP_EXTENSIONS.has(f.get_extension().to_lower()):
				continue
			var file_path := dir_path.path_join(f)
			add_file(file_path, FileAccess.get_file_as_bytes(file_path), false)
			count += 1
		for d in DirAccess.get_directories_at(dir_path):
			if not d.begins_with("."):
				count += _add_dir(dir_path.path_join(d))
		return count
