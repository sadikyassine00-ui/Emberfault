extends Node
class_name WeaponCoreManager

signal core_equipped(slot: WeaponCoreData.SlotType, core_data: WeaponCoreData)

# Slot storage: SlotType -> WeaponCoreData
var equipped_cores: Dictionary = {
	WeaponCoreData.SlotType.SLOT_1_PRIMARY: null,
	WeaponCoreData.SlotType.SLOT_2_FINISHER: null,
	WeaponCoreData.SlotType.SLOT_3_DASH: null
}

func equip_core(core: WeaponCoreData) -> void:
	if not core:
		return
	equipped_cores[core.slot] = core
	core_equipped.emit(core.slot, core)

func get_equipped_core(slot: WeaponCoreData.SlotType) -> WeaponCoreData:
	return equipped_cores.get(slot, null)

# --- Slot 1: Primary Attack Modifiers ---
func get_primary_damage_multiplier() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_1_PRIMARY, null)
	if core:
		return 1.0 + core.primary_damage_bonus_pct
	return 1.0

func get_primary_arc_bonus() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_1_PRIMARY, null)
	if core:
		return core.primary_arc_bonus_deg
	return 0.0

func get_primary_lifesteal() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_1_PRIMARY, null)
	if core:
		return core.primary_lifesteal_amount
	return 0.0

# --- Slot 2: Finisher Attack Modifiers ---
func get_finisher_damage_multiplier() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_2_FINISHER, null)
	if core:
		return 1.0 + core.finisher_damage_bonus_pct
	return 1.0

func get_shockwave_radius_multiplier() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_2_FINISHER, null)
	if core:
		return core.shockwave_radius_mult
	return 1.0

func get_pull_radius() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_2_FINISHER, null)
	if core:
		return core.pull_enemies_radius
	return 0.0

# --- Slot 3: Dash / Utility Modifiers ---
func get_dash_speed_multiplier() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_3_DASH, null)
	if core:
		return 1.0 + core.dash_speed_bonus_pct
	return 1.0

func get_dash_cooldown_multiplier() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_3_DASH, null)
	if core:
		return maxf(0.1, 1.0 - core.dash_cooldown_reduction_pct)
	return 1.0

func has_dash_trail() -> bool:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_3_DASH, null)
	if core:
		return core.dash_trail_damage > 0.0
	return false

func get_dash_trail_damage() -> float:
	var core: WeaponCoreData = equipped_cores.get(WeaponCoreData.SlotType.SLOT_3_DASH, null)
	if core:
		return core.dash_trail_damage
	return 0.0
