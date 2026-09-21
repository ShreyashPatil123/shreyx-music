import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/audio_normalization_service.dart';
import '../services/crossfade_audio_engine.dart';
import '../services/equalizer_service.dart';
import '../services/stream_cache_service.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  // Audio Engine State
  late bool _normalizationEnabled;
  late int _crossfadeSeconds;
  late String _currentEqPreset;

  final List<int> _crossfadeOptions = [0, 3, 5, 8, 12];

  // Cache State
  late int _cacheBytes;
  late int _cacheCount;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  void _loadState() {
    _normalizationEnabled = AudioNormalizationService().isEnabled;
    _crossfadeSeconds = CrossfadeAudioEngine().crossfadeSeconds;
    _currentEqPreset = EqualizerService().activePreset.name;

    _cacheBytes = StreamCacheService().totalCacheBytes;
    _cacheCount = StreamCacheService().entryCount;
  }

  void _cycleCrossfade() {
    int currentIndex = _crossfadeOptions.indexOf(_crossfadeSeconds);
    if (currentIndex == -1 || currentIndex == _crossfadeOptions.length - 1) {
      _crossfadeSeconds = _crossfadeOptions.first;
    } else {
      _crossfadeSeconds = _crossfadeOptions[currentIndex + 1];
    }
    CrossfadeAudioEngine().setCrossfadeSeconds(_crossfadeSeconds);
    setState(() {});
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    final mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(2)} MB";
  }

  Future<void> _clearCache() async {
    await StreamCacheService().clearCache();
    setState(() {
      _cacheBytes = StreamCacheService().totalCacheBytes;
      _cacheCount = StreamCacheService().entryCount;
    });
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 20, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _buildSectionHeader('Audio Engine'),
                SwitchListTile(
                  title: const Text(
                    'Volume Normalization',
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Balance volume across all tracks',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  activeThumbColor: AppTheme.neon,
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) 
                        ? Colors.transparent 
                        : AppTheme.borderHairline,
                  ),
                  value: _normalizationEnabled,
                  onChanged: (val) {
                    setState(() {
                      _normalizationEnabled = val;
                    });
                    AudioNormalizationService().setEnabled(val);
                  },
                ),
                ListTile(
                  title: const Text(
                    'Crossfade Duration',
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Seamless transition between tracks',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderHairline),
                    ),
                    child: Text(
                      _crossfadeSeconds == 0 ? 'Off' : '${_crossfadeSeconds}s',
                      style: const TextStyle(
                        color: AppTheme.neon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  onTap: _cycleCrossfade,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: const Text(
                    'Equalizer Preset',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: EqualizerService().availablePresets.map((preset) {
                      final isActive = preset.name == _currentEqPreset;
                      return InkWell(
                        onTap: () {
                          EqualizerService().setPreset(preset.name);
                          setState(() {
                            _currentEqPreset = preset.name;
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive 
                                ? AppTheme.neon.withValues(alpha: 0.1) 
                                : AppTheme.bgElevated,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive ? AppTheme.neon : AppTheme.borderHairline,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(preset.icon, size: 16, color: isActive ? AppTheme.neon : AppTheme.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                preset.name,
                                style: TextStyle(
                                  color: isActive ? AppTheme.neon : AppTheme.textSecondary,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),
                _buildSectionHeader('Cache'),
                ListTile(
                  title: const Text(
                    'Cached Data',
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    '$_cacheCount tracks • ${_formatBytes(_cacheBytes)}',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  trailing: TextButton(
                    onPressed: _clearCache,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                    ),
                    child: const Text('Clear Cache'),
                  ),
                ),

                const SizedBox(height: 16),
                _buildSectionHeader('About'),
                const ListTile(
                  title: Text(
                    'ShreyX Music',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(
                        'Version 2.0.0',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Local-first • Privacy-first • High-fidelity',
                        style: TextStyle(
                          color: AppTheme.cyan,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
