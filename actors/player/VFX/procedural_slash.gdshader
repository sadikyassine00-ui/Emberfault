shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D slash_texture : source_color, filter_nearest;
uniform sampler2D color_gradient : source_color, filter_linear;
uniform float glow_intensity : hint_range(1.0, 30.0) = 1.8;

uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float border_glow_intensity : hint_range(1.0, 30.0) = 8.0;
uniform float border_thickness : hint_range(0.05, 0.4) = 0.15;

uniform float shine_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shine_glow_intensity : hint_range(1.0, 30.0) = 30.0;
uniform float shine_thickness : hint_range(0.01, 0.6) = 0.28;

uniform float element_enabled : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D element_texture : source_color, filter_linear;
uniform sampler2D element_gradient : source_color, filter_linear;
uniform float element_glow_intensity : hint_range(1.0, 30.0) = 4.0;
uniform float element_scroll_speed = -4.5;

uniform sampler2D warp_noise_texture : hint_default_white, filter_linear, repeat_enable;
uniform float warp_strength : hint_range(0.0, 0.3) = 0.08;
uniform vec2 warp_scroll_speed = vec2(-2.0, 0.5);

uniform float sweep_progress : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 warp_uv = UV + (TIME * warp_scroll_speed);
	vec4 noise_sample = texture(warp_noise_texture, warp_uv);
	vec2 uv_displacement = (noise_sample.rg - 0.5) * warp_strength;
	
	vec2 distorted_global_uv = UV + uv_displacement;

	float vertical_container_mask = smoothstep(0.02, 0.16, distorted_global_uv.y) * smoothstep(0.98, 0.84, distorted_global_uv.y);
	float horizontal_container_mask = smoothstep(0.0, 0.15, distorted_global_uv.x) * smoothstep(1.0, 0.85, distorted_global_uv.x);
	float boundary_envelope = vertical_container_mask * horizontal_container_mask;

	float eased_shine_t = 1.0 - (1.0 - shine_progress) * (1.0 - shine_progress);

	vec2 centered_base_uv = distorted_global_uv;
	centered_base_uv.y = (distorted_global_uv.y - 0.15) / 0.70;
	
	vec4 base_tex = vec4(0.0);
	if (centered_base_uv.y >= 0.0 && centered_base_uv.y <= 1.0) {
		base_tex = texture(slash_texture, centered_base_uv);
	}
	
	vec4 base_grad = texture(color_gradient, vec2(distorted_global_uv.x, 0.5));
	
	float spatial_glow_multiplier = mix(0.40, 1.0, smoothstep(0.1, 0.9, distorted_global_uv.x));
	vec3 base_final_rgb = base_tex.rgb * base_grad.rgb * (glow_intensity * spatial_glow_multiplier);
	float base_final_alpha = base_tex.a * base_grad.a * boundary_envelope;

	float outer_edge_mask = smoothstep(0.02, 0.08, base_tex.a);
	float inner_edge_mask = 1.0 - smoothstep(0.08, 0.08 + border_thickness, base_tex.a);
	float contour_rim = outer_edge_mask * inner_edge_mask;
	
	vec3 border_grad_mod = mix(base_grad.rgb, vec3(1.0), 0.5); 
	vec3 border_composite_rgb = border_color.rgb * border_grad_mod * border_glow_intensity * contour_rim * boundary_envelope;

	float shine_center = mix(-0.35, 1.35, eased_shine_t);
	float shine_dist = abs(distorted_global_uv.x - shine_center);
	float raw_shine_mask = smoothstep(shine_thickness, 0.0, shine_dist);
	float sharp_glare_line = pow(raw_shine_mask, 1.5) * vertical_container_mask;
	
	vec3 shine_rgb = vec3(1.0, 1.0, 1.0) * shine_glow_intensity * sharp_glare_line * (1.0 - shine_progress) * boundary_envelope;

	vec2 element_uv = vec2(distorted_global_uv.x + TIME * element_scroll_speed, distorted_global_uv.y);
	vec4 element_tex = texture(element_texture, element_uv);
	vec4 element_grad = texture(element_gradient, vec2(distorted_global_uv.x, 0.5));
	
	float core_dimming_mask = 1.0 - (base_tex.a * 0.85);
	vec3 element_final_rgb = element_tex.rgb * element_grad.rgb * (element_glow_intensity * spatial_glow_multiplier) * element_enabled;
	float element_final_alpha = element_tex.a * element_grad.a * element_enabled * boundary_envelope * core_dimming_mask;

	float rollout_mask = step(distorted_global_uv.x, sweep_progress);
	float dissolve_mask = smoothstep(dissolve_progress, dissolve_progress + 0.12, distorted_global_uv.x);
	
	ALBEDO = base_final_rgb + element_final_rgb + shine_rgb + border_composite_rgb;
	ALPHA = max(max(max(base_final_alpha, element_final_alpha), contour_rim), sharp_glare_line) * rollout_mask * dissolve_mask;

	if (ALPHA < 0.01) {
		discard;
	}
}