shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

// Core Positioning
uniform vec3 player_world_pos;
uniform float fog_radius : hint_range(0.0, 100.0) = 15.0;
uniform float fog_feather : hint_range(0.0, 100.0) = 10.0;

// Color Gradient (The Bleed Matrix)
uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform vec3 energy_color : source_color = vec3(0.0, 0.9, 1.0);
uniform float energy_bleed_falloff : hint_range(0.1, 25.0) = 1.0;

// Height Mask
uniform float fog_max_height = 4.0;
uniform float fog_height_feather = 2.0;

// Mist Swirl
uniform float wave_speed : hint_range(0.0, 5.0) = 0.5;
uniform float wave_frequency : hint_range(0.0, 1.0) = 0.1;
uniform float wave_amplitude : hint_range(0.0, 5.0) = 0.4;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;

void vertex() {
	// FIX 1: Multiply by 2.0 to expand the default 1x1 QuadMesh (-0.5 to 0.5) 
	// to perfectly fill the full NDC screen boundaries (-1.0 to 1.0).
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	
	// FIX 2: Safe Reconstruction. We handle this inside the fragment pass 
	// where camera and projection matrices are guaranteed to be fully populated.
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
	vec4 world = INV_VIEW_MATRIX * (INV_PROJECTION_MATRIX * vec4(ndc, 1.0));
	vec3 world_pos = world.xyz / world.w;
	
	// Streamlined vector calculations
	float time_factor = TIME * wave_speed;
	float wave_x = world_pos.x * wave_frequency + time_factor;
	float wave_z = world_pos.z * (wave_frequency * 0.8) - (time_factor * 0.6);
	
	float wave = sin(wave_x) * cos(wave_z) * wave_amplitude;
	float dist = distance(world_pos, player_world_pos) + wave;
	
	// Calculate density maps
	float radial_fog = smoothstep(fog_radius, fog_radius + fog_feather, dist);
	float height_factor = smoothstep(fog_max_height + fog_height_feather, fog_max_height, world_pos.y);
	
	// Re-applied branchless skybox mask
	float sky_mask = step(0.0001, depth) * (1.0 - step(0.9999, depth));
	float final_density = radial_fog * height_factor * sky_mask;
	
	float bleed_mix = pow(radial_fog, energy_bleed_falloff);
	vec3 final_fog_rgb = mix(fog_color.rgb, energy_color, bleed_mix);
	
	ALBEDO = final_fog_rgb;
	ALPHA = final_density * fog_color.a;
}