extends RefCounted
## The actual source_script of each shelf chooses its book. Paired sides share a volume.
const PREFIX := "CanalaveLibrary3F_"
static var catalog: Dictionary = {}

static func _data() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/library.json"))
	return catalog

static func talk(g, npc: Dictionary) -> bool:
	if npc.get("source_script","") != "CanalaveLibrary1F_Receptionist":
		return false
	var aftermath := 1 if g._flags().get("s_library",false) else 0
	g._dialog(_data().reception[aftermath], "图书管理员")
	return true

static func shelf(g, obj: Dictionary) -> bool:
	var source := str(obj.get("source_script",""))
	if source == "CanalaveLibrary2F_Bookshelves":
		g._dialog(_data().shelves_2f)
		return true
	if not source.begins_with(PREFIX):
		return false
	var title := source.trim_prefix(PREFIX)
	if title == "SinnohFolkStories":
		var folk: Dictionary = _data().folk
		g._dialog(folk.open).closed.connect(func():
			var back := func(): g._dialog(folk.back)
			g._pick(folk.question, ["其一","其二","其三","放回书架"], func(i: int):
				if i < folk.stories.size(): g._dialog(folk.stories[i])
				else: back.call()
			,back))
		return true
	if not _data().books.has(title):
		return false
	var book: Dictionary = catalog.books[title]
	_ask(g,book.open,"阅读",book,0)
	return true

static func _ask(g, lines: Array, yes: String, book: Dictionary, chapter: int) -> void:
	var dlg = g._dialog(lines)
	dlg.ask(yes,"放回")
	dlg.answered.connect(func(read_on: bool):
		if read_on: _read(g,book,chapter)
		else: g._dialog(book.back))

static func _read(g, book: Dictionary, chapter: int) -> void:
	var pages: Array = book.chapters[chapter]
	if chapter + 1 == book.chapters.size():
		g._dialog(pages)
		return
	# Original long volumes end the first two sections with a separate continuation
	# question. Finish the section before any answer buttons can be activated.
	g._dialog(pages.slice(0,-1)).closed.connect(func():
		_ask(g,[pages.back()],"继续阅读",book,chapter+1))
