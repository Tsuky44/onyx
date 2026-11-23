#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Le rendu de l'interface est celui du moteur par défaut : Impeller sur
  // OpenGL ES (ANGLE) depuis Flutter 3.47 (ADR-0167). Impeller n'a pas de
  // rendu logiciel de secours : si la surface GPU échoue, la fenêtre reste
  // noire. Hors release, FLUTTER_ENGINE_SWITCHES=1 et
  // FLUTTER_ENGINE_SWITCH_1=enable-impeller=false repassent en Skia pour
  // comparer. En 3.50.1, `set_impeller_switch(Disabled)` n'a pas eu d'effet
  // ici : ne pas s'y fier comme repli sans l'avoir revérifié.

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
