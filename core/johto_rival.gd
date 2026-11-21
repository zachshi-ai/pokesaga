extends RefCounted
## Crystal checks the local weekday when the player approaches the League corridor.
const LOBBY := "johto_indigo_plateau_pokecenter_1f"
static var local_date: Callable = Time.get_date_dict_from_system

static func date_key(date: Dictionary) -> String:
	return "%04d-%02d-%02d" % [date.year,date.month,date.day]

static func available(flags: Dictionary, date: Dictionary) -> bool:
	return flags.get("j2_rival_moon",false) and int(date.weekday) in [Time.WEEKDAY_MONDAY,Time.WEEKDAY_WEDNESDAY] and flags.get("j2_rival_day","") != date_key(date)

static func scene_flags(room: String, flags: Dictionary) -> Dictionary:
	if room == LOBBY:
		return flags.merged({"j2_rival_available":available(flags,local_date.call())},true)
	return flags
