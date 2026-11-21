extends RefCounted
## Shared rooms use the player's entrance to select a return floor or ferry berth.
## A valid fixed destination on every door also lets older saves leave the room.

static func resolve(save: Dictionary, target: Dictionary) -> Dictionary:
	var mark: Dictionary = target.get("remember_passage", {})
	if not mark.is_empty():
		var history: Dictionary = save.get("return_passages", {})
		history[String(mark.key)] = mark.destination.duplicate(true)
		save["return_passages"] = history
	var key := String(target.get("recall_passage", ""))
	if not key.is_empty():
		var history: Dictionary = save.get("return_passages", {})
		var stored: Dictionary = history.get(key, {})
		if stored.has("region") and stored.has("map") and stored.get("at") is Array and stored.at.size() == 2:
			return stored
	return target
