shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// filter_nearest keeps your Aseprite pixel art perfectly sharp on the mesh
uniform sampler2D slash_texture : source_color, filter_nearest;
uniform vec4 base_color : source_color = vec4(1.0, 0.84, 0.35, 1.0);
uniform float glow_intensity : hint_range(1.0, 10.0) = 4.0;

// 0.0 = completely hidden, 1.0 = fully rolled out along the arc
uniform float sweep_progress : hint_range(0.0, 1.0) = 1.0;
// 0.0 = fully solid, 1.0 = completely dissolved from back to front
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Sample your continuous Aseprite artwork sheet
	vec4 tex = texture(slash_texture, UV);
	
	// STEP 1: Front-facing rollout mask (Wipes visibility from 0 to 1)
	float rollout_mask = step(UV.x, sweep_progress);
	
	// STEP 2: Back-to-Front sequential dissolve mask
	// As dissolve_progress goes up, it starts cutting off the lowest UV.x values first
	float dissolve_mask = smoothstep(dissolve_progress, dissolve_progress + 0.15, UV.x);
	
	// Combine the math profiles
	float final_alpha = tex.a * base_color.a * rollout_mask * dissolve_mask;
	
	// Output high intensity HDR color straight into Godot's Bloom processor
	ALBEDO = tex.rgb * base_color.rgb * glow_intensity;
	ALPHA = final_alpha;
	
	if (ALPHA < 0.001) {
		discard;
	}
}