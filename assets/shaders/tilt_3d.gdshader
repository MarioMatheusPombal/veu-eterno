// Tilt 3D falso para a visualização ampliada da carta (segue o mouse).
shader_type canvas_item;

uniform vec2 inclinacao = vec2(0.0, 0.0); // -1..1 em cada eixo
uniform float intensidade = 0.22;

void vertex() {
	vec2 centro = 0.5 / TEXTURE_PIXEL_SIZE;
	vec2 c = UV - vec2(0.5);
	// Perspectiva falsa: cada canto escala conforme "profundidade" dada pelo tilt.
	float prof = 1.0 + (c.x * inclinacao.x + c.y * inclinacao.y) * intensidade;
	VERTEX = centro + (VERTEX - centro) * prof;
}

void fragment() {
	// Brilho direcional sutil acompanhando o tilt.
	vec2 c = UV - vec2(0.5);
	float brilho = clamp((c.x * -inclinacao.x + c.y * -inclinacao.y) * 0.35, -0.12, 0.25);
	COLOR = texture(TEXTURE, UV);
	COLOR.rgb += brilho * COLOR.a;
}
