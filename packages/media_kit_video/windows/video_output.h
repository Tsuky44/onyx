// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef VIDEO_OUTPUT_H_
#define VIDEO_OUTPUT_H_

#include <optional>

#include <client.h>
#include <render.h>
#include <render_d3d11.h>
#include <render_gl.h>

#include <atomic>
#include <future>
#include <memory>
#include <string>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "angle_surface_manager.h"
#include "d3d11_surface_manager.h"
#include "thread_pool.h"

typedef struct _VideoOutputConfiguration {
  std::optional<int64_t> width;
  std::optional<int64_t> height;
  bool enable_hardware_acceleration;
  // Onyx : le premier chemin de rendu matériel essayé (ADR-0158, phase 2).
  // "d3d11" : le rendu D3D11 de libmpv, puis ANGLE, puis le logiciel.
  // "angle" (défaut, et toute autre valeur) : ANGLE, puis le logiciel.
  std::string render_api;

  _VideoOutputConfiguration(std::optional<int64_t> width = std::nullopt,
                            std::optional<int64_t> height = std::nullopt,
                            bool enable_hardware_acceleration = true,
                            std::string render_api = "angle")
      : width(width),
        height(height),
        enable_hardware_acceleration(enable_hardware_acceleration),
        render_api(render_api) {}
} VideoOutputConfiguration;

// Onyx : texture, largeur, hauteur, et le chemin de rendu retenu ("d3d11",
// "angle" ou "sw"), que Dart lit pour choisir le décodeur (ADR-0158).
typedef std::function<void(int64_t, int64_t, int64_t, const std::string&)>
    TextureUpdateCallback;

class VideoOutput {
 public:
  int64_t texture_id() const { return texture_id_; }

  // Onyx : le chemin de rendu retenu à la création, et ce que ses rendus ont
  // donné. Une texture D3D11 qui n'a jamais rendu une image est ce que Dart
  // guette pour retomber sur ANGLE (ADR-0158, phase 2, point 4).
  const std::string& render_api() const { return render_api_; }
  int64_t rendered_frames() const { return rendered_frames_.load(); }
  int64_t failed_frames() const { return failed_frames_.load(); }
  // La cause relevée au premier rendu D3D11 raté sur un périphérique perdu
  // (TDR, pilote redémarré) ; 0 sinon.
  int64_t device_removed_reason() const {
    return device_removed_reason_.load();
  }

  // Onyx : quitte le rendu D3D11 pour ANGLE (puis le logiciel), sans changer
  // de lecteur mpv (ADR-0158, phase 2, point 4). Libérer le contexte de rendu
  // coupe la vidéo de mpv (sa piste est désélectionnée, le son continue) :
  // Dart la resélectionne ensuite. Rend le chemin retenu ; rien ne change si
  // la sortie n'est pas en D3D11.
  std::string FallbackToANGLE();

  int64_t width() const {
    // D3D11
    if (d3d11_surface_manager_ != nullptr && texture_id_) {
      return d3d11_surface_manager_->width();
    }
    // H/W
    if (surface_manager_ != nullptr && texture_id_) {
      return surface_manager_->width();
    }
    // S/W
    if (pixel_buffer_ != nullptr && texture_id_) {
      return pixel_buffer_textures_.at(texture_id_)->width;
    }
    return width_.value_or(1);
  }
  int64_t height() const {
    // D3D11
    if (d3d11_surface_manager_ != nullptr && texture_id_) {
      return d3d11_surface_manager_->height();
    }
    // H/W
    if (surface_manager_ != nullptr && texture_id_) {
      return surface_manager_->height();
    }
    // S/W
    if (pixel_buffer_ != nullptr && texture_id_) {
      return pixel_buffer_textures_.at(texture_id_)->height;
    }
    return height_.value_or(1);
  }

  VideoOutput(int64_t handle,
              VideoOutputConfiguration configuration,
              flutter::PluginRegistrarWindows* registrar,
              ThreadPool* thread_pool_ref);

  ~VideoOutput();

  void SetTextureUpdateCallback(TextureUpdateCallback callback);

  void SetSize(std::optional<int64_t> width, std::optional<int64_t> height);

 private:
  // Onyx : un essai par chemin. Chacun ne garde son état que si
  // mpv_render_context_create réussit, et laisse tout propre sinon.
  bool InitializeD3D11();

  bool InitializeANGLE();

  void InitializeSoftware();

  void SetUpdateCallback();

  void NotifyRender();

  void Render();

  void CheckAndResize();

  void Resize(int64_t required_width, int64_t required_height);

  int64_t GetVideoWidth();

  int64_t GetVideoHeight();

  std::optional<int64_t> height_ = std::nullopt;
  std::optional<int64_t> width_ = std::nullopt;
  VideoOutputConfiguration configuration_ = VideoOutputConfiguration{};

  mpv_handle* handle_ = nullptr;
  mpv_render_context* render_context_ = nullptr;
  int64_t texture_id_ = 0;
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  ThreadPool* thread_pool_ref_ = nullptr;
  // For preventing any asynchronous operations (primarily texture objects
  // deletion after unregister in |Resize|) access this object after
  // destruction.
  bool destroyed_ = false;

  std::mutex textures_mutex_ = std::mutex();

  std::unordered_map<int64_t, std::unique_ptr<flutter::TextureVariant>>
      texture_variants_ = {};

  // H/W rendering.

  std::unique_ptr<ANGLESurfaceManager> surface_manager_ = nullptr;
  // Onyx : le rendu D3D11 de libmpv (ADR-0158). Exclusif avec
  // |surface_manager_| : un seul des deux est non nul.
  std::unique_ptr<D3D11SurfaceManager> d3d11_surface_manager_ = nullptr;
  std::unordered_map<int64_t,
                     std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor>>
      textures_ = {};

  // S/W rendering.

  std::unique_ptr<uint8_t[]> pixel_buffer_ = nullptr;
  std::unordered_map<int64_t, std::unique_ptr<FlutterDesktopPixelBuffer>>
      pixel_buffer_textures_ = {};

  std::string render_api_ = "sw";
  std::atomic<int64_t> rendered_frames_{0};
  std::atomic<int64_t> failed_frames_{0};
  std::atomic<int64_t> device_removed_reason_{0};

  // Public notifier. This is called when a new texture is registered & texture
  // ID is changed. Only happens when video output resolution changes.
  TextureUpdateCallback texture_update_callback_ =
      [](int64_t, int64_t, int64_t, const std::string&) {};
};

#endif  // VIDEO_OUTPUT_H_
