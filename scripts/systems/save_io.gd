class_name SaveIO
extends RefCounted
## Crash-safe JSON saves.
##   * Atomic write: the new data goes to <path>.tmp, is read back and verified,
##     the previous good file is copied to <path>.bak (the backup slot), then the
##     tmp file is renamed over <path>. A crash at any point leaves either the old
##     file or the new one, never half of one.
##   * Every file carries a header line with a format tag, version, byte count and
##     MD5 of the payload, so truncation and bit rot are detected on load.
##   * load_json() falls back to the backup when the main file is missing or
##     corrupt, and moves a corrupt main file aside as <path>.corrupt.

const FORMAT := "lasthandoff-save"
const VERSION := 1

static var last_status := ""   # "main", "tmp", "backup", "none", "corrupt_reset"
static var last_error := ""


static func encode(data: Dictionary) -> String:
	var payload := JSON.stringify(data, "", false)
	var header := {"format": FORMAT, "version": VERSION, "bytes": payload.to_utf8_buffer().size(), "md5": payload.md5_text()}
	return JSON.stringify(header, "", false) + "\n" + payload + "\n"


## Returns the payload Dictionary, or null when the text is not a valid save.
static func decode(text: String) -> Variant:
	var nl := text.find("\n")
	if nl <= 0:
		last_error = "no header"
		return null
	var hj := JSON.new()
	if hj.parse(text.substr(0, nl)) != OK or typeof(hj.data) != TYPE_DICTIONARY:
		last_error = "bad header"
		return null
	var header: Dictionary = hj.data
	if header.get("format", "") != FORMAT:
		last_error = "wrong format"
		return null
	var payload := text.substr(nl + 1).strip_edges(false, true)
	if payload.to_utf8_buffer().size() != int(header.get("bytes", -1)):
		last_error = "size mismatch (truncated?)"
		return null
	if payload.md5_text() != str(header.get("md5", "")):
		last_error = "checksum mismatch"
		return null
	var pj := JSON.new()
	if pj.parse(payload) != OK or typeof(pj.data) != TYPE_DICTIONARY:
		last_error = "bad payload"
		return null
	return pj.data


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func save_json(path: String, data: Dictionary) -> Error:
	var text := encode(data)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot open tmp: %s" % error_string(FileAccess.get_open_error())
		return ERR_CANT_OPEN
	f.store_string(text)
	f.flush()
	f.close()
	# verify what actually reached the disk before replacing anything
	if decode(_read(tmp)) == null:
		last_error = "tmp verify failed: " + last_error
		DirAccess.remove_absolute(_abs(tmp))
		return ERR_FILE_CORRUPT
	# keep the last good file as the backup slot
	if FileAccess.file_exists(path) and decode(_read(path)) != null:
		DirAccess.copy_absolute(_abs(path), _abs(path + ".bak"))
	var err := DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if err != OK:
		# some platforms refuse to rename over an existing file
		DirAccess.remove_absolute(_abs(path))
		err = DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if err != OK:
		last_error = "rename failed: %s" % error_string(err)
	return err


## {"ok": bool, "data": Dictionary, "source": "main"|"backup"|"none", "error": String}
static func load_json(path: String) -> Dictionary:
	last_error = ""
	# Phase 6: a lingering .tmp means a save was cut off before its rename. Every
	# save writes .tmp and renames it straight away, so a .tmp that passes the
	# checksum is always newer than main (power cut between verify and rename, or
	# between "remove the old main" and the rename on platforms that refuse to
	# rename over a file): promote it. A torn .tmp never finished: drop it.
	if FileAccess.file_exists(path + ".tmp"):
		var tdat: Variant = decode(_read(path + ".tmp"))
		if tdat != null:
			var main_ok := FileAccess.file_exists(path) and decode(_read(path)) != null
			if main_ok:
				DirAccess.copy_absolute(_abs(path), _abs(path + ".bak"))
			DirAccess.remove_absolute(_abs(path))
			DirAccess.rename_absolute(_abs(path + ".tmp"), _abs(path))
			last_status = "tmp"
			return {"ok": true, "data": tdat, "source": "tmp", "error": ""}
		DirAccess.remove_absolute(_abs(path + ".tmp"))
		last_error = ""
	var main_text := _read(path)
	var errors: Array[String] = []
	if main_text != "":
		var d: Variant = decode(main_text)
		if d != null:
			last_status = "main"
			return {"ok": true, "data": d, "source": "main", "error": ""}
		errors.append("main: " + last_error)
		# keep the damaged file for inspection, out of the way of the next save
		DirAccess.copy_absolute(_abs(path), _abs(path + ".corrupt"))
		DirAccess.remove_absolute(_abs(path))
	var bak_text := _read(path + ".bak")
	if bak_text != "":
		var b: Variant = decode(bak_text)
		if b != null:
			last_status = "backup"
			return {"ok": true, "data": b, "source": "backup", "error": "; ".join(errors)}
		errors.append("backup: " + last_error)
	last_status = "corrupt_reset" if not errors.is_empty() else "none"
	return {"ok": false, "data": {}, "source": "none", "error": "; ".join(errors)}


static func delete_all(path: String) -> void:
	for suf in ["", ".tmp", ".bak", ".corrupt"]:
		if FileAccess.file_exists(path + suf):
			DirAccess.remove_absolute(_abs(path + suf))
