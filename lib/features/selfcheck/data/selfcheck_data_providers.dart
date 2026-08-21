import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/features/selfcheck/data/selfcheck_result_data_source.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selfcheck_data_providers.g.dart';

@riverpod
SelfCheckResultDataSource selfCheckResultDataSource(Ref ref) => SelfCheckResultDao(ref.watch(dbProvider));
