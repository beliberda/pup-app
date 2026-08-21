import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/split_tunneling/model/windows_app_info.dart';
import 'package:hiddify/features/split_tunneling/notifier/windows_apps_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Windows split-tunneling app picker: ticking an app writes its resolved
/// .exe path into the current rule's processPaths (see
/// SelectedWindowsAppsNotifier). Manual text entry for processPath remains
/// available from RulePage for apps this picker can't find (e.g. UWP apps,
/// or anything without a Start Menu shortcut).
class WindowsAppsPage extends HookConsumerWidget {
  const WindowsAppsPage({super.key, this.ruleListOrder});

  final int? ruleListOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final localizations = MaterialLocalizations.of(context);
    final searchController = useTextEditingController();
    ref.listen(windowsAppsSearchQueryProvider, (_, next) => searchController.text = next);
    final focusNode = useFocusNode();

    final selectedNotifier = SelectedWindowsAppsProvider(ruleListOrder);
    final selected = ref.watch(selectedNotifier);
    final apps = ref.watch(filteredWindowsAppsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.routing.routeRule.windowsApps.pageTitle),
        actions: [
          if (selected.isNotEmpty)
            IconButton(
              onPressed: ref.read(selectedNotifier.notifier).clearSelection,
              icon: const Icon(Icons.clear_all_rounded),
              tooltip: t.pages.settings.routing.routeRule.windowsApps.clearSelection,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kMinInteractiveDimension),
          child: TextField(
            focusNode: focusNode,
            controller: searchController,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              label: Text(localizations.searchFieldLabel),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        ref.read(windowsAppsSearchQueryProvider.notifier).clear();
                        focusNode.unfocus();
                      },
                      icon: const Icon(Icons.cancel_outlined),
                    )
                  : null,
            ),
            onChanged: (value) => ref.read(windowsAppsSearchQueryProvider.notifier).setQuery(value),
          ),
        ),
      ),
      body: apps.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(t.pages.settings.routing.routeRule.windowsApps.noneFound));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final app = items[index];
              return CheckboxListTile(
                title: Text(app.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(app.exePath, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                secondary: SizedBox(width: 32, height: 32, child: _AppIcon(app: app)),
                value: selected.contains(app.exePath),
                onChanged: (_) => ref.read(selectedNotifier.notifier).onChanged(app.exePath),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _AppIcon extends HookWidget {
  const _AppIcon({required this.app});

  final WindowsAppInfo app;

  @override
  Widget build(BuildContext context) {
    final rgba = app.iconRgba;
    final size = app.iconSize;
    if (rgba == null || size == null) {
      return const Icon(Icons.desktop_windows_rounded);
    }

    final image = useFuture(useMemoized(() => _decode(rgba, size), [app.exePath]));
    if (!image.hasData) return const SizedBox.shrink();
    return RawImage(image: image.data, width: 32, height: 32);
  }

  static Future<ui.Image> _decode(Uint8List pixels, int size) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }
}
