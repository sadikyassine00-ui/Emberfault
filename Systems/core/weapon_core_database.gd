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

	# --- SLOT 1: ATTACK 1 & 2 MODIFIERS ---
	var c1 = WeaponCoreData.new()
	c1.id = "core_heavy_impact"
	c1.title = "Heavy Kinetic Core"
	c1.description = "Modifies Attack 1 & 2:\n+30% Primary Damage and adds heavy knockback stagger on hit."
	c1.slot = WeaponCoreData.SlotType.SLOT_1_PRIMARY
	c1.rarity = WeaponCoreData.Rarity.RARE
	c1.icon = preload("res://Art/icons/Sprites/200%/Sword_0.png")
	c1.primary_damage_bonus_pct = 0.30
	c1.primary_stagger_force = 5.0
	c1.accent_color = Color(0.95, 0.45, 0.2, 1.0)
	_all_cores.append(c1)

	var c2 = WeaponCoreData.new()
	c2.id = "core_wide_cleave"
	c2.title = "Wide Cleave Core"
	c2.description = "Modifies Attack 1 & 2:\nExpands strike arc by +45 degrees, cleaving through wide enemy hordes."
	c2.slot = WeaponCoreData.SlotType.SLOT_1_PRIMARY
	c2.rarity = WeaponCoreData.Rarity.EPIC
	c2.icon = preload("res://Art/icons/Sprites/200%/Sword_7.png")
	c2.primary_damage_bonus_pct = 0.15
	c2.primary_arc_bonus_deg = 45.0
	c2.accent_color = Color(0.2, 0.85, 0.5, 1.0)
	_all_cores.append(c2)

	var c3 = WeaponCoreData.new()
	c3.id = "core_vampiric_edge"
	c3.title = "Vampiric Core"
	c3.description = "Modifies Attack 1 & 2:\nPrimary hits restore 4 HP per enemy struck."
	c3.slot = WeaponCoreData.SlotType.SLOT_1_PRIMARY
	c3.rarity = WeaponCoreData.Rarity.LEGENDARY
	c3.icon = preload("res://Art/icons/Sprites/200%/Rune_9.png")
	c3.primary_lifesteal_amount = 4.0
	c3.accent_color = Color(0.9, 0.15, 0.35, 1.0)
	_all_cores.append(c3)

	# --- SLOT 2: ATTACK 3 (FINISHER) MODIFIERS ---
	var c4 = WeaponCoreData.new()
	c4.id = "core_seismic_slam"
	c4.title = "Seismic Shockwave Core"
	c4.description = "Modifies Attack 3:\nFinisher slam radius is increased (1.8x) and deals +50% heavy damage."
	c4.slot = WeaponCoreData.SlotType.SLOT_2_FINISHER
	c4.rarity = WeaponCoreData.Rarity.EPIC
	c4.icon = preload("res://Art/icons/Sprites/200%/Skill_14.png")
	c4.finisher_damage_bonus_pct = 0.50
	c4.shockwave_radius_mult = 1.8
	c4.finisher_knockback_bonus = 8.0
	c4.accent_color = Color(1.0, 0.6, 0.1, 1.0)
	_all_cores.append(c4)

	var c5 = WeaponCoreData.new()
	c5.id = "core_vortex_taunt"
	c5.title = "Gravitational Vortex Core"
	c5.description = "Modifies Attack 3:\nFinisher slam pulls all surrounding enemies toward you before crushing them."
	c5.slot = WeaponCoreData.SlotType.SLOT_2_FINISHER
	c5.rarity = WeaponCoreData.Rarity.LEGENDARY
	c5.icon = preload("res://Art/icons/Sprites/200%/Skill_5.png")
	c5.finisher_damage_bonus_pct = 0.25
	c5.pull_enemies_radius = 8.0
	c5.accent_color = Color(0.65, 0.2, 0.95, 1.0)
	_all_cores.append(c5)

	var c6 = WeaponCoreData.new()
	c6.id = "core_thunder_burst"
	c6.title = "Thunder Burst Core"
	c6.description = "Modifies Attack 3:\nFinisher slam releases a high-voltage shockwave."
	c6.slot = WeaponCoreData.SlotType.SLOT_2_FINISHER
	c6.rarity = WeaponCoreData.Rarity.RARE
	c6.icon = preload("res://Art/icons/Sprites/200%/Rune_2.png")
	c6.finisher_damage_bonus_pct = 0.35
	c6.shockwave_radius_mult = 1.3
	c6.accent_color = Color(0.2, 0.75, 1.0, 1.0)
	_all_cores.append(c6)

	# --- SLOT 3: DASH / UTILITY MODIFIERS ---
	var c7 = WeaponCoreData.new()
	c7.id = "core_overclock_dash"
	c7.title = "Chrono Thruster Core"
	c7.description = "Modifies Dash:\n+50% Dash speed and reduces dash cooldown by 30%."
	c7.slot = WeaponCoreData.SlotType.SLOT_3_DASH
	c7.rarity = WeaponCoreData.Rarity.RARE
	c7.icon = preload("res://Art/icons/Sprites/200%/Skill_1.png")
	c7.dash_speed_bonus_pct = 0.50
	c7.dash_cooldown_reduction_pct = 0.30
	c7.accent_color = Color(0.1, 0.9, 0.9, 1.0)
	_all_cores.append(c7)

	var c8 = WeaponCoreData.new()
	c8.id = "core_blaze_trail"
	c8.title = "Infernal Trail Core"
	c8.description = "Modifies Dash:\nLeaves a scorching ember trail behind your dash that burns pursuing foes."
	c8.slot = WeaponCoreData.SlotType.SLOT_3_DASH
	c8.rarity = WeaponCoreData.Rarity.EPIC
	c8.icon = preload("res://Art/icons/Sprites/200%/Other_38.png")
	c8.dash_trail_damage = 15.0
	c8.accent_color = Color(1.0, 0.25, 0.1, 1.0)
	_all_cores.append(c8)

	var c9 = WeaponCoreData.new()
	c9.id = "core_phantom_dodge"
	c9.title = "Aether Slip Core"
	c9.description = "Modifies Dash:\nGrants extended invincibility during dash and +30% dash speed."
	c9.slot = WeaponCoreData.SlotType.SLOT_3_DASH
	c9.rarity = WeaponCoreData.Rarity.LEGENDARY
	c9.icon = preload("res://Art/icons/Sprites/200%/Rune_5.png")
	c9.dash_speed_bonus_pct = 0.30
	c9.dash_invincibility_bonus = 0.15
	c9.accent_color = Color(0.4, 1.0, 0.7, 1.0)
	_all_cores.append(c9)
