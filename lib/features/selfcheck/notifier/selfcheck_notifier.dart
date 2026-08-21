import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/selfcheck/data/selfcheck_data_providers.dart';
import 'package:hiddify/features/selfcheck/model/selfcheck_models.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selfcheck_notifier.g.dart';

/// Self-check screen (PLAN.md §4.5): runs the same class of checks a
/// background app without root could run against this device, so the user
/// can see what's actually detectable right now, on their current server and
/// config — not just a static write-up.
///
/// Keyed by profile id so the last result for each profile is cached
/// (loaded from [SelfCheckResultDataSource]) instead of forcing a re-run
/// every time the user switches profiles.
///
/// Detail text is localized at run() time using the app's current locale and
/// baked into the stored [SelfCheckItem.detail] string — if the user changes
/// the app language afterwards, a cached report keeps its old-locale text
/// until the next re-run.
@riverpod
class SelfCheckNotifier extends _$SelfCheckNotifier with AppLogger {
  @override
  Future<SelfCheckReport?> build(String profileId) {
    return ref.watch(selfCheckResultDataSourceProvider).getByProfileId(profileId);
  }

  Future<void> run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final report = await _runChecks();
      await ref.read(selfCheckResultDataSourceProvider).upsert(profileId: profileId, report: report);
      return report;
    });
  }

  Future<SelfCheckReport> _runChecks() async {
    final t = ref.read(translationsProvider).requireValue;
    final items = t.pages.selfCheck.items;
    final signatures = await _loadSignatures();
    final serviceRunning = ref.read(serviceRunningProvider);
    final client = ref.read(httpClientProvider);

    final results = <SelfCheckItem>[
      await _checkLocalPorts(client, t),
      await _checkInterfaceName(signatures, serviceRunning, t),
      if (serviceRunning) ...[
        await _checkIpReputation(client, signatures, t),
        await _checkCdnColo(client, signatures, t),
        await _checkRtt(client, signatures, t),
      ] else ...[
        SelfCheckItem(id: 'ipReputation', status: CheckStatus.info, detail: items.ipReputation.detail.notConnected),
        SelfCheckItem(id: 'cdnColo', status: CheckStatus.info, detail: items.cdnColo.detail.notConnected),
        SelfCheckItem(id: 'rtt', status: CheckStatus.info, detail: items.rtt.detail.notConnected),
      ],
      SelfCheckItem(id: 'dnsLeak', status: CheckStatus.info, detail: items.dnsLeak.detail),
      SelfCheckItem(id: 'transportVpn', status: CheckStatus.info, detail: items.transportVpn.detail),
    ];

    return SelfCheckReport(items: results, generatedAt: DateTime.now());
  }

  Future<Map<String, dynamic>> _loadSignatures() async {
    final raw = await rootBundle.loadString('assets/selfcheck_signatures.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<SelfCheckItem> _checkLocalPorts(DioHttpClient client, Translations t) async {
    final labels = t.pages.selfCheck.items.localPorts.labels;
    final checks = <(String label, bool shouldBeClosed, int port)>[
      (labels.clashApi, !ref.read(ConfigOptions.enableClashApi), ref.read(ConfigOptions.clashApiPort)),
      (labels.tproxyInbound, !ref.read(ConfigOptions.enableTproxyPort), ref.read(ConfigOptions.tproxyPort)),
      (labels.redirectInbound, !ref.read(ConfigOptions.enableRedirectPort), ref.read(ConfigOptions.redirectPort)),
      (labels.directInbound, !ref.read(ConfigOptions.enableDirectPort), ref.read(ConfigOptions.directPort)),
    ];

    final detail = t.pages.selfCheck.items.localPorts.detail;
    final lines = <String>[];
    var severity = 0;

    for (final (label, shouldBeClosed, port) in checks) {
      if (!shouldBeClosed) {
        lines.add(detail.enabledInSettings(label: label, port: port));
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
        lines.add(detail.openUnexpected(label: label, port: port));
        severity = 2;
      } else {
        lines.add(detail.closedAsExpected(label: label));
      }
    }

    final mixedPort = ref.read(ConfigOptions.mixedPort);
    lines.add(detail.mixedInbound(port: mixedPort));

    final status = switch (severity) {
      2 => CheckStatus.bad,
      1 => CheckStatus.warning,
      _ => CheckStatus.good,
    };
    return SelfCheckItem(id: 'localPorts', status: status, detail: lines.join('\n'));
  }

  Future<SelfCheckItem> _checkInterfaceName(Map<String, dynamic> signatures, bool serviceRunning, Translations t) async {
    final detail = t.pages.selfCheck.items.interfaceName.detail;
    if (!serviceRunning) {
      return SelfCheckItem(id: 'interfaceName', status: CheckStatus.info, detail: detail.notConnected);
    }

    final patterns = (signatures['suspiciousInterfacePatterns'] as List)
        .cast<String>()
        .map((p) => RegExp(p, caseSensitive: false))
        .toList();

    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(includeLoopback: false);
    } catch (e) {
      return SelfCheckItem(id: 'interfaceName', status: CheckStatus.error, detail: detail.error(error: e));
    }

    final names = interfaces.map((i) => i.name).toList();
    final suspicious = names.where((name) => patterns.any((p) => p.hasMatch(name))).toSet();

    if (suspicious.isEmpty) {
      return SelfCheckItem(id: 'interfaceName', status: CheckStatus.good, detail: detail.good(names: names.join(', ')));
    }
    return SelfCheckItem(
      id: 'interfaceName',
      status: CheckStatus.warning,
      detail: detail.warning(names: names.join(', '), suspicious: suspicious.join(', ')),
    );
  }

  Future<SelfCheckItem> _checkIpReputation(DioHttpClient client, Map<String, dynamic> signatures, Translations t) async {
    final detail = t.pages.selfCheck.items.ipReputation.detail;
    final flagLabels = t.pages.selfCheck.items.ipReputation.flags;
    final endpoint = signatures['ipReputationEndpoint'] as String;
    try {
      final response = await client.get<Map<String, dynamic>>(endpoint, proxyOnly: true);
      final data = response.data;
      if (data == null) throw const FormatException('empty response');

      final flags = <String>[
        if (data['is_datacenter'] == true) flagLabels.datacenter,
        if (data['is_vpn'] == true) flagLabels.vpn,
        if (data['is_proxy'] == true) flagLabels.proxy,
        if (data['is_tor'] == true) flagLabels.tor,
      ];
      final ip = data['ip']?.toString() ?? '?';
      final company = data['company'] is Map ? (data['company']['name']?.toString() ?? '') : '';
      final label = company.isEmpty ? ip : '$ip ($company)';

      if (flags.isEmpty) {
        return SelfCheckItem(id: 'ipReputation', status: CheckStatus.good, detail: detail.good(label: label));
      }
      return SelfCheckItem(
        id: 'ipReputation',
        status: CheckStatus.bad,
        detail: detail.bad(label: label, flags: flags.join(', ')),
      );
    } catch (e) {
      return SelfCheckItem(id: 'ipReputation', status: CheckStatus.error, detail: detail.error(endpoint: endpoint, error: e));
    }
  }

  Future<SelfCheckItem> _checkCdnColo(DioHttpClient client, Map<String, dynamic> signatures, Translations t) async {
    final detail = t.pages.selfCheck.items.cdnColo.detail;
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
      return SelfCheckItem(id: 'cdnColo', status: CheckStatus.info, detail: detail.info(colo: colo, loc: loc));
    } catch (e) {
      return SelfCheckItem(id: 'cdnColo', status: CheckStatus.error, detail: detail.error(endpoint: endpoint, error: e));
    }
  }

  Future<SelfCheckItem> _checkRtt(DioHttpClient client, Map<String, dynamic> signatures, Translations t) async {
    final detail = t.pages.selfCheck.items.rtt.detail;
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
      return SelfCheckItem(id: 'rtt', status: CheckStatus.error, detail: detail.notEnoughData);
    }

    final avgRu = ruTimes.reduce((a, b) => a + b) / ruTimes.length;
    final avgForeign = foreignTimes.reduce((a, b) => a + b) / foreignTimes.length;
    final avgRuStr = avgRu.toStringAsFixed(0);
    final avgForeignStr = avgForeign.toStringAsFixed(0);

    if (avgRu <= avgForeign) {
      return SelfCheckItem(id: 'rtt', status: CheckStatus.good, detail: detail.good(avgRu: avgRuStr, avgForeign: avgForeignStr));
    }
    return SelfCheckItem(id: 'rtt', status: CheckStatus.warning, detail: detail.warning(avgRu: avgRuStr, avgForeign: avgForeignStr));
  }
}
