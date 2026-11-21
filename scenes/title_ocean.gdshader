shader_type canvas_item;
render_mode unshaded;

// Light filtered through the surface and the contours of a deep ocean trench.
void fragment() {
	vec2 p = UV;
	float surface = pow(1.0 - p.y, 2.0);
	vec3 deep = vec3(0.027, 0.073, 0.204);
	vec3 blue = mix(deep, vec3(0.018, 0.294, 0.53), (0.22 + 0.78 * p.x) * (0.28 + 0.72 * surface));
	float glow = exp(-length((p - vec2(0.76, 0.27)) * vec2(2.4, 2.0)) * 2.3);
	blue += vec3(0.005, 0.17, 0.235) * glow;
	float rays = 0.5 + 0.5 * sin(22.0 * p.x + 6.5 * p.y + 0.22 * sin(TIME * 0.23));
	blue += vec3(0.008, 0.055, 0.074) * pow(rays, 5.0) * surface;
	float depth = 2.3*p.x + 3.5*p.y + 0.56*sin(3.7*p.x - 4.1*p.y) + 0.14*sin(10.0*p.x + 3.6*p.y + TIME*0.055);
	float ring = 1.0 - smoothstep(0.022, 0.053, abs(fract(depth * 3.15) - 0.5));
	float coast = smoothstep(0.48, 0.89, p.y) + 0.22 * smoothstep(0.77, 1.0, p.x);
	blue += vec3(0.045, 0.155, 0.185) * ring * clamp(coast, 0.0, 1.0);
	float surface_lace = sin(p.x*53.0 + 2.6*sin(p.x*11.6 + TIME*0.28) + TIME*0.31);
	float crest = exp(-abs(p.y - 0.014 - 0.005*surface_lace - 0.007*sin(p.x*16.0 - TIME*0.13))*83.0);
	blue += vec3(0.04, 0.23, 0.33) * crest * smoothstep(0.22,0.75,p.x);
	vec2 field = p*vec2(24.0, 13.0) + vec2(0.05*sin(TIME*0.17), TIME*0.12);
	vec2 cell = floor(field);
	float seed = fract(sin(dot(cell, vec2(13.73,65.13)))*43758.55);
	vec2 center = vec2(0.24+0.51*seed,0.28+0.43*fract(seed*11.6));
	vec2 delta = (fract(field)-center)*vec2(0.82,1.0);
	float bubble = (1.0-smoothstep(0.014,0.040,abs(length(delta)-(0.03+0.085*seed))));
	blue += vec3(0.08,0.24,0.30) * bubble * smoothstep(0.76,0.92,seed) * smoothstep(0.27,0.58,p.x);
	COLOR = vec4(blue, 1.0);
}
