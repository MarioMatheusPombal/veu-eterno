// Acabamento HOLOGRÁFICO: mais forte que o foil — varredura vertical, arco-íris e cintilância.
shader_type canvas_item;
render_mode blend_add;

uniform float forca = 0.45;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Varredura de brilho subindo pela carta.
	float varredura = pow(0.5 + 0.5 * sin(UV.y * 16.0 - TIME * 2.6), 3.0);
	// Arco-íris diagonal em movimento.
	float fase = TIME * 1.1 + (UV.x - UV.y) * 8.0;
	vec3 arcoiris = vec3(
		0.5 + 0.5 * sin(fase),
		0.5 + 0.5 * sin(fase + 2.094),
		0.5 + 0.5 * sin(fase + 4.188));
	// Cintilâncias (sparkles) que mudam com o tempo.
	vec2 celula = floor(UV * vec2(18.0, 26.0));
	float cintila = step(0.965, hash(celula + floor(TIME * 3.0)));
	vec3 cor = arcoiris * (varredura * 0.6 + 0.15) * forca + vec3(cintila) * 0.5;
	COLOR = vec4(cor, 1.0);
}
