// Из игры SunLess: scenes/map/sleeper_water.gdshader — предпросмотр воды и тумана как в игре.
shader_type canvas_item;
// Вода прилива на «Карте Спящего»: уровень по карте высот (0–255). Нарисованное море (ниже обычной кромки)
// не трогаем — только оживляем бликами; выше кромки, где высота ниже уровня, — гравированная вода с пеной по краю.

uniform sampler2D height_tex : filter_linear;
uniform sampler2D water_tex : repeat_enable, filter_linear_mipmap;
uniform float level = 55.0;
uniform float normal_level = 55.0;
uniform float aspect = 2.0;
uniform vec4 tint : source_color = vec4(0.62, 0.78, 0.86, 1.0);

void fragment() {
	float h = texture(height_tex, UV).r * 255.0;
	float depth = level - h;
	float above = smoothstep(normal_level - 3.0, normal_level + 3.0, h);
	vec2 wuv = UV * vec2(6.0 * aspect, 6.0);
	vec3 w1 = texture(water_tex, wuv + vec2(TIME * 0.006, TIME * 0.003)).rgb;
	vec3 w2 = texture(water_tex, wuv * 1.37 + vec2(-TIME * 0.004, TIME * 0.005)).rgb;
	vec3 w = mix(w1, w2, 0.45) * tint.rgb;
	float d = clamp(depth / 45.0, 0.0, 1.0);
	vec3 col = mix(w * 1.2, w * 0.55, d);
	float wet = smoothstep(-1.0, 3.0, depth) * above;
	float foam = (1.0 - smoothstep(0.0, 5.0, abs(depth))) * above * step(normal_level + 1.0, level);
	float ripple = 0.55 + 0.45 * sin(TIME * 1.7 + UV.x * 90.0 + UV.y * 40.0);
	col = mix(col, vec3(0.86, 0.9, 0.92), foam * 0.55 * ripple);
	// в открытом море — лёгкие бегущие блики поверх нарисованных волн
	float sea = 1.0 - above;
	float glint = smoothstep(0.62, 0.95, w2.r) * sea * 0.18;
	float a = max(wet * 0.9, foam * 0.7);
	COLOR = vec4(mix(col, vec3(0.8, 0.86, 0.9), glint * (1.0 - a)), max(a, glint));
}
