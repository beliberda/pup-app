import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/split_tunneling/data/windows_installed_apps_source.dart';
import 'package:hiddify/features/split_tunneling/model/windows_app_info.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'windows_apps_notifier.g.dart';

@riverpod
WindowsInstalledAppsSource windowsInstalledAppsSource(Ref ref) => WindowsInstalledAppsSourceImpl();

@riverpod
Future<List<WindowsAppInfo>> windowsApps(Ref ref) {
  return ref.watch(windowsInstalledAppsSourceProvider).getInstalledApps();
}

@riverpod
class WindowsAppsSearchQuery extends _$WindowsAppsSearchQuery {
  @override
  String build() => '';

  void setQuery(String query) => state = query.trim();

  void clear() => state = '';
}

@riverpod
Future<List<WindowsAppInfo>> filteredWindowsApps(Ref ref) async {
  final query = ref.watch(windowsAppsSearchQueryProvider).toLowerCase();
  final apps = await ref.watch(windowsAppsProvider.future);
  if (query.isEmpty) return apps;
  return apps.where((app) => app.name.toLowerCase().contains(query)).toList();
}

/// Selection state for the process-path picker, backed directly by the
/// rule's `processPaths` field — mirrors the (commented-out)
/// SelectedPackagesNotifier pattern used for Android's packageName field.
@riverpod
class SelectedWindowsApps extends _$SelectedWindowsApps {
  late int? _ruleListOrder;
  final _ruleEnum = RuleEnum.processPath;

  @override
  List<String> build(int? ruleListOrder) {
    _ruleListOrder = ruleListOrder;
    final value = ref.read(ruleNotifierProvider(ruleListOrder)).writeToJsonMap()['${_ruleEnum.getIndex()}'];
    if (value is List) return value.cast<String>();
    return [];
  }

  void onChanged(String exePath) {
    if (state.contains(exePath)) {
      state = List.from(state)..removeWhere((element) => element == exePath);
    } else {
      state = [...state, exePath];
    }
    _save();
  }

  void clearSelection() {
    state = [];
    _save();
  }

  void _save() => ref.read(ruleNotifierProvider(_ruleListOrder).notifier).update<List<dynamic>>(_ruleEnum, state);
}
