import 'package:flutter/foundation.dart';

void logInfo(String message) {
  debugPrint('[INFO] $message');
}

void logError(String message, [Object? error, StackTrace? stackTrace]) {
  debugPrint('[ERROR] $message');
  if (error != null) {
    debugPrint('  └─ $error');
  }
  if (stackTrace != null) {
    debugPrint('$stackTrace');
  }
}


