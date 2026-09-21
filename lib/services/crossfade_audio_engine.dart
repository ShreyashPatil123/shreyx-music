import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrossfadeAudioEngine {
  static final CrossfadeAudioEngine _instance = CrossfadeAudioEngine._internal();

  factory CrossfadeAudioEngine() {
    return _instance;
  }

  CrossfadeAudioEngine._internal();

  static const String _crossfadeKey = 'shrex_crossfade_seconds';
  int _crossfadeSeconds = 0;

  int get crossfadeSeconds => _crossfadeSeconds;
  Duration get crossfadeDuration => Duration(seconds: _crossfadeSeconds);

  bool get isEnabled => _crossfadeSeconds > 0;

  ({double currentVolume, double nextVolume}) calculateVolumes(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return (
      currentVolume: cos(p * pi / 2),
      nextVolume: sin(p * pi / 2),
    );
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _crossfadeSeconds = prefs.getInt(_crossfadeKey) ?? 0;
      debugPrint('[Crossfade] Initialized with $_crossfadeSeconds seconds');
    } catch (e) {
      debugPrint('[Crossfade] Error initializing: $e');
    }
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    if (![0, 3, 5, 8, 12].contains(seconds)) {
      debugPrint('[Crossfade] Invalid crossfade duration: $seconds');
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_crossfadeKey, seconds);
      _crossfadeSeconds = seconds;
      debugPrint('[Crossfade] Set crossfade to $_crossfadeSeconds seconds');
    } catch (e) {
      debugPrint('[Crossfade] Error setting crossfade: $e');
    }
  }

  bool shouldStartCrossfade(Duration currentPosition, Duration totalDuration) {
    if (!isEnabled) return false;
    
    final crossfadeDuration = Duration(seconds: _crossfadeSeconds);
    if (totalDuration <= crossfadeDuration * 2) {
      return false; // Prevent crossfade on very short tracks
    }

    return (totalDuration - currentPosition) <= crossfadeDuration;
  }

  double calculateFadeOutVolume(Duration currentPosition, Duration totalDuration) {
    if (!isEnabled) return 1.0;
    
    final crossfadeDuration = Duration(seconds: _crossfadeSeconds);
    if (totalDuration <= crossfadeDuration * 2) return 1.0;
    
    final remaining = totalDuration - currentPosition;
    if (remaining > crossfadeDuration) return 1.0;
    
    // Elapsed into crossfade region
    final elapsed = crossfadeDuration - remaining;
    final progress = elapsed.inMilliseconds / crossfadeDuration.inMilliseconds;
    final clampedProgress = progress.clamp(0.0, 1.0);
    
    // Equal-power crossfade curve: cos(progress * pi / 2)
    return cos(clampedProgress * pi / 2);
  }

  double calculateFadeInVolume(Duration currentPosition, Duration totalDuration) {
    if (!isEnabled) return 1.0;
    
    final crossfadeDuration = Duration(seconds: _crossfadeSeconds);
    if (totalDuration <= crossfadeDuration * 2) return 1.0;
    
    if (currentPosition > crossfadeDuration) return 1.0;
    
    final progress = currentPosition.inMilliseconds / crossfadeDuration.inMilliseconds;
    final clampedProgress = progress.clamp(0.0, 1.0);
    
    // Equal-power crossfade curve: sin(progress * pi / 2)
    return sin(clampedProgress * pi / 2);
  }
}
