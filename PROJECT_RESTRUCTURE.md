# PROJECT_RESTRUCTURE.md
## Voxel-Hearth — Architectural Restructure Complete
### Completed: 2026-06-14

This file documents the new feature-based architecture adopted for this project.

## New Directory Structure

```
res://
├── actors/
│   ├── player/      -> player.tscn, player_controller.gd, Axyl.tscn, visuals_controller.gd
│   └── enemies/     -> active_enemy.tscn/.gd, enemy.tscn, enemy_controller.gd, enemy_stats.gd, base_enemy_stats.tres
├── components/      -> movement_component.gd
├── systems/
│   ├── camera/      -> camera_manager.gd, explore_cam_1.tscn
│   ├── spawning/    -> director.gd, horde_manager.gd, spawn_manager.gd, enemy_pool.gd, swarm_director.gd
│   └── test/        -> enemy_damage_test.gd, mouse_destruction.gd, fps_counter.gd, camera_test.tscn
├── levels/
│   ├── hub/         -> hub.tscn  (MAIN SCENE)
│   └── world/       -> world.tscn
├── voxel/
│   └── materials/   -> master_material.tres
├── ui/              -> debug_ui.gd, camera_transition_fade.gd, camera_transition_screen.tscn
└── assets/
    ├── characters/
    │   ├── axyl/    -> all Axyl .obj/.png/.mtl meshes, palette.tres files, axyl.glb
    │   └── cuby/    -> simple_cube.tscn/.obj/.png, cube_mesh.tres
    ├── animations/  -> Idle.res, Jump.res, Jump_Land.res, Jump_Start.res, Sprint.res, UAL1_Standard.glb
    ├── heightmaps/  -> Mountain.png/jpeg
    ├── tiles/       -> tiles-0 through tiles-8 (.obj/.png/.mtl)
    ├── materials/   -> floor.tres
    └── sky/         -> sky_115_2k.png
```

## DO NOT MOVE
- `addons/` — Godot plugin discovery is path-sensitive
- `Resources/Data/` — Terrain3D binary chunk data
- `project.godot` — Root config
