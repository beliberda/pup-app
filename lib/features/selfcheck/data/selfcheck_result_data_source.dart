import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/selfcheck/model/selfcheck_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';

part 'selfcheck_result_data_source.g.dart';

abstract interface class SelfCheckResultDataSource {
  Future<SelfCheckReport?> getByProfileId(String profileId);
  Stream<SelfCheckReport?> watchByProfileId(String profileId);
  Future<void> upsert({required String profileId, required SelfCheckReport report});
  Future<void> deleteByProfileId(String profileId);
}

@DriftAccessor(tables: [SelfCheckResultEntries])
class SelfCheckResultDao extends DatabaseAccessor<Db> with _$SelfCheckResultDaoMixin, InfraLogger
    implements SelfCheckResultDataSource {
  SelfCheckResultDao(super.db);

  @override
  Future<SelfCheckReport?> getByProfileId(String profileId) async {
    final entry = await (select(
      selfCheckResultEntries,
    )..where((tbl) => tbl.profileId.equals(profileId))).getSingleOrNull();
    return _toReport(entry);
  }

  @override
  Stream<SelfCheckReport?> watchByProfileId(String profileId) {
    return (select(selfCheckResultEntries)..where((tbl) => tbl.profileId.equals(profileId)))
        .watchSingleOrNull()
        .map(_toReport);
  }

  @override
  Future<void> upsert({required String profileId, required SelfCheckReport report}) {
    return into(selfCheckResultEntries).insertOnConflictUpdate(
      SelfCheckResultEntriesCompanion.insert(
        profileId: profileId,
        itemsJson: jsonEncode(report.itemsToJson()),
        verdict: report.verdict,
        generatedAt: report.generatedAt,
      ),
    );
  }

  @override
  Future<void> deleteByProfileId(String profileId) {
    return (delete(selfCheckResultEntries)..where((tbl) => tbl.profileId.equals(profileId))).go();
  }

  SelfCheckReport? _toReport(SelfCheckResultEntry? entry) {
    if (entry == null) return null;
    return SelfCheckReport.fromItemsJson(jsonDecode(entry.itemsJson) as List<dynamic>, entry.generatedAt);
  }
}
