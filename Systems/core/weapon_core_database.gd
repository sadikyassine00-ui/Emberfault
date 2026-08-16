extends RefCounted
class_name WeaponCoreDatabase

static var _all_cores: Array[WeaponCoreData] = []

static func get_all_cores() -> Array[WeaponCoreData]:
	if _all_cores.is_empty():
		_initialize_default_cores()
	return _all_cores

static func get_random_draft_choices(count: int = 3) -> Array[WeaponCoreData]:
	var cores := get_all_cores()
	if cores.size() < count:
		return cores.duplicate()

	# Group by slot to present 1 choice per slot (Slot 1, Slot 2, Slot 3)
	var slot1_cores: Array[WeaponCoreData] = []
	var slot2_cores: Array[WeaponCoreData] = []
	var slot3_cores: Array[WeaponCoreData] = []

	for c in cores:
		match c.slot:
			WeaponCoreData.SlotType.SLOT_1_PRIMARY:
				slot1_cores.append(c)
			WeaponCoreData.SlotType.SLOT_2_FINISHER:
				slot2_cores.append(c)
			WeaponCoreData.SlotType.SLOT_3_DASH:
				slot3_cores.append(c)

	var selection: Array[WeaponCoreData] = []

	if count == 3 and not slot1_cores.is_empty() and not slot2_cores.is_empty() and not slot3_cores.is_empty():
		slot1_cores.shuffle()
		slot2_cores.shuffle()
		slot3_cores.shuffle()
		selection.append(slot1_cores[0])
		selection.append(slot2_cores[0])
		selection.append(slot3_cores[0])
		return selection

	# Fallback random distinct selection
	var pool := cores.duplicate()
	pool.shuffle()
	return pool.slice(0, count)

static func _initialize_default_cores() -> void:
	_all_cores.clear()

	# Load .tres Resource files from res://Resources/weapon_cores/
	var dir := DirAccess.open("res://Resources/weapon_cores/")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var core_res := load("res://Resources/weapon_cores/" + file_name) as WeaponCoreData
				if core_res:
					_all_cores.append(core_res)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Fallback preloads if directory scan returns empty
	if _all_cores.is_empty():
		_all_cores.append(preload("res://Resources/weapon_cores/heavy_kinetic_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/wide_cleave_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/vampiric_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/seismic_shockwave_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/gravitational_vortex_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/thunder_burst_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/chrono_thruster_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/infernal_trail_core.tres"))
		_all_cores.append(preload("res://Resources/weapon_cores/aether_slip_core.tres"))
