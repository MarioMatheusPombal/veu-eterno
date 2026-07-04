// Acabamento FOIL: varredura de arco-íris metálica e sutil sobre a carta.
shader_type canvas_item;
render_mode blend_add;

uniform float forca = 0.28;

void fragment() {
	float faixa = sin((UV.x + UV.y) * 7.0 - TIME * 1.4);
	float fase = TIME * 0.8 + UV.x * 5.0 + UV.y * 2.0;
	vec3 arcoiris = vec3(
		0.5 + 0.5 * sin(fase),
		0.5 + 0.5 * sin(fase + 2.094),
		0.5 + 0.5 * sin(fase + 4.188));
	COLOR = vec4(arcoiris * max(faixa, 0.0) * forca, 1.0);
}
