import 'package:flutter/material.dart';
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

/// Service managing audio equalizer presets with persistence via SharedPreferences.
class EqualizerService {
  static final EqualizerService _instance = EqualizerService._internal();

  factory EqualizerService() => _instance;

  EqualizerService._internal();

  static const String _prefKey = 'shrex_eq_preset';
  static const String _defaultPresetName = 'Flat';

  /// Predefined list of equalizer presets.
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
      bassGain: 0.8,
      midGain: 0.1,
      trebleGain: 0.0,
      icon: Icons.speaker,
    ),
    EqPreset(
      name: 'Treble Boost',
      bassGain: 0.0,
      midGain: 0.1,
      trebleGain: 0.8,
      icon: Icons.music_note,
    ),
    EqPreset(
      name: 'Vocal',
      bassGain: -0.2,
      midGain: 0.7,
      trebleGain: 0.3,
      icon: Icons.mic,
    ),
    EqPreset(
      name: 'Electronic',
      bassGain: 0.6,
      midGain: -0.2,
      trebleGain: 0.5,
      icon: Icons.electric_bolt,
    ),
    EqPreset(
      name: 'Rock',
      bassGain: 0.5,
      midGain: 0.3,
      trebleGain: 0.4,
      icon: Icons.album,
    ),
    EqPreset(
      name: 'Acoustic',
      bassGain: 0.2,
      midGain: 0.5,
      trebleGain: 0.2,
      icon: Icons.piano,
    ),
    EqPreset(
      name: 'Soft',
      bassGain: -0.3,
      midGain: 0.0,
      trebleGain: -0.2,
      icon: Icons.nights_stay,
    ),
  ];

  EqPreset _activePreset = presets.first;

  /// Returns the currently active equalizer preset.
  EqPreset get activePreset => _activePreset;

  /// Returns all available equalizer presets.
  List<EqPreset> get availablePresets => presets;

  /// Initializes the service and loads the saved preset from persistent storage.
  Future<void> init() async {
    try {
      debugPrint('[Equalizer] Initializing EqualizerService...');
      final prefs = await SharedPreferences.getInstance();
      final savedPresetName = prefs.getString(_prefKey) ?? _defaultPresetName;
      _activePreset = _findPreset(savedPresetName);
      debugPrint('[Equalizer] Loaded preset: ${_activePreset.name}');
    } catch (e, stack) {
      debugPrint('[Equalizer] Error loading preset during init: $e\n$stack');
      _activePreset = presets.first;
    }
  }

  /// Sets and persists the equalizer preset matching [name].
  Future<void> setPreset(String name) async {
    try {
      final preset = _findPreset(name);
      _activePreset = preset;
      debugPrint('[Equalizer] Setting active preset to: ${preset.name}');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, preset.name);
      debugPrint('[Equalizer] Preset successfully saved: ${preset.name}');
    } catch (e, stack) {
      debugPrint('[Equalizer] Error saving preset: $e\n$stack');
    }
  }

  /// Performs no-op cleanup when the service is disposed.
  void dispose() {
    debugPrint('[Equalizer] EqualizerService disposed.');
  }

  /// Helper to locate a preset by name (case-insensitive) or fallback to 'Flat'.
  static EqPreset _findPreset(String name) {
    final trimmedName = name.trim().toLowerCase();
    return presets.firstWhere(
      (preset) => preset.name.toLowerCase() == trimmedName,
      orElse: () => presets.first,
    );
  }
}
