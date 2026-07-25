shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled;

// --- WAVY TWISTING WIND SHADER FOR 2-LINE PNG TEXTURE ---
group_uniforms WindTexture;
uniform sampler2D wind_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 wind_color : source_color = vec4(0.9, 0.96, 1.0, 0.65);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);

group_uniforms WavyDeformation;
uniform float wave_speed : hint_range(0.0, 30.0) = 10.0;
uniform float wave_frequency : hint_range(0.5, 20.0) = 6.0;
uniform float wave_amplitude : hint_range(0.0, 0.2) = 0.045;
uniform float twist_intensity : hint_range(0.0, 0.2) = 0.025;

varying flat float instance_seed;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void vertex() {
	instance_seed = float(INSTANCE_ID);
	
	// Particle Billboard facing camera in isometric view without rotation
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	// Vertex-level subtle wavy flex along Y
	float rand_phase = hash(instance_seed) * 6.28318;
	float v_wave = sin((UV.x * wave_frequency) + (TIME * wave_speed) + rand_phase) * wave_amplitude;
	VERTEX.y += v_wave * sin(UV.x * 3.14159);
}

void fragment() {
	float rand_phase = hash(instance_seed) * 6.28318;
	
	// Dynamic S-curve wave distortion on UV coordinates
	float primary_wave = sin((UV.x * wave_frequency) + (TIME * wave_speed) + rand_phase) * wave_amplitude;
	float secondary_wave = cos((UV.x * wave_frequency * 2.3) - (TIME * wave_speed * 1.4) + rand_phase * 1.5) * twist_intensity;
	
	// Pin distortion at UV ends so line tips remain sharp
	float pin_tips = sin(UV.x * 3.14159);
	float total_uv_offset = (primary_wave + secondary_wave) * pin_tips;

	// Apply wavy twist offset to UV.y
	vec2 distorted_uv = vec2(UV.x, UV.y + total_uv_offset);
	vec4 tex_color = texture(wind_texture, distorted_uv);

	// Extract white line brightness for alpha mask
	float line_brightness = max(tex_color.r, max(tex_color.g, tex_color.b));
	float line_alpha = pow(line_brightness, 1.1);

	// Soft fade-out at the extreme left/right edges of the quad
	float fade_x = sin(clamp(UV.x, 0.0, 1.0) * 3.14159);
	float fade_y = sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
	float edge_mask = fade_x * fade_y;

	// Core glow & color mixing
	vec3 final_rgb = mix(wind_color.rgb, core_color.rgb, line_brightness * 0.7);

	ALBEDO = final_rgb;
	ALPHA = clamp(line_alpha * edge_mask * wind_color.a * COLOR.a, 0.0, 1.0);
}