import 'dart:io';
import 'package:flutter/foundation.dart';

/// Centralized platform-aware network identity provider.
///
/// Provides generic standard browser User-Agents for Android, iOS, and Desktop.
/// Strictly eliminates device-specific model impersonation (such as SM-S921E / S24).
class NetworkIdentityService {
  static final NetworkIdentityService _instance = NetworkIdentityService._internal();
  factory NetworkIdentityService() => _instance;
  NetworkIdentityService._internal();

  /// Generic Android Mobile Chrome User-Agent (no specific OEM or model number)
  static const String androidUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// Generic iOS Mobile Safari User-Agent
  static const String iosUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

  /// Generic Desktop Chrome User-Agent
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// Returns the most appropriate generic User-Agent for the current execution platform.
  String get userAgent {
    if (kIsWeb) return desktopUserAgent;
    if (Platform.isAndroid) return androidUserAgent;
    if (Platform.isIOS || Platform.isMacOS) return iosUserAgent;
    return desktopUserAgent;
  }

  /// Standard HTTP request headers for YouTube CDN and media streams
  Map<String, String> get mediaStreamHeaders => {
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      };
}
