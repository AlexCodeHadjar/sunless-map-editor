// Из игры SunLess: scenes/map/sleeper_fog.gdshader — предпросмотр воды и тумана как в игре.
shader_type canvas_item;
// Туман неизвестного на «Карте Спящего»: бумага с дымкой поверх всего, кроме открытого.
// Где открыто — маска (sleeper_fog_mask.gdshader): круги мест и коридоры между открытыми соседями (просьба владельца
// 03.10: открытые места сливаются в одну область, без тёмных перемычек). Маска считается отдельно и только при
// изменениях (аудит 03.10); здесь — одна выборка из неё, дымка и кромка.

uniform sampler2D fog_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D mask : filter_linear;
uniform float aspect = 2.0;
uniform float density = 0.86;

void fragment() {
	float clear = texture(mask, UV).r;
	vec2 fuv = UV * vec2(2.2 * aspect, 2.2);
	vec3 f = texture(fog_tex, fuv + vec2(TIME * 0.004, -TIME * 0.002)).rgb;
	vec3 f2 = texture(fog_tex, fuv * 0.6 + vec2(-TIME * 0.003, TIME * 0.0015)).rgb;
	vec3 col = mix(f, f2, 0.5) * 0.4;
	// у кромки открытого — тушь дорисовывается: тёмная линия
	float edge = smoothstep(0.08, 0.35, clear) * (1.0 - smoothstep(0.35, 0.8, clear));
	col = mix(col, vec3(0.07, 0.07, 0.09), edge * 0.6);
	COLOR = vec4(col, (1.0 - clear) * density);
}
