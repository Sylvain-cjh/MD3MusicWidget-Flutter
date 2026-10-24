import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class FontCredits {
  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(() async* {
      final notice = await rootBundle.loadString(
        'assets/fonts/MiSans-NOTICE.txt',
      );
      yield LicenseEntryWithLineBreaks(const ['MiSans'], notice);
    });
  }
}
