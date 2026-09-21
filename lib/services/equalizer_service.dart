import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents an audio equalizer preset configuration.
class EqPreset {
  final String name;
  final double bassGain;
  final double midGain;
  final double trebleGain;
  final IconData icon;

  const EqPreset({
    required this.name,
    required this.bassGain,
    required this.midGain,
    required this.trebleGain,
    required this.icon,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqPreset &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() =>
      'EqPreset(name: $name, bassGain: $bassGain, midGain: $midGain, trebleGain: $trebleGain)';
}

/// Service managing audio equalizer presets with persistence and real-time DSP
/// application to just_audio's AndroidEqualizer hardware effect.
class EqualizerService {
  static final EqualizerService _instance = EqualizerService._internal();

  factory EqualizerService() => _instance;

  EqualizerService._internal();

  static const String _prefKey = 'shrex_eq_preset';
  static const String _defaultPresetName = 'Flat';

  AndroidEqualizer? _activeEqualizer;

  /// Predefined list of equalizer presets with prominent acoustic profiles.
  static const List<EqPreset> presets = [
    EqPreset(
      name: 'Flat',
      bassGain: 0.0,
      midGain: 0.0,
      trebleGain: 0.0,
      icon: Icons.equalizer,
    ),
    EqPreset(
      name: 'Bass Boost',
      bassGain: 0.85,
      midGain: 0.1,
      trebleGain: -0.15,
      icon: Icons.speaker,
    ),
    EqPreset(
      name: 'Treble Boost',
      bassGain: -0.15,
      midGain: 0.15,
      trebleGain: 0.85,
      icon: Icons.music_note,
    ),
    EqPreset(
      name: 'Vocal',
      bassGain: -0.25,
      midGain: 0.85,
      trebleGain: 0.3,
      icon: Icons.mic,
    ),
    EqPreset(
      name: 'Electronic',
      bassGain: 0.75,
      midGain: -0.2,
      trebleGain: 0.65,
      icon: Icons.electric_bolt,
    ),
    EqPreset(
      name: 'Rock',
      bassGain: 0.65,
      midGain: 0.3,
      trebleGain: 0.5,
      icon: Icons.album,
    ),
    EqPreset(
      name: 'Acoustic',
      bassGain: 0.25,
      midGain: 0.65,
      trebleGain: 0.35,
      icon: Icons.piano,
    ),
    EqPreset(
      name: 'Soft',
      bassGain: -0.35,
      midGain: 0.1,
      trebleGain: -0.3,
      icon: Icons.nights_stay,
    ),
  ];

  EqPreset _activePreset = presets.first;

  /// Returns the currently active equalizer preset.
  EqPreset get activePreset => _activePreset;

  /// Returns all available equalizer presets.
  List<EqPreset> get availablePresets => presets;

  /// Attaches the active audio player's AndroidEqualizer effect so preset
  /// changes immediately control the hardware DSP.
  void attachEqualizer(AndroidEqualizer equalizer) {
    _activeEqualizer = equalizer;
    applyCurrentPreset();
  }

  /// Initializes the service and loads the saved preset from persistent storage.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPresetName = prefs.getString(_prefKey) ?? _defaultPresetName;
      _activePreset = _findPreset(savedPresetName);
      debugPrint('[Equalizer] Loaded preset: ${_activePreset.name}');
    } catch (e, stack) {
      debugPrint('[Equalizer] Error loading preset during init: $e\n$stack');
      _activePreset = presets.first;
    }
  }

  /// Sets and persists the equalizer preset matching [name], and immediately
  /// updates the DSP bands on the active player.
  Future<void> setPreset(String name) async {
    try {
      final preset = _findPreset(name);
      _activePreset = preset;
      debugPrint('[Equalizer] Setting active preset to: ${preset.name}');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, preset.name);
      
      await applyCurrentPreset();
    } catch (e, stack) {
      debugPrint('[Equalizer] Error saving preset: $e\n$stack');
    }
  }

  /// Applies the active preset to the attached AndroidEqualizer.
  Future<void> applyCurrentPreset() async {
    final eq = _activeEqualizer;
    if (eq == null) {
      debugPrint('[Equalizer] No active AndroidEqualizer attached yet');
      return;
    }

    try {
      await eq.setEnabled(true);
      final params = await eq.parameters;
      final bands = params.bands;
      if (bands.isEmpty) return;

      final double minDb = params.minDecibels;
      final double maxDb = params.maxDecibels;

      debugPrint('[Equalizer] Applying "${_activePreset.name}" across ${bands.length} bands (range: $minDb to $maxDb dB)');

      for (int i = 0; i < bands.length; i++) {
        double gainFactor = 0.0;
        if (i == 0) {
          // Sub-bass (~60 Hz)
          gainFactor = _activePreset.bassGain;
        } else if (i == 1) {
          // Mid-bass (~230 Hz)
          gainFactor = _activePreset.bassGain * 0.65 + _activePreset.midGain * 0.35;
        } else if (i == 2) {
          // Mid-range / Vocals (~910 Hz)
          gainFactor = _activePreset.midGain;
        } else if (i == 3) {
          // High-mids (~3.6 kHz)
          gainFactor = _activePreset.midGain * 0.3 + _activePreset.trebleGain * 0.7;
        } else {
          // Highs / Treble (~14 kHz)
          gainFactor = _activePreset.trebleGain;
        }

        final double targetDb = gainFactor >= 0
            ? gainFactor * maxDb
            : gainFactor.abs() * minDb;

        await bands[i].setGain(targetDb);
        debugPrint('[Equalizer] Band $i (${bands[i].centerFrequency.round()} Hz): ${targetDb.toStringAsFixed(1)} dB');
      }
    } catch (e) {
      debugPrint('[Equalizer] Error applying preset to hardware: $e');
    }
  }

  /// Helper to locate a preset by name (case-insensitive) or fallback to 'Flat'.
  static EqPreset _findPreset(String name) {
    final trimmedName = name.trim().toLowerCase();
    return presets.firstWhere(
      (preset) => preset.name.toLowerCase() == trimmedName,
      orElse: () => presets.first,
    );
  }

  void dispose() {
    _activeEqualizer = null;
    debugPrint('[Equalizer] EqualizerService disposed.');
  }
}
