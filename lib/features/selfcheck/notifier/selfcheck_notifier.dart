import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/selfcheck/model/selfcheck_models.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selfcheck_notifier.g.dart';

/// Self-check screen (PLAN.md §4.5): runs the same class of checks a
/// background app without root could run against this device, so the user
/// can see what's actually detectable right now, on their current server and
/// config — not just a static write-up.
@riverpod
class SelfCheckNotifier extends _$SelfCheckNotifier with AppLogger {
  @override
  Future<SelfCheckReport?> build() async => null;

  Future<void> run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_runChecks);
  }

  Future<SelfCheckReport> _runChecks() async {
    final signatures = await _loadSignatures();
    final serviceRunning = ref.read(serviceRunningProvider);
    final client = ref.read(httpClientProvider);

    final items = <SelfCheckItem>[
      await _checkLocalPorts(client),
      await _checkInterfaceName(signatures, serviceRunning),
      if (serviceRunning) ...[
        await _checkIpReputation(client, signatures),
        await _checkCdnColo(client, signatures),
        await _checkRtt(client, signatures),
      ] else ...[
        const SelfCheckItem(
          id: 'ipReputation',
          status: CheckStatus.info,
          detail: 'VPN is not connected — connect the tunnel to check the exit IP reputation.',
        ),
        const SelfCheckItem(
          id: 'cdnColo',
          status: CheckStatus.info,
          detail: 'VPN is not connected — connect the tunnel to check the CDN edge location.',
        ),
        const SelfCheckItem(
          id: 'rtt',
          status: CheckStatus.info,
          detail: 'VPN is not connected — connect the tunnel to measure RTT triangulation.',
        ),
      ],
      const SelfCheckItem(
        id: 'dnsLeak',
        status: CheckStatus.info,
        detail:
            'Not automated here — DNS/WebRTC/IPv6 leaks need a real browser context '
            '(WebRTC in particular can\'t be probed from Dart). Check manually with '
            'browserleaks.com or ipleak.net while connected, especially after changing '
            'routing rules.',
      ),
      const SelfCheckItem(
        id: 'transportVpn',
        status: CheckStatus.info,
        detail:
            'Any app can see that some VPN is active on this device via the official '
            'ConnectivityManager/NEVPNManager API (TRANSPORT_VPN) — this is expected OS '
            'behavior and can\'t be hidden without root/jailbreak. It reveals only "a VPN '
            'is on", never which one or the server IP, so it is not treated as a finding here.',
      ),
    ];

    return SelfCheckReport(items: items, generatedAt: DateTime.now());
  }

  Future<Map<String, dynamic>> _loadSignatures() async {
    final raw = await rootBundle.loadString('assets/selfcheck_signatures.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<SelfCheckItem> _checkLocalPorts(DioHttpClient client) async {
    final checks = <(String label, bool shouldBeClosed, int port)>[
      ('Clash API', !ref.read(ConfigOptions.enableClashApi), ref.read(ConfigOptions.clashApiPort)),
      ('TProxy inbound', !ref.read(ConfigOptions.enableTproxyPort), ref.read(ConfigOptions.tproxyPort)),
      ('Redirect inbound', !ref.read(ConfigOptions.enableRedirectPort), ref.read(ConfigOptions.redirectPort)),
      ('Direct inbound', !ref.read(ConfigOptions.enableDirectPort), ref.read(ConfigOptions.directPort)),
    ];

    final lines = <String>[];
    var severity = 0;

    for (final (label, shouldBeClosed, port) in checks) {
      if (!shouldBeClosed) {
        lines.add(
          '$label: enabled in settings (port $port) — this opens a local API reachable by '
          'any app with plain INTERNET permission on 127.0.0.1.',
        );
        severity = severity < 1 ? 1 : severity;
        continue;
      }
      bool open;
      try {
        open = await client.isPortOpen('127.0.0.1', port);
      } catch (_) {
        open = false;
      }
      if (open) {
        lines.add('$label: port $port is OPEN even though it\'s disabled in settings — unexpected.');
        severity = 2;
      } else {
        lines.add('$label: closed, as expected.');
      }
    }

    final mixedPort = ref.read(ConfigOptions.mixedPort);
    lines.add(
      'Mixed SOCKS/HTTP inbound: always on (port $mixedPort, randomized per install), no auth '
      'token — this is the engine\'s only unconditional local inbound, and by design of the '
      'TUN mode it can\'t be disabled from this client.',
    );

    final status = switch (severity) {
      2 => CheckStatus.bad,
      1 => CheckStatus.warning,
      _ => CheckStatus.good,
    };
    return SelfCheckItem(id: 'localPorts', status: status, detail: lines.join('\n'));
  }

  Future<SelfCheckItem> _checkInterfaceName(Map<String, dynamic> signatures, bool serviceRunning) async {
    if (!serviceRunning) {
      return const SelfCheckItem(
        id: 'interfaceName',
        status: CheckStatus.info,
        detail: 'VPN is not connected — connect the tunnel to check the active interface name.',
      );
    }

    final patterns = (signatures['suspiciousInterfacePatterns'] as List)
        .cast<String>()
        .map((p) => RegExp(p, caseSensitive: false))
        .toList();

    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(includeLoopback: false);
    } catch (e) {
      return SelfCheckItem(id: 'interfaceName', status: CheckStatus.error, detail: 'Could not list network interfaces: $e');
    }

    final names = interfaces.map((i) => i.name).toList();
    final suspicious = names.where((name) => patterns.any((p) => p.hasMatch(name))).toSet();

    if (suspicious.isEmpty) {
      return SelfCheckItem(
        id: 'interfaceName',
        status: CheckStatus.good,
        detail: 'Active interfaces: ${names.join(', ')}. None match default VPN naming patterns.',
      );
    }
    return SelfCheckItem(
      id: 'interfaceName',
      status: CheckStatus.warning,
      detail:
          'Active interfaces: ${names.join(', ')}. Default-looking names: ${suspicious.join(', ')} — naive '
          'detectors regex-match tun/tap/wg/utun/ppp interface names. A rename is already written in the '
          'engine source but is inactive until the native engine is rebuilt from source (see '
          'tasks/03-stealth-hardening.md, "Сетевой интерфейс").',
    );
  }

  Future<SelfCheckItem> _checkIpReputation(DioHttpClient client, Map<String, dynamic> signatures) async {
    final endpoint = signatures['ipReputationEndpoint'] as String;
    try {
      final response = await client.get<Map<String, dynamic>>(endpoint, proxyOnly: true);
      final data = response.data;
      if (data == null) throw const FormatException('empty response');

      final flags = <String>[
        if (data['is_datacenter'] == true) 'datacenter',
        if (data['is_vpn'] == true) 'vpn',
        if (data['is_proxy'] == true) 'proxy',
        if (data['is_tor'] == true) 'tor',
      ];
      final ip = data['ip']?.toString() ?? '?';
      final company = data['company'] is Map ? (data['company']['name']?.toString() ?? '') : '';
      final label = company.isEmpty ? ip : '$ip ($company)';

      if (flags.isEmpty) {
        return SelfCheckItem(
          id: 'ipReputation',
          status: CheckStatus.good,
          detail: 'Exit IP $label is not flagged by ipapi.is as datacenter/VPN/proxy/Tor.',
        );
      }
      return SelfCheckItem(
        id: 'ipReputation',
        status: CheckStatus.bad,
        detail:
            'Exit IP $label is flagged: ${flags.join(', ')}. This is the main real-world detection vector '
            '(GeoIP-based checks used by banks/marketplaces) — it\'s fixed by choosing a server IP with a '
            'clean reputation, not by any setting in this client.',
      );
    } catch (e) {
      return SelfCheckItem(id: 'ipReputation', status: CheckStatus.error, detail: 'Could not reach $endpoint through the tunnel: $e');
    }
  }

  Future<SelfCheckItem> _checkCdnColo(DioHttpClient client, Map<String, dynamic> signatures) async {
    final endpoint = signatures['cdnTraceEndpoint'] as String;
    try {
      final response = await client.get<String>(endpoint, proxyOnly: true);
      final body = response.data ?? '';
      final fields = {
        for (final line in body.split('\n'))
          if (line.contains('=')) line.split('=').first: line.split('=').skip(1).join('='),
      };
      final colo = fields['colo'] ?? '?';
      final loc = fields['loc'] ?? '?';
      return SelfCheckItem(
        id: 'cdnColo',
        status: CheckStatus.info,
        detail:
            'Cloudflare sees this connection arriving via edge "$colo" (its guess at your country: $loc). '
            'Informational only — compare it yourself against where your server actually is.',
      );
    } catch (e) {
      return SelfCheckItem(id: 'cdnColo', status: CheckStatus.error, detail: 'Could not reach $endpoint through the tunnel: $e');
    }
  }

  Future<SelfCheckItem> _checkRtt(DioHttpClient client, Map<String, dynamic> signatures) async {
    final hosts = signatures['rttHosts'] as Map<String, dynamic>;
    final ruHosts = (hosts['ru'] as List).cast<String>();
    final foreignHosts = (hosts['foreign'] as List).cast<String>();

    Future<int?> measure(String host) async {
      final sw = Stopwatch()..start();
      try {
        await client.get<dynamic>('https://$host/', proxyOnly: true);
        sw.stop();
        return sw.elapsedMilliseconds;
      } catch (_) {
        return null;
      }
    }

    final ruTimes = (await Future.wait(ruHosts.map(measure))).whereType<int>().toList();
    final foreignTimes = (await Future.wait(foreignHosts.map(measure))).whereType<int>().toList();

    if (ruTimes.isEmpty || foreignTimes.isEmpty) {
      return const SelfCheckItem(
        id: 'rtt',
        status: CheckStatus.error,
        detail: 'Not enough successful measurements to compare RTT (some reference hosts unreachable).',
      );
    }

    final avgRu = ruTimes.reduce((a, b) => a + b) / ruTimes.length;
    final avgForeign = foreignTimes.reduce((a, b) => a + b) / foreignTimes.length;
    final detail = 'Avg RTT to RU reference hosts: ${avgRu.toStringAsFixed(0)}ms, '
        'to foreign reference hosts: ${avgForeign.toStringAsFixed(0)}ms.';

    if (avgRu <= avgForeign) {
      return SelfCheckItem(
        id: 'rtt',
        status: CheckStatus.good,
        detail: '$detail Exit point looks geographically closer to RU than to the foreign references.',
      );
    }
    return SelfCheckItem(
      id: 'rtt',
      status: CheckStatus.warning,
      detail:
          '$detail Exit point looks farther from RU than from the foreign references — a triangulation '
          'heuristic (like RttTriangulationChecker) could read this as "probably not in/near Russia". This '
          'is a low-confidence signal, not a hard detection.',
    );
  }
}
