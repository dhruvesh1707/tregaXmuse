import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../firebase/firestore_service.dart';

/// Strict force-update gate: minimum installable build numbers.
///
/// The minimums live in the `config/app` Firestore doc (public read,
/// console-only write, same pattern as `config/delivery`), so the team
/// can raise the floor without an app release. A minimum of 0 (or a
/// missing doc or field) means unenforced for that platform.
///
/// Comparison is build numbers only, never version name strings. Every
/// failure fails open: any error, timeout, or unparseable build number
/// lets the user through, so a bad config can never lock everyone out.
class ForceUpdateConfig {
  final int minAndroidBuild;
  final int minIosBuild;

  const ForceUpdateConfig({
    required this.minAndroidBuild,
    required this.minIosBuild,
  });

  /// Bundled defaults, used until (and unless) `config/app` exists.
  /// Zero means unenforced.
  static const ForceUpdateConfig defaults = ForceUpdateConfig(
    minAndroidBuild: 0,
    minIosBuild: 0,
  );

  factory ForceUpdateConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    final androidRaw = map['minAndroidBuild'];
    final iosRaw = map['minIosBuild'];
    return ForceUpdateConfig(
      minAndroidBuild:
          androidRaw is num ? androidRaw.toInt() : defaults.minAndroidBuild,
      minIosBuild: iosRaw is num ? iosRaw.toInt() : defaults.minIosBuild,
    );
  }
}

/// True only when the installed build is below the enforced minimum for
/// this platform. Fails open: any error returns false.
Future<bool> isForceUpdateRequired(FirestoreService service) async {
  try {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS) {
      return false;
    }
    final data =
        await service.getAppConfig().timeout(const Duration(seconds: 4));
    final config = ForceUpdateConfig.fromMap(data);
    final minimum = platform == TargetPlatform.android
        ? config.minAndroidBuild
        : config.minIosBuild;
    if (minimum <= 0) return false;
    final info = await PackageInfo.fromPlatform();
    final installed = int.tryParse(info.buildNumber);
    if (installed == null) return false;
    return installed < minimum;
  } catch (_) {
    return false;
  }
}
