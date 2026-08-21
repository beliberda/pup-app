import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/selfcheck/model/selfcheck_models.dart';
import 'package:hiddify/features/selfcheck/notifier/selfcheck_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SelfCheckPage extends HookConsumerWidget {
  const SelfCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final activeProfile = ref.watch(activeProfileProvider);
    final profileId = activeProfile.valueOrNull?.id;

    if (profileId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.pages.selfCheck.title)),
        body: Center(child: Text(t.pages.selfCheck.notRunYet)),
      );
    }

    final state = ref.watch(selfCheckNotifierProvider(profileId));

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.selfCheck.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.pages.selfCheck.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const Gap(16),
          _VerdictBanner(state: state, t: t),
          const Gap(16),
          switch (state) {
            AsyncData(value: final report?) => Column(
              children: [
                for (final item in report.items) _CheckTile(item: item, t: t),
              ],
            ),
            AsyncError(:final error) => ListTile(
              leading: const Icon(Icons.error_outline_rounded, color: Colors.red),
              title: Text(t.pages.selfCheck.status.error),
              subtitle: Text('$error'),
            ),
            AsyncLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            _ => Text(t.pages.selfCheck.notRunYet),
          },
          const Gap(24),
          FilledButton.icon(
            onPressed: state.isLoading ? null : () => ref.read(selfCheckNotifierProvider(profileId).notifier).run(),
            icon: const Icon(Icons.security_rounded),
            label: Text(state.hasValue && state.value != null ? t.pages.selfCheck.rerun : t.pages.selfCheck.run),
          ),
          const Gap(16),
          Text(
            t.pages.selfCheck.limitationNotice,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.state, required this.t});

  final AsyncValue<SelfCheckReport?> state;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final report = state.valueOrNull;
    final verdict = report?.verdict ?? CheckStatus.info;
    final label = switch (verdict) {
      CheckStatus.good => t.pages.selfCheck.verdict.good,
      CheckStatus.warning => t.pages.selfCheck.verdict.warning,
      CheckStatus.bad => t.pages.selfCheck.verdict.bad,
      _ => t.pages.selfCheck.verdict.info,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _statusColor(verdict).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor(verdict).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(verdict), color: _statusColor(verdict)),
          const Gap(12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.item, required this.t});

  final SelfCheckItem item;
  final Translations t;

  String get _title => switch (item.id) {
    'localPorts' => t.pages.selfCheck.items.localPorts.title,
    'interfaceName' => t.pages.selfCheck.items.interfaceName.title,
    'profileSecurity' => t.pages.selfCheck.items.profileSecurity.title,
    'ipReputation' => t.pages.selfCheck.items.ipReputation.title,
    'cdnColo' => t.pages.selfCheck.items.cdnColo.title,
    'rtt' => t.pages.selfCheck.items.rtt.title,
    'dnsLeak' => t.pages.selfCheck.items.dnsLeak.title,
    'transportVpn' => t.pages.selfCheck.items.transportVpn.title,
    _ => item.id,
  };

  String get _statusLabel => switch (item.status) {
    CheckStatus.good => t.pages.selfCheck.status.good,
    CheckStatus.warning => t.pages.selfCheck.status.warning,
    CheckStatus.bad => t.pages.selfCheck.status.bad,
    CheckStatus.info => t.pages.selfCheck.status.info,
    CheckStatus.error => t.pages.selfCheck.status.error,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(_statusIcon(item.status), color: _statusColor(item.status)),
        title: Text(_title),
        subtitle: Text(_statusLabel, style: TextStyle(color: _statusColor(item.status))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.centerLeft,
        children: [Align(alignment: Alignment.centerLeft, child: Text(item.detail))],
      ),
    );
  }
}

Color _statusColor(CheckStatus status) => switch (status) {
  CheckStatus.good => Colors.green,
  CheckStatus.warning => Colors.orange,
  CheckStatus.bad => Colors.red,
  CheckStatus.info => Colors.blueGrey,
  CheckStatus.error => Colors.grey,
};

IconData _statusIcon(CheckStatus status) => switch (status) {
  CheckStatus.good => Icons.check_circle_rounded,
  CheckStatus.warning => Icons.warning_rounded,
  CheckStatus.bad => Icons.dangerous_rounded,
  CheckStatus.info => Icons.info_rounded,
  CheckStatus.error => Icons.error_rounded,
};
