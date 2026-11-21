import 'dart:convert';
import 'dart:io';

import '../platform/updater_service.dart';

/// Validate the published release feed and real installer bytes without
/// installing. The production helper is tested separately before publication.
Future<bool> runUpdateFeedSelfTest(String output) async {
  final report = <String, dynamic>{'status': 'failed'};
  final oldClient = UpdaterService(currentVersion: '1.0.0+1');
  final currentClient = UpdaterService();
  try {
    final update = await oldClient.check();
    if (update.state != UpdateState.available) {
      throw StateError('No update for baseline client.');
    }
    if (!await oldClient.download() ||
        oldClient.state != UpdateState.downloaded) {
      throw StateError('Published installer integrity validation failed.');
    }
    if ((await currentClient.check()).state != UpdateState.upToDate) {
      throw StateError(
        'The current release is incorrectly offered another update.',
      );
    }
    report.addAll({
      'status': 'passed',
      'baseline_version': '1.0.0+1',
      'available_version': update.version,
      'download_integrity': 'passed',
      'current_version_check': 'passed',
    });
  } catch (error) {
    report['error_type'] = '${error.runtimeType}';
    report['updater_error'] = oldClient.error ?? currentClient.error;
  } finally {
    oldClient.dispose();
    currentClient.dispose();
    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(report), flush: true);
  }
  return report['status'] == 'passed';
}
