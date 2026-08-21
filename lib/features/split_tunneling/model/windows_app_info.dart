import 'dart:typed_data';

/// One installed desktop app, discovered via Start Menu shortcut resolution
/// (see WindowsInstalledAppsSource). [exePath] is the exact path resolved by
/// `IShellLink::GetPath`, which is what sing-box's process_path route
/// matcher compares against at runtime (QueryFullProcessImageName), so it
/// must be used verbatim, not re-derived or normalized.
class WindowsAppInfo {
  const WindowsAppInfo({required this.name, required this.exePath, this.iconRgba, this.iconSize});

  final String name;
  final String exePath;

  /// Top-down BGRA8888 pixel buffer of size iconSize*iconSize*4, or null if
  /// icon extraction failed for this app (falls back to a placeholder icon
  /// in the UI — extraction failure is cosmetic only, never blocks
  /// selecting the app).
  final Uint8List? iconRgba;
  final int? iconSize;
}
