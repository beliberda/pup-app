import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One-tap "load a curated app bundle into the bypass list" sheet, styled
/// after PredefinedRulesModal. Currently offers a single bundle (RU apps);
/// more regions/bundles can be appended to [_bundles] later.
class PredefinedAppsModal extends HookConsumerWidget {
  const PredefinedAppsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final bundles = _bundles(t);

    final initialSize = PlatformUtils.isDesktop ? .40 : .25;
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: initialSize,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t.pages.settings.routing.predefinedApps.title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  controller: scrollController,
                  itemBuilder: (context, index) {
                    final bundle = bundles[index];
                    return ListTile(
                      onTap: () async {
                        await ref.read(PerAppProxyProvider(AppProxyMode.exclude).notifier).loadRuPreset();
                        if (context.mounted) context.pop();
                      },
                      title: Text(
                        bundle.name,
                        style: Theme.of(context).textTheme.titleMedium!.copyWith(color: theme.colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        bundle.description,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    );
                  },
                  itemCount: bundles.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<({String name, String description})> _bundles(Translations t) => [
    (
      name: t.pages.settings.routing.predefinedApps.ruApps.name,
      description: t.pages.settings.routing.predefinedApps.ruApps.description,
    ),
  ];
}
