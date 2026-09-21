import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for volume and loudness normalization across tracks.
///
/// Targets -14.0 LUFS (the standard streaming loudness target used by Spotify,
/// YouTube, and Apple Music) to prevent jarring volume jumps between tracks.
class AudioNormalizationService {
  static final AudioNormalizationService _instance =
      AudioNormalizationService._internal();

  factory AudioNormalizationService() => _instance;

  AudioNormalizationService._internal();

  static const String _prefsKey = 'shrex_volume_normalization';

  /// Standard streaming target loudness in LUFS / dB LKFS.
  static const double targetLoudness = -14.0;

  bool _enabled = true;
  Timer? _rampTimer;
  Completer<void>? _rampCompleter;

  /// Whether loudness normalization is currently active.
  bool get isEnabled => _enabled;

  /// Initializes the service and loads persisted settings.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
      debugPrint('[AudioNorm] Initialized (enabled: $_enabled)');
    } catch (e) {
      debugPrint('[AudioNorm] Error initializing: $e');
    }
  }

  /// Toggles volume normalization and persists the user preference.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
      debugPrint('[AudioNorm] Normalization ${value ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[AudioNorm] Error persisting enabled state: $e');
    }
  }

  /// Calculates the linear gain multiplier required to bring [loudnessDb]
  /// to the standard [targetLoudness] (-14 LUFS).
  ///
  /// - Returns 1.0 (unity gain) if normalization is disabled or [loudnessDb] is null.
  /// - Computes gain in dB as `targetLoudness - loudnessDb`.
  /// - Converts dB gain to linear scale via `pow(10, gainDb / 20)`.
  /// - Clamps the linear gain between 0.3 and 3.0 to avoid distortion or silence.
  double calculateGain(double? loudnessDb) {
    if (!_enabled || loudnessDb == null) {
      return 1.0;
    }

    final double gainDb = targetLoudness - loudnessDb;
    final double linearGain = pow(10.0, gainDb / 20.0).toDouble();
    final double clampedGain = linearGain.clamp(0.3, 3.0);

    debugPrint(
      '[AudioNorm] Track loudness: ${loudnessDb.toStringAsFixed(1)} dB, '
      'gain: ${gainDb.toStringAsFixed(1)} dB, linear: ${clampedGain.toStringAsFixed(2)}',
    );

    return clampedGain;
  }

  /// Applies volume normalization to the [player] based on [loudnessDb].
  ///
  /// Cancels any in-progress ramp timer, calculates the target linear gain,
  /// and smoothly transitions the player volume from its current level to the
  /// target gain over 300ms in 30ms increments (10 steps).
  Future<void> applyToPlayer(AudioPlayer player, double? loudnessDb) async {
    // Cancel any active ramp timer before starting a new ramp
    _rampTimer?.cancel();
    _rampTimer = null;
    if (_rampCompleter != null && !_rampCompleter!.isCompleted) {
      _rampCompleter!.complete();
    }

    final double targetGain = calculateGain(loudnessDb);
    final double startVolume = player.volume;

    // If volume is already at the target gain, apply directly
    if ((startVolume - targetGain).abs() < 0.001) {
      try {
        await player.setVolume(targetGain);
      } catch (e) {
        debugPrint('[AudioNorm] Error setting volume: $e');
      }
      return;
    }

    const int totalSteps = 10;
    const int stepDurationMs = 30; // 10 steps * 30ms = 300ms total ramp
    int currentStep = 0;

    final completer = Completer<void>();
    _rampCompleter = completer;

    debugPrint(
      '[AudioNorm] Ramping volume from ${startVolume.toStringAsFixed(2)} '
      'to ${targetGain.toStringAsFixed(2)} over 300ms',
    );

    _rampTimer = Timer.periodic(
      const Duration(milliseconds: stepDurationMs),
      (timer) {
        currentStep++;
        final double progress = currentStep / totalSteps;
        final double stepVolume = startVolume + (targetGain - startVolume) * progress;

        try {
          unawaited(
            player.setVolume(stepVolume).catchError((Object e) {
              debugPrint('[AudioNorm] Error setting player volume during ramp: $e');
            }),
          );
        } catch (e) {
          debugPrint('[AudioNorm] Error in volume ramp step: $e');
        }

        if (currentStep >= totalSteps) {
          timer.cancel();
          _rampTimer = null;
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      },
    );

    return completer.future;
  }

  /// Cancels any active ramp timer and cleans up resources.
  void dispose() {
    _rampTimer?.cancel();
    _rampTimer = null;
    if (_rampCompleter != null && !_rampCompleter!.isCompleted) {
      _rampCompleter!.complete();
    }
  }
}
