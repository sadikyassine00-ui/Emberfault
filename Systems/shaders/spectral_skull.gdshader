shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- ⚙️ SPECTRAL SWARM TUNING ---
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;

uniform float bob_speed : hint_range(0.0, 10.0) = 3.5;
uniform float bob_height : hint_range(0.0, 2.0) = 0.25;

uniform float wiggle_speed : hint_range(0.0, 10.0) = 4.5;
uniform float wiggle_yaw : hint_range(0.0, 1.0) = 0.15;   // Tilt left/right
uniform float wiggle_roll : hint_range(0.0, 1.0) = 0.10;  // Lean side-to-side

void vertex() {
	// Extract the unique world position coordinates of the current entity
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	
	// ⚡ SMOOTH SPATIAL COUPLING: 
	// We use a low-frequency linear combinations of their coordinates.
	// This changes continuously as they move, creating a smooth Doppler frequency shift 
	// instead of high-frequency shaking.
	float phase = world_pos.x * 0.35 + world_pos.y * 0.15 + world_pos.z * 0.35;

	// 1. Vertical Altitude Bobbing (Sine translation)
	float bob = sin(TIME * bob_speed + phase) * bob_height;

	// 2. Yaw Wiggle (Rotation around Local Y-Axis)
	float yaw_angle = sin(TIME * wiggle_speed * 0.8 + phase) * wiggle_yaw;
	mat3 rot_y = mat3(
		vec3(cos(yaw_angle), 0.0, -sin(yaw_angle)),
		vec3(0.0, 1.0, 0.0),
		vec3(sin(yaw_angle), 0.0, cos(yaw_angle))
	);

	// 3. Roll Leaning (Rotation around Local Z-Axis)
	float roll_angle = cos(TIME * wiggle_speed * 1.1 + phase) * wiggle_roll;
	mat3 rot_z = mat3(
		vec3(cos(roll_angle), -sin(roll_angle), 0.0),
		vec3(sin(roll_angle), cos(roll_angle), 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	// Apply rotations locally first, then apply vertical float displacement
	VERTEX = rot_z * (rot_y * VERTEX);
	VERTEX.y += bob;
	
	// Keep normals aligned with the new vertex rotations
	NORMAL = rot_z * (rot_y * NORMAL);
}

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	ALBEDO = tex_color.rgb * albedo.rgb;
	
	if (COLOR.rgb != vec3(1.0)) {
		ALBEDO *= COLOR.rgb;
	}
	
	METALLIC = metallic;
	ROUGHNESS = roughness;
}