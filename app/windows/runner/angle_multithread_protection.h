#ifndef RUNNER_ANGLE_MULTITHREAD_PROTECTION_H_
#define RUNNER_ANGLE_MULTITHREAD_PROTECTION_H_

// Protection multithread de Direct3D 11 sur l'appareil D3D11 d'ANGLE, celui
// avec lequel Flutter dessine l'interface (ADR-0167).
//
// En 3.50, ANGLE ne verrouille plus `eglSwapBuffers` contre les appels GL :
// le fil raster qui présente une image et le fil IO qui envoie une image
// décodée au GPU passent alors en même temps dans le contexte immédiat D3D11,
// et le pilote plante en quelques secondes (flutter/flutter#196618, avec
// Skia comme avec Impeller). Le moteur corrige en activant la protection
// multithread de l'appareil (flutter/flutter#196897), ce que la 3.50.1 ne
// fait pas encore.
//
// L'ANGLE de Flutter est lié dans flutter_windows.dll (le libEGL.dll livré à
// côté est celui de libmpv) et n'expose ni EGL ni son appareil. Il trouve
// D3D11CreateDevice par GetProcAddress : |Install| détourne cet import-là de
// flutter_windows.dll, et seulement pour D3D11CreateDevice. Chaque appareil
// créé par Flutter reçoit la protection avant son premier usage.
namespace angle_multithread_protection {

// À appeler une fois, avant la création du FlutterViewController. Rend vrai
// si le détour est posé ; sinon, journalise la raison sur la sortie standard
// et l'app continue sans protection.
bool Install();

}  // namespace angle_multithread_protection

#endif  // RUNNER_ANGLE_MULTITHREAD_PROTECTION_H_
