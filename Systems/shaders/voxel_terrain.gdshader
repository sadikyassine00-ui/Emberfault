shader_type spatial;
// Strictly blocks specular pass overhead to guarantee a locked 60 FPS on integrated GPUs
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

group_uniforms Texturing;
uniform sampler2D texture_atlas : source_color, filter_nearest, repeat_disable;

group_uniforms Depth_Pop;
uniform float edge_pop : hint_range(0.0, 1.0) = 0.15;
uniform float side_shade : hint_range(0.0, 1.0) = 0.1;

group_uniforms Procedural_Emission;
uniform float emit_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float emit_energy : hint_range(0.0, 16.0) = 3.0;

group_uniforms AAA_Readability_Engine;
uniform vec4 voxel_edge_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float voxel_edge_visible : hint_range(0.0, 10.0) = 2.5;
uniform float voxel_edge_thickness : hint_range(0.005, 0.1) = 0.03;
uniform float voxel_scale : hint_range(0.1, 10.0) = 1.0;

group_uniforms Static_Terrain_Depth;
uniform float height_gradient_impact : hint_range(0.0, 1.0) = 0.25;
// Replaced raw min/max with hardware-friendly scale and offset values to bypass fragment divisions
uniform float world_height_scale = 0.0333; // 1.0 / (ceiling_y - floor_y)
uniform float world_height_offset = 0.5;   // Pre-shifted midpoint offset
uniform float directional_contrast : hint_range(0.0, 0.2) = 0.08;

varying float v_world_up;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	// Collect spatial and orientation properties at vertex step to save fragment ALU power
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_up = max(0.0, v_world_normal.y);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Texturing & Vertex-Assigned Color Data
	vec4 tex_color = texture(texture_atlas, UV);
	vec3 final_color = tex_color.rgb * COLOR.rgb;
	
	// 2. Fused Side Shading (Top vs Side definition)
	final_color += vec3(v_world_up * edge_pop - (1.0 - v_world_up) * side_shade);
	
	// 3. Directional Slope Tinting (Separates East/West walls from North/South)
	float directional_weight = abs(v_world_normal.x) * directional_contrast;
	final_color += vec3(directional_weight - (abs(v_world_normal.z) * directional_contrast));
	
	// 4. Global Elevation Gradient (Optimized to an O(1) multiply-add instruction)
	float height_factor = clamp(v_world_pos.y * world_height_scale + world_height_offset, 0.0, 1.0);
	final_color *= mix(1.0 - height_gradient_impact, 1.0, height_factor);
	
	// 5. Procedural Color-Sourced Map Glow
	float luma = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	float emit_mask = smoothstep(emit_threshold - 0.01, emit_threshold + 0.01, luma);
	vec3 base_emission = tex_color.rgb * emit_mask * emit_energy;
	
	// 6. Grid-Aligned Edge Contour Layout Logic
	vec3 scaled_world_pos = v_world_pos * (1.0 / voxel_scale);
	
	// Calculates strict distance to closest integer grid seam boundary
	vec3 dist_to_edge = min(fract(scaled_world_pos), 1.0 - fract(scaled_world_pos));
	vec3 edge_mask = smoothstep(voxel_edge_thickness / voxel_scale, 0.0, dist_to_edge);
	
	// Normal masking prevents cross-talk lines running flat down the visible faces
	vec3 normal_weight = 1.0 - abs(v_world_normal);
	float edge_contour = max(edge_mask.x * normal_weight.x, 
						 max(edge_mask.y * normal_weight.y, 
							 edge_mask.z * normal_weight.z));
	
	vec3 contour_glow = voxel_edge_color.rgb * edge_contour * voxel_edge_visible;
	
	// 7. Material Assignments
	ALBEDO = final_color;
	EMISSION = base_emission + contour_glow;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}