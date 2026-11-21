shader_type canvas_item;
render_mode unshaded;

// Emerald pulses a single palette entry on Rayquaza's markings.
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	if (texel.r > 0.98 && texel.g > 0.98 && texel.b < 0.65) {
		float phase = (sin(TIME * 1.8) + 1.0) * 0.5;
		float step_value = floor(phase * 7.0) / 7.0;
		texel.rgb = mix(vec3(0.38, 0.72, 0.38), texel.rgb, step_value);
	}
	COLOR = texel;
}
