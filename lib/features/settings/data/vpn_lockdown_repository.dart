import 'package:flutter/services.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:loggy/loggy.dart';

/// Opens Android's system VPN settings screen so the user can manually enable
/// "Always-on VPN" + "Block connections without VPN" for this app.
///
/// Android does not let an app enable this for itself (by design, for user
/// safety), and there is no reliable public API for a normal app to query
/// whether it's currently enabled — so this can only open the screen and
/// explain why, not detect or toggle the state itself.
/// See PLAN.md §5.4, tasks/03-stealth-hardening.md.
abstract interface class VpnLockdownRepository {
  Future<bool> openSystemVpnSettings();
}

class VpnLockdownRepositoryImpl with InfraLogger implements VpnLockdownRepository {
  final _methodChannel = const MethodChannel("com.hiddify.app/platform");

  @override
  Future<bool> openSystemVpnSettings() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>("open_vpn_settings");
      return result ?? false;
    } catch (e) {
      loggy.log(LogLevel.error, e.toString());
      return false;
    }
  }
}
