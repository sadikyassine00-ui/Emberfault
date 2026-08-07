extends Resource
class_name WeaponCoreData

enum SlotType {
	SLOT_1_PRIMARY = 1, # Modifies Attack 1 & 2
	SLOT_2_FINISHER = 2, # Modifies Attack 3
	SLOT_3_DASH = 3      # Modifies Dash / Utility
}

enum Rarity {
	COMMON,
	RARE,
	EPIC,
	LEGENDARY
}

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var slot: SlotType = SlotType.SLOT_1_PRIMARY
@export var rarity: Rarity = Rarity.COMMON

# Color accents for UI cards & VFX
@export var accent_color: Color = Color(0.2, 0.8, 1.0, 1.0)

# Gameplay Modifiers
@export_group("Attack 1 & 2 Modifiers (Slot 1)")
@export var primary_damage_bonus_pct: float = 0.0
@export var primary_stagger_force: float = 0.0
@export var primary_arc_bonus_deg: float = 0.0
@export var primary_lifesteal_amount: float = 0.0

@export_group("Attack 3 Finisher Modifiers (Slot 2)")
@export var finisher_damage_bonus_pct: float = 0.0
@export var shockwave_radius_mult: float = 1.0
@export var pull_enemies_radius: float = 0.0
@export var finisher_knockback_bonus: float = 0.0

@export_group("Dash / Utility Modifiers (Slot 3)")
@export var dash_speed_bonus_pct: float = 0.0
@export var dash_cooldown_reduction_pct: float = 0.0
@export var dash_trail_damage: float = 0.0
@export var dash_invincibility_bonus: float = 0.0

# Optional path for custom logic/extensibility
@export var custom_script_path: String = ""

func get_slot_name() -> String:
	match slot:
		SlotType.SLOT_1_PRIMARY:
			return "SLOT 1: ATTACK 1 & 2"
		SlotType.SLOT_2_FINISHER:
			return "SLOT 2: ATTACK 3"
		SlotType.SLOT_3_DASH:
			return "SLOT 3: DASH / UTILITY"
		_:
			return "UNKNOWN SLOT"

func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON:
			return "COMMON"
		Rarity.RARE:
			return "RARE"
		Rarity.EPIC:
			return "EPIC"
		Rarity.LEGENDARY:
			return "LEGENDARY"
		_:
			return "COMMON"

func get_rarity_color() -> Color:
	match rarity:
		Rarity.COMMON:
			return Color(0.7, 0.75, 0.8, 1.0)
		Rarity.RARE:
			return Color(0.2, 0.65, 1.0, 1.0)
		Rarity.EPIC:
			return Color(0.75, 0.3, 0.95, 1.0)
		Rarity.LEGENDARY:
			return Color(1.0, 0.75, 0.15, 1.0)
		_:
			return Color.WHITE
