import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/model/environment.dart';

part 'app_info_entity.freezed.dart';

/// Short identifier for this specific build, passed in via
/// `--dart-define=BUILD_HASH=...` at build time (see scripts/build_hash.*).
/// Shown next to the version string so it's obvious at a glance whether
/// you're running a build from before or after a given change, without
/// having to trust file timestamps (which don't move when only a native
/// dependency like hiddify-core.dll changes, not the Dart/exe code itself).
const String buildHash = String.fromEnvironment('BUILD_HASH', defaultValue: 'nohash');

@freezed
class AppInfoEntity with _$AppInfoEntity {
  const AppInfoEntity._();

  const factory AppInfoEntity({
    required String name,
    required String version,
    required String buildNumber,
    required Release release,
    required String operatingSystem,
    required String operatingSystemVersion,
    required Environment environment,
  }) = _AppInfoEntity;

  String get userAgent => "Pup/$version ($operatingSystem) like ClashMeta v2ray sing-box";

  String get presentVersion {
    final base = environment == Environment.prod ? version : "$version ${environment.name}";
    return buildHash == 'nohash' ? base : "$base [$buildHash]";
  }

  /// formats app info for sharing
  String format() =>
      '''
$name v$version ($buildNumber) [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}
