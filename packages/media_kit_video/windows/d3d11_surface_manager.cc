// Onyx : le rendu D3D11 de libmpv (ADR-0158, phase 2). Voir l'en-tête.

#include "d3d11_surface_manager.h"

#include <d3d10.h>
#include <dxgi.h>

#include <iostream>
#include <stdexcept>

#include "utils.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

namespace {

void LogFailure(const char* step, HRESULT hr) {
  std::cout << "media_kit: D3D11SurfaceManager: Failure: " << step
            << " (0x" << std::hex << static_cast<uint32_t>(hr) << std::dec
            << ")" << std::endl;
}

}  // namespace

D3D11SurfaceManager::D3D11SurfaceManager(int32_t width, int32_t height)
    : width_(width), height_(height) {
  mutex_ = ::CreateMutex(NULL, FALSE, NULL);
  if (!CreateDevice()) {
    ::CloseHandle(mutex_);
    mutex_ = nullptr;
    throw std::runtime_error("Unable to create Direct3D 11 device.");
  }
  if (!CreateTextures()) {
    ReleaseTextures();
    ::CloseHandle(mutex_);
    mutex_ = nullptr;
    throw std::runtime_error("Unable to create Direct3D 11 textures.");
  }
}

D3D11SurfaceManager::~D3D11SurfaceManager() {
  if (mutex_ != nullptr) {
    ::WaitForSingleObject(mutex_, INFINITE);
  }
  ReleaseTextures();
  context_.Reset();
  // mpv garde sa propre référence au périphérique jusqu'à
  // mpv_render_context_free, appelé après cette destruction.
  device_.Reset();
  if (mutex_ != nullptr) {
    ::ReleaseMutex(mutex_);
    ::CloseHandle(mutex_);
  }
}

bool D3D11SurfaceManager::SetSize(int32_t width, int32_t height) {
  if (width == width_ && height == height_ && internal_texture_ != nullptr) {
    return true;
  }
  ::WaitForSingleObject(mutex_, INFINITE);
  width_ = width;
  height_ = height;
  ReleaseTextures();
  auto created = CreateTextures();
  if (!created) {
    ReleaseTextures();
  }
  ::ReleaseMutex(mutex_);
  return created;
}

void D3D11SurfaceManager::Draw(std::function<void()> callback) {
  ::WaitForSingleObject(mutex_, INFINITE);
  callback();
  ::ReleaseMutex(mutex_);
}

void D3D11SurfaceManager::Read() {
  ::WaitForSingleObject(mutex_, INFINITE);
  if (context_ != nullptr && internal_texture_ != nullptr &&
      public_texture_ != nullptr) {
    context_->CopyResource(public_texture_.Get(), internal_texture_.Get());
    context_->Flush();
  }
  ::ReleaseMutex(mutex_);
}

bool D3D11SurfaceManager::CreateDevice() {
  // Le même adaptateur que le chemin ANGLE, donc que Flutter : sur un portable
  // à deux GPU, la texture partagée doit naître sur le GPU qui la compose, sans
  // quoi Flutter ne peut pas l'ouvrir. Sous Windows 10 et après, l'adaptateur
  // par défaut ; avant, le premier énuméré.
  IDXGIAdapter* adapter = nullptr;
  D3D_DRIVER_TYPE driver_type = D3D_DRIVER_TYPE_UNKNOWN;
  if (Utils::IsWindows10RTMOrGreater()) {
    driver_type = D3D_DRIVER_TYPE_HARDWARE;
  } else {
    IDXGIFactory* dxgi = nullptr;
    if (SUCCEEDED(::CreateDXGIFactory(__uuidof(IDXGIFactory),
                                      reinterpret_cast<void**>(&dxgi)))) {
      dxgi->EnumAdapters(0, &adapter);
      dxgi->Release();
    }
  }

  // Les niveaux que mpv demande lui-même pour sa sortie d3d11
  // (video/out/gpu/d3d11_helpers.c). Sans D3D11_CREATE_DEVICE_SINGLETHREADED :
  // le décodage d3d11va tourne sur le fil du décodeur de mpv, sur ce même
  // périphérique (render_d3d11.h).
  const D3D_FEATURE_LEVEL levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3,
  };
  auto create = [&](const D3D_FEATURE_LEVEL* first, UINT count) {
    return ::D3D11CreateDevice(adapter, driver_type, nullptr, 0, first, count,
                               D3D11_SDK_VERSION, &device_, nullptr,
                               &context_);
  };
  auto hr = create(levels, ARRAYSIZE(levels));
  if (hr == E_INVALIDARG) {
    // Un runtime sans D3D 11.1 refuse toute la liste dès qu'elle le nomme.
    hr = create(levels + 1, ARRAYSIZE(levels) - 1);
  }
  if (adapter != nullptr) {
    adapter->Release();
  }
  if (FAILED(hr)) {
    LogFailure("D3D11CreateDevice", hr);
    return false;
  }

  // mpv l'active aussi à l'ouverture de d3d11va. Posé ici pour que le rendu
  // logiciel, qui ne l'ouvre pas, soit couvert de la même façon : |Read| vient
  // du fil de rendu de Flutter.
  Microsoft::WRL::ComPtr<ID3D10Multithread> multithread;
  if (SUCCEEDED(device_.As(&multithread))) {
    multithread->SetMultithreadProtected(TRUE);
  }

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  if (SUCCEEDED(device_.As(&dxgi_device))) {
    dxgi_device->SetGPUThreadPriority(5);  // Dans [-7, 7], comme ANGLE.
  }

  auto level = device_->GetFeatureLevel();
  std::cout << "media_kit: D3D11SurfaceManager: Direct3D Feature Level: "
            << (((unsigned)level) >> 12) << "_"
            << ((((unsigned)level) >> 8) & 0xf) << std::endl;
  return true;
}

bool D3D11SurfaceManager::CreateTextures() {
  auto desc = D3D11_TEXTURE2D_DESC{0};
  desc.Width = width_;
  desc.Height = height_;
  // B8G8R8A8 : le format que Flutter attend d'une DxgiSharedHandle, et l'un de
  // ceux que render_d3d11.h accepte pour mpv_d3d11_fbo.
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.CPUAccessFlags = 0;

  // L'interne : mpv y dessine, sur ce périphérique seul.
  desc.MiscFlags = 0;
  auto hr = device_->CreateTexture2D(&desc, nullptr, &internal_texture_);
  if (FAILED(hr)) {
    LogFailure("CreateTexture2D (render target)", hr);
    return false;
  }

  // La publique : Flutter l'ouvre sur son propre périphérique.
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  hr = device_->CreateTexture2D(&desc, nullptr, &public_texture_);
  if (FAILED(hr)) {
    LogFailure("CreateTexture2D (shared)", hr);
    return false;
  }
  Microsoft::WRL::ComPtr<IDXGIResource> resource;
  hr = public_texture_.As(&resource);
  if (FAILED(hr)) {
    LogFailure("IDXGIResource", hr);
    return false;
  }
  hr = resource->GetSharedHandle(&handle_);
  if (FAILED(hr) || handle_ == nullptr) {
    LogFailure("GetSharedHandle", hr);
    return false;
  }
  return true;
}

void D3D11SurfaceManager::ReleaseTextures() {
  internal_texture_.Reset();
  public_texture_.Reset();
  // Le |HANDLE| d'une ressource partagée par GetSharedHandle n'est pas un
  // handle de noyau : il ne se ferme pas, il meurt avec la texture.
  handle_ = nullptr;
}
