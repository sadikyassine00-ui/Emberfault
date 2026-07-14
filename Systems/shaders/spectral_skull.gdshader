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

instance uniform float hit_flash_intensity : hint_range(0.0, 1.0) = 0.0;
varying flat float hit_flash_varying;

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	float phase = world_pos.x * 0.35 + world_pos.y * 0.15 + world_pos.z * 0.35;

	float bob = sin(TIME * bob_speed + phase) * bob_height;
	float yaw_angle = sin(TIME * wiggle_speed * 0.8 + phase) * wiggle_yaw;
	mat3 rot_y = mat3(
		vec3(cos(yaw_angle), 0.0, -sin(yaw_angle)),
		vec3(0.0, 1.0, 0.0),
		vec3(sin(yaw_angle), 0.0, cos(yaw_angle))
	);

	float roll_angle = cos(TIME * wiggle_speed * 1.1 + phase) * wiggle_roll;
	mat3 rot_z = mat3(
		vec3(cos(roll_angle), -sin(roll_angle), 0.0),
		vec3(sin(roll_angle), cos(roll_angle), 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	VERTEX = rot_z * (rot_y * VERTEX);
	VERTEX.y += bob;
	NORMAL = rot_z * (rot_y * NORMAL);

	float raw_flash = max(INSTANCE_CUSTOM.x, hit_flash_intensity);
	hit_flash_varying = raw_flash;

	if (raw_flash > 0.0) {
		float shake_speed = 150.0;
		float shake_magnitude = 0.45; 
		vec3 jitter = vec3(
			sin(TIME * shake_speed + world_pos.x * 12.0),
			sin(TIME * (shake_speed * 1.4) + world_pos.y * 8.0) * 0.4,
			cos(TIME * shake_speed + world_pos.z * 12.0)
		) * raw_flash * shake_magnitude;
		VERTEX += jitter;
	}
}

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	vec3 base_col = tex_color.rgb * albedo.rgb;
	
	if (COLOR.rgb != vec3(1.0)) {
		base_col *= COLOR.rgb;
	}
	
	ALBEDO = mix(base_col, vec3(1.0), hit_flash_varying);
	
	// ⚡ TUNED EMISSION: Dropped to 2.0 for a clean glow instead of a blinding wash
	EMISSION = vec3(1.0) * hit_flash_varying * 2.0; 
	
	METALLIC = mix(metallic, 0.0, hit_flash_varying);
	ROUGHNESS = mix(roughness, 1.0, hit_flash_varying);
}