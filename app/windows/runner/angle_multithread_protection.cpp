#include "angle_multithread_protection.h"

#include <windows.h>

// ID3D10Multithread vient de d3d10.h, que d3d10_1.h inclut : d3d10.h seul,
// avant d3d10_1.h, est refusé par le SDK Windows.
#include <d3d10_1.h>
#include <d3d11.h>
#include <wrl/client.h>

#include <atomic>
#include <cstring>
#include <iostream>

namespace angle_multithread_protection {

namespace {

using GetProcAddressFn = FARPROC(WINAPI*)(HMODULE, LPCSTR);

std::atomic<GetProcAddressFn> real_get_proc_address{nullptr};
std::atomic<PFN_D3D11_CREATE_DEVICE> real_create_device{nullptr};
std::atomic<int> protected_devices{0};

void Log(const char* message) {
  std::cout << "Onyx: ANGLE: " << message << std::endl;
}

HRESULT WINAPI ProtectedCreateDevice(IDXGIAdapter* adapter,
                                     D3D_DRIVER_TYPE driver_type,
                                     HMODULE software,
                                     UINT flags,
                                     const D3D_FEATURE_LEVEL* feature_levels,
                                     UINT feature_level_count,
                                     UINT sdk_version,
                                     ID3D11Device** device,
                                     D3D_FEATURE_LEVEL* feature_level,
                                     ID3D11DeviceContext** context) {
  const HRESULT result = real_create_device.load()(
      adapter, driver_type, software, flags, feature_levels,
      feature_level_count, sdk_version, device, feature_level, context);
  // ANGLE appelle aussi D3D11CreateDevice sans |device| pour sonder les
  // niveaux de fonctionnalité : rien à protéger alors.
  if (FAILED(result) || !device || !*device) {
    return result;
  }
  Microsoft::WRL::ComPtr<ID3D10Multithread> multithread;
  if (FAILED((*device)->QueryInterface(IID_PPV_ARGS(&multithread)))) {
    Log("protection multithread D3D11 non activée (ID3D10Multithread)");
    return result;
  }
  multithread->SetMultithreadProtected(TRUE);
  if (!multithread->GetMultithreadProtected()) {
    Log("protection multithread D3D11 non activée (SetMultithreadProtected)");
    return result;
  }
  const int count = ++protected_devices;
  std::cout << "Onyx: ANGLE: protection multithread D3D11 active (appareil "
            << count << ")" << std::endl;
  return result;
}

FARPROC WINAPI DetouredGetProcAddress(HMODULE module, LPCSTR name) {
  const FARPROC proc = real_get_proc_address.load()(module, name);
  // Un nom peut être un ordinal : seul un vrai nom est comparé.
  if (!proc || IS_INTRESOURCE(name) ||
      std::strcmp(name, "D3D11CreateDevice") != 0) {
    return proc;
  }
  real_create_device = reinterpret_cast<PFN_D3D11_CREATE_DEVICE>(proc);
  return reinterpret_cast<FARPROC>(&ProtectedCreateDevice);
}

// L'entrée de la table d'imports de |module| pour |dll|!|function|, ou nullptr.
FARPROC* FindImport(HMODULE module, const char* dll, const char* function) {
  auto* base = reinterpret_cast<BYTE*>(module);
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
    return nullptr;
  }
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE) {
    return nullptr;
  }
  const IMAGE_DATA_DIRECTORY& directory =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (directory.VirtualAddress == 0) {
    return nullptr;
  }
  for (auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(
           base + directory.VirtualAddress);
       descriptor->Name != 0; ++descriptor) {
    if (_stricmp(reinterpret_cast<char*>(base + descriptor->Name), dll) != 0 ||
        descriptor->OriginalFirstThunk == 0) {
      continue;
    }
    auto* names = reinterpret_cast<IMAGE_THUNK_DATA*>(
        base + descriptor->OriginalFirstThunk);
    auto* slots =
        reinterpret_cast<IMAGE_THUNK_DATA*>(base + descriptor->FirstThunk);
    for (; names->u1.AddressOfData != 0; ++names, ++slots) {
      if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) {
        continue;
      }
      auto* by_name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
          base + names->u1.AddressOfData);
      if (std::strcmp(reinterpret_cast<char*>(by_name->Name), function) == 0) {
        return reinterpret_cast<FARPROC*>(&slots->u1.Function);
      }
    }
  }
  return nullptr;
}

}  // namespace

bool Install() {
  if (real_get_proc_address.load()) {
    return true;
  }
  HMODULE flutter = ::GetModuleHandleW(L"flutter_windows.dll");
  if (!flutter) {
    Log("protection multithread D3D11 non posée (flutter_windows.dll absent)");
    return false;
  }
  FARPROC* slot = FindImport(flutter, "KERNEL32.dll", "GetProcAddress");
  if (!slot) {
    Log("protection multithread D3D11 non posée (import GetProcAddress "
        "introuvable)");
    return false;
  }
  DWORD old_protection = 0;
  if (!::VirtualProtect(slot, sizeof(*slot), PAGE_READWRITE,
                        &old_protection)) {
    Log("protection multithread D3D11 non posée (VirtualProtect)");
    return false;
  }
  real_get_proc_address = reinterpret_cast<GetProcAddressFn>(*slot);
  *slot = reinterpret_cast<FARPROC>(&DetouredGetProcAddress);
  ::VirtualProtect(slot, sizeof(*slot), old_protection, &old_protection);
  return true;
}

}  // namespace angle_multithread_protection
