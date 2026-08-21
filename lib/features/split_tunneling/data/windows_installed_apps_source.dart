import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/features/split_tunneling/model/windows_app_info.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:win32/win32.dart';

/// Enumerates installed desktop apps on Windows for the split-tunneling
/// app picker, by resolving Start Menu (.lnk) shortcuts to their target
/// .exe — the same identifier sing-box's process_path route rule compares
/// against at runtime. Pure Dart via package:win32 (COM interop for shell
/// links + GDI for icon extraction), no native platform channel needed.
///
/// UWP/Microsoft Store apps are intentionally out of scope: they use a
/// different identifier (Package Family Name) that doesn't map onto a
/// resolvable .exe path the way classic desktop apps do.
abstract interface class WindowsInstalledAppsSource {
  Future<List<WindowsAppInfo>> getInstalledApps();
}

class WindowsInstalledAppsSourceImpl implements WindowsInstalledAppsSource {
  @override
  Future<List<WindowsAppInfo>> getInstalledApps() async {
    if (!PlatformUtils.isWindows) return [];
    return compute(_enumerateWindowsApps, null);
  }
}

List<WindowsAppInfo> _enumerateWindowsApps(void _) {
  final hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  final needsUninit = SUCCEEDED(hr);
  try {
    final startMenuDirs = <String>{
      r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs',
      if (Platform.environment['APPDATA'] case final appData?)
        '$appData\\Microsoft\\Windows\\Start Menu\\Programs',
    };

    final byPath = <String, WindowsAppInfo>{};
    for (final dirPath in startMenuDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(recursive: true, followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entity in entries) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.lnk')) continue;
        final targetPath = _resolveShortcut(entity.path);
        if (targetPath == null || !targetPath.toLowerCase().endsWith('.exe')) continue;
        if (byPath.containsKey(targetPath)) continue;
        if (!File(targetPath).existsSync()) continue;

        final name = entity.uri.pathSegments.last.replaceAll('.lnk', '');
        final icon = _extractIconRgba(targetPath);
        byPath[targetPath] = WindowsAppInfo(
          name: name,
          exePath: targetPath,
          iconRgba: icon?.$1,
          iconSize: icon?.$2,
        );
      }
    }

    final apps = byPath.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  } finally {
    if (needsUninit) CoUninitialize();
  }
}

String? _resolveShortcut(String lnkPath) {
  final shellLink = ShellLink.createInstance();
  try {
    final persistFile = IPersistFile.from(shellLink);
    try {
      final pathPtr = lnkPath.toNativeUtf16();
      try {
        if (FAILED(persistFile.load(pathPtr, 0))) return null;
      } finally {
        free(pathPtr);
      }

      // SLR_NO_UI (0x1) | SLR_NOUPDATE (0x8) — not exposed as named
      // constants in package:win32, values from shobjidl_core.h.
      shellLink.resolve(0, 0x1 | 0x8);

      final buffer = calloc<Uint16>(MAX_PATH).cast<Utf16>();
      final findData = calloc<WIN32_FIND_DATA>();
      try {
        if (FAILED(shellLink.getPath(buffer, MAX_PATH, findData, 0))) return null;
        final target = buffer.toDartString();
        return target.isEmpty ? null : target;
      } finally {
        free(buffer);
        free(findData);
      }
    } finally {
      persistFile.release();
    }
  } catch (_) {
    return null;
  } finally {
    shellLink.release();
  }
}

const _iconSize = 32;

/// Returns top-down BGRA8888 pixels + side length, or null on failure.
/// Never throws — icon extraction is best-effort, callers fall back to a
/// placeholder icon.
(Uint8List, int)? _extractIconRgba(String exePath) {
  final pathPtr = exePath.toNativeUtf16();
  final phicon = calloc<IntPtr>(1);
  try {
    final extracted = PrivateExtractIcons(pathPtr, 0, _iconSize, _iconSize, phicon, nullptr, 1, 0);
    if (extracted == 0 || extracted == 0xFFFFFFFF || phicon.value == 0) return null;
    final hIcon = phicon.value;

    final iconInfo = calloc<ICONINFO>();
    try {
      if (GetIconInfo(hIcon, iconInfo) == 0) return null;
      final hbmColor = iconInfo.ref.hbmColor;
      try {
        if (hbmColor == 0) return null;

        final bmp = calloc<BITMAP>();
        try {
          if (GetObject(hbmColor, sizeOf<BITMAP>(), bmp) == 0) return null;
          final width = bmp.ref.bmWidth;
          final height = bmp.ref.bmHeight;
          if (width <= 0 || height <= 0 || width > 256 || height > 256) return null;

          final hdc = GetDC(NULL);
          try {
            final bmi = calloc<BITMAPINFO>();
            try {
              bmi.ref.bmiHeader
                ..biSize = sizeOf<BITMAPINFOHEADER>()
                ..biWidth = width
                ..biHeight = -height // negative = top-down, avoids manual row flipping
                ..biPlanes = 1
                ..biBitCount = 32
                ..biCompression = BI_RGB;

              final bufSize = width * height * 4;
              final buf = calloc<Uint8>(bufSize);
              try {
                final lines = GetDIBits(hdc, hbmColor, 0, height, buf.cast(), bmi, DIB_RGB_COLORS);
                if (lines == 0) return null;
                return (Uint8List.fromList(buf.asTypedList(bufSize)), width);
              } finally {
                free(buf);
              }
            } finally {
              free(bmi);
            }
          } finally {
            ReleaseDC(NULL, hdc);
          }
        } finally {
          free(bmp);
        }
      } finally {
        DeleteObject(hbmColor);
        if (iconInfo.ref.hbmMask != 0) DeleteObject(iconInfo.ref.hbmMask);
      }
    } finally {
      free(iconInfo);
      DestroyIcon(hIcon);
    }
  } catch (_) {
    return null;
  } finally {
    free(phicon);
    free(pathPtr);
  }
}
