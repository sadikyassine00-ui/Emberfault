shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;

uniform float bob_speed : hint_range(0.0, 10.0) = 3.5;
uniform float bob_height : hint_range(0.0, 2.0) = 0.25;

uniform float wiggle_speed : hint_range(0.0, 10.0) = 4.5;
uniform float wiggle_yaw : hint_range(0.0, 1.0) = 0.15;   
uniform float wiggle_roll : hint_range(0.0, 1.0) = 0.10;  

// Authoritative pipeline streams
instance uniform float hit_flash_intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform float attack_lunge_intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform float is_foreground = 0.0;

varying flat float hit_flash_varying;
varying flat float attack_lunge_varying;

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	float phase = world_pos.x * 0.35 + world_pos.y * 0.15 + world_pos.z * 0.35;
	
	// Safe domain wrapping to protect power-efficient mobile chipsets
	float safe_time = mod(TIME, 6.28318530718);
	
	// Gentle secondary ambient floating movement loops
	float bob = sin(safe_time * bob_speed + phase) * bob_height;

	float yaw_angle = sin(safe_time * wiggle_speed * 0.8 + phase) * wiggle_yaw;
	mat3 rot_y = mat3(
		vec3(cos(yaw_angle), 0.0, -sin(yaw_angle)),
		vec3(0.0, 1.0, 0.0),
		vec3(sin(yaw_angle), 0.0, cos(yaw_angle))
	);

	float roll_angle = cos(safe_time * wiggle_speed * 1.1 + phase) * wiggle_roll;
	mat3 rot_z = mat3(
		vec3(cos(roll_angle), -sin(roll_angle), 0.0),
		vec3(sin(roll_angle), cos(roll_angle), 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	VERTEX = rot_z * (rot_y * VERTEX);
	VERTEX.y += bob;
	NORMAL = rot_z * (rot_y * NORMAL);

	// Surgically isolate low-level driver buffer bleeding
	float raw_flash = mix(INSTANCE_CUSTOM.x, hit_flash_intensity, is_foreground);
	hit_flash_varying = raw_flash;

	float raw_lunge = mix(INSTANCE_CUSTOM.y, attack_lunge_intensity, is_foreground);
	attack_lunge_varying = raw_lunge;

	// Smooth linear lunge translation offsets
	if (raw_lunge > 0.0) {
		float lunge_arc = sin(raw_lunge * 3.141592);
		VERTEX.z -= lunge_arc * 0.75;
		VERTEX.y -= lunge_arc * 0.15;
	}
}

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	vec3 base_col = tex_color.rgb * albedo.rgb;
	
	if (COLOR.rgb != vec3(1.0)) {
		base_col *= COLOR.rgb;
	}
	
	// Surgical color interpolation: Blends clean solid white over texture base map
	ALBEDO = mix(base_col, vec3(1.0), hit_flash_varying);
	
	// High-end HDR emissive bloom responses
	vec3 white_hit_emission = vec3(1.0) * hit_flash_varying * 2.5;
	vec3 plasma_attack_emission = vec3(1.0, 0.22, 0.0) * attack_lunge_varying * 3.5;
	
	EMISSION = white_hit_emission + plasma_attack_emission;
	
	METALLIC = mix(metallic, 0.0, max(hit_flash_varying, attack_lunge_varying));
	ROUGHNESS = mix(roughness, 1.0, max(hit_flash_varying, attack_lunge_varying));
}