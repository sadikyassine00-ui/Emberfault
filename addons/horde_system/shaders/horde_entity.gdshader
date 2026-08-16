shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Configurable Colors ---
uniform vec4 base_color : source_color = vec4(0.72, 0.72, 0.72, 1.0);    // Light grey (unpromoted swarm)
uniform vec4 promoted_color : source_color = vec4(1.0, 0.85, 0.0, 1.0);  // Yellow (promoted/close)
uniform vec4 hit_flash_color : source_color = vec4(1.0, 0.15, 0.15, 1.0); // Red flash on hit
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float metallic  : hint_range(0.0, 1.0) = 0.05;

// --- Per-instance parameters (used by promoted Node3D meshes) ---
instance uniform float is_foreground = 0.0;       // 1.0 when this is a promoted node
instance uniform float hit_flash_intensity = 0.0;
instance uniform float attack_lunge_intensity = 0.0;

// Passed from vertex to fragment — carries MultiMesh INSTANCE_CUSTOM data
varying float v_hit_flash;
varying float v_attack_lunge;
varying float v_is_promoted;

void vertex() {
	// INSTANCE_CUSTOM.x = hit flash, .y = attack lunge, .z = is_promoted flag
	v_hit_flash   = mix(INSTANCE_CUSTOM.x, hit_flash_intensity, is_foreground);
	v_attack_lunge = mix(INSTANCE_CUSTOM.y, attack_lunge_intensity, is_foreground);
	v_is_promoted  = mix(INSTANCE_CUSTOM.z, is_foreground, is_foreground);

}

void fragment() {
	// Pick base or promoted color depending on promotion state
	vec3 color = mix(base_color.rgb, promoted_color.rgb, v_is_promoted);

	// Layer on attack lunge tint (orange)
	color = mix(color, vec3(1.0, 0.55, 0.1), v_attack_lunge * 0.45);

	// Layer on hit flash (red→white)
	color = mix(color, hit_flash_color.rgb, v_hit_flash);

	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = hit_flash_color.rgb * v_hit_flash * 0.6;
}
