extends Resource
class_name ItemData

enum Category {
	RESOURCES = 0,
	CONSUMABLES = 1,
	EQUIPMENT = 2,
	QUEST = 3
}

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: Category = Category.RESOURCES
@export var max_stack: int = 99
@export var custom_stats: Dictionary = {}
