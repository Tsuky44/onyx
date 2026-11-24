#version 320 es

// Le flou du bord du haut d'une page qui défile sous la barre du téléphone
// (ADR-0144) : fort en haut, nul en bas, et sans marche entre les deux. Une
// passe le long d'un axe ; la barre en compose deux, horizontale puis
// verticale, pour un flou gaussien.

#include <flutter/runtime_effect.glsl>

// Posés par le moteur : la taille de la texture et ce qui est dessous.
uniform vec2 u_size;
uniform sampler2D u_texture;

// La hauteur du bord, en pixels physiques, depuis le haut de l'écran.
uniform float u_height;
// Le flou le plus fort, en haut (écart type, en pixels physiques).
uniform float u_sigma;
// L'axe de la passe : (1, 0) ou (0, 1).
uniform vec2 u_dir;

out vec4 frag_color;

const int kTaps = 16;

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 uv = coord / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  // La force du flou suit la position à l'écran, et s'éteint en douceur :
  // pas de pente brusque, ni en haut ni en bas.
  float t = clamp(coord.y / u_height, 0.0, 1.0);
  float sigma = u_sigma * (1.0 - smoothstep(0.0, 1.0, t));

  // Une seule sortie : un `return` anticipé à côté d'un échantillonneur
  // peut faire échouer la compilation du shader sous Windows, où Impeller
  // passe par OpenGL ES (flutter/flutter#190809, ADR-0167).
  if (sigma < 0.35) {
    frag_color = texture(u_texture, uv);
  } else {
    vec2 dir = u_dir / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
    dir.y = -dir.y;
#endif

    // Trois écarts types de chaque côté, en seize pas.
    float stepPx = max(sigma * 3.0 / float(kTaps), 1.0);
    float inv = 1.0 / (2.0 * sigma * sigma);
    vec4 sum = texture(u_texture, uv);
    float total = 1.0;
    for (int i = 1; i <= kTaps; i++) {
      float x = float(i) * stepPx;
      float w = exp(-x * x * inv);
      sum += (texture(u_texture, uv + dir * x) + texture(u_texture, uv - dir * x)) * w;
      total += 2.0 * w;
    }
    frag_color = sum / total;
  }
}
