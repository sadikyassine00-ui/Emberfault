shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// --- VISUAL LAYOUT ---
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Base tint color
uniform float glow_intensity : hint_range(10.0, 150.0) = 45.0;     // Emissive blowout power

// --- RECTANGLE DIMENSIONS ---
uniform float flash_length : hint_range(0.05, 0.5) = 0.15;          // Constant length of the block along the arc
uniform float max_width : hint_range(0.1, 1.0) = 0.40;              // Constant uniform thickness from outer edge inward

// Linked directly to your script duration timer
uniform float animation_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// UV.x = 0.0 (Outer reach) to 1.0 (Inner hands)
	// UV.y = 0.0 (Right start) to 1.0 (Left finish)
	
	// 1. Calculate the sliding window position along the arc length (UV.y)
	float total_range = 1.0 + flash_length;
	float lead_tip = animation_progress * total_range;
	float dist_behind_tip = lead_tip - UV.y;
	
	// Hard binary clip to establish the traveling block length
	float inside_window = step(0.0, dist_behind_tip) * step(dist_behind_tip, flash_length);
	
	// 2. THE UNIFORM RECTANGLE MASK
	// We drop all curve/taper multipliers. It checks against 'max_width' everywhere inside the window.
	// This forces the shape to be a perfect, uniform geometric block from front to back.
	float sharp_block_mask = step(UV.x, max_width) * inside_window;
	
	// 3. Uniform white-hot inner core for clean visual punch
	float white_core = step(UV.x, max_width * 0.25) * sharp_block_mask;
	vec3 final_rgb = mix(flash_color.rgb, vec3(1.0), white_core * 0.8);

	// --- OUTPUT ---
	ALBEDO = final_rgb * glow_intensity;
	ALPHA = sharp_block_mask * flash_color.a;
}