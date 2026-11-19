// Onyx : le rendu D3D11 de libmpv (ADR-0158, phase 2).
//
// Le pendant d'|ANGLESurfaceManager| sans ANGLE : libmpv dessine directement
// dans une texture D3D11 (MPV_RENDER_API_TYPE_D3D11, mpv 0.42.0), et son
// décodage d3d11va recopie lui-même la zone utile sur le GPU. Plus de recopie
// en mémoire vive (ADR-0095), plus de bande verte (ADR-0019).
//
// Même schéma que le chemin ANGLE, éprouvé : une texture de rendu interne que
// mpv remplit, une texture publique partagée avec Flutter par son |HANDLE|
// (DxgiSharedHandle), recopiées l'une dans l'autre sous un mutex. Ce mutex est
// ce qu'exige render_d3d11.h : personne d'autre ne touche au contexte immédiat
// pendant un rendu de mpv.

#ifndef D3D11_SURFACE_MANAGER_H_
#define D3D11_SURFACE_MANAGER_H_

#include <Windows.h>

#include <d3d11.h>
#include <wrl.h>

#include <cstdint>
#include <functional>

class D3D11SurfaceManager {
 public:
  const int32_t width() const { return width_; }
  const int32_t height() const { return height_; }
  const HANDLE handle() const { return handle_; }

  // Le périphérique à donner à mpv (mpv_d3d11_init_params::device).
  ID3D11Device* device() const { return device_.Get(); }

  // La texture où mpv dessine (mpv_d3d11_fbo::tex), à n'utiliser que dans le
  // rappel de |Draw|. Nulle si la dernière création a échoué (pilote
  // redémarré, mémoire vidéo épuisée).
  ID3D11Texture2D* render_target() const { return internal_texture_.Get(); }

  // Lève std::runtime_error si le périphérique ou les textures ne se créent
  // pas : |VideoOutput| passe alors au chemin suivant.
  D3D11SurfaceManager(int32_t width, int32_t height);

  ~D3D11SurfaceManager();

  // Recrée les deux textures à la nouvelle taille, en gardant le périphérique
  // (mpv le tient). Faux si la création échoue : |render_target| et |handle|
  // sont alors nuls, et le rendu suivant échoue sans planter.
  bool SetSize(int32_t width, int32_t height);

  // Appelle |callback| (le rendu de mpv) sous le mutex partagé avec |Read|.
  void Draw(std::function<void()> callback);

  // Recopie la texture interne dans la texture publique, sur le GPU. Appelé
  // par Flutter, sur son thread de rendu, quand il veut l'image.
  void Read();

 private:
  bool CreateDevice();

  bool CreateTextures();

  void ReleaseTextures();

  int32_t width_ = 1;
  int32_t height_ = 1;
  HANDLE handle_ = nullptr;

  // Synchronise |Draw| et |Read|.
  HANDLE mutex_ = nullptr;

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> internal_texture_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> public_texture_;
};

#endif  // D3D11_SURFACE_MANAGER_H_
