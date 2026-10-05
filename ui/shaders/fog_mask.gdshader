// Из игры SunLess: scenes/map/sleeper_fog_mask.gdshader — предпросмотр воды и тумана как в игре.
shader_type canvas_item;
// Маска тумана «Карты Спящего»: где открыто (0..1). Считается в своей текстуре (SubViewport, половина разрешения
// основы) и только когда открытое меняется — проявление места, новые места, сдвиг воды (аудит 03.10: раньше эти
// циклы шли для каждого пикселя экрана в каждом кадре — самая дорогая часть кадра). Формулы — прежние.
// Открыто: круги мест (holes) и коридоры между открытыми соседями (segs), слияние мягкое (smooth max).

uniform vec4 holes[48];      // xy — центр (доли основы), z — радиус (доли высоты основы), w — 0..1 (проявление)
uniform int hole_count = 0;
uniform vec4 segs[64];       // xy — один конец, zw — другой (доли основы)
uniform vec2 seg_w[64];      // x — полуширина коридора (доли высоты основы), y — 0..1 (проявление)
uniform int seg_count = 0;
uniform float aspect = 2.0;

float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(a, b, h) + k * h * (1.0 - h);
}

void fragment() {
	float clear = 0.0;
	for (int i = 0; i < hole_count; i++) {
		vec4 hl = holes[i];
		vec2 dd = UV - hl.xy;
		dd.x *= aspect;
		float r = hl.z * hl.w;
		clear = smax(clear, 1.0 - smoothstep(r * 0.55, r, length(dd)), 0.12);
	}
	for (int j = 0; j < seg_count; j++) {
		vec4 sg = segs[j];
		vec2 a = sg.xy;
		vec2 b = sg.zw;
		vec2 pa = UV - a;
		vec2 ba = b - a;
		pa.x *= aspect;
		ba.x *= aspect;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
		float d = length(pa - ba * h);
		float r = seg_w[j].x * seg_w[j].y;
		clear = smax(clear, 1.0 - smoothstep(r * 0.45, r, d), 0.12);
	}
	COLOR = vec4(clamp(clear, 0.0, 1.0), 0.0, 0.0, 1.0);
}
