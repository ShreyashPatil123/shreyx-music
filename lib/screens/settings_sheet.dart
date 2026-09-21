import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../services/audio_normalization_service.dart';
import '../services/crossfade_audio_engine.dart';
import '../services/equalizer_service.dart';
import '../services/stream_cache_service.dart';
import '../providers/vibe_provider.dart';
import 'vibe/vibe_home_sheet.dart';

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
                _buildSectionHeader('ShreyX Vibe (Party Mode)'),
                Consumer<VibeProvider>(
                  builder: (context, vibe, _) {
                    final config = vibe.config;
                    return Column(
                      children: [
                        SwitchListTile(
                          title: const Text(
                            'Local Development Mode',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            config.isDevMode
                                ? 'Active: ws://127.0.0.1:8080/ws'
                                : 'Active: ${config.activeWsUrl}',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          value: config.isDevMode,
                          activeThumbColor: AppTheme.neon,
                          activeTrackColor: AppTheme.neon.withValues(alpha: 0.4),
                          onChanged: (val) {
                            vibe.updateConfig(isDevMode: val);
                          },
                        ),
                        ListTile(
                          title: const Text(
                            'Custom Server URL',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            config.isDevMode
                                ? (config.customDevUrl.isNotEmpty ? config.customDevUrl : 'Default: ws://127.0.0.1:8080/ws')
                                : (config.customProdUrl.isNotEmpty ? config.customProdUrl : 'Default: wss://shreyx-vibe.onrender.com/ws'),
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.edit_outlined, color: AppTheme.neon, size: 20),
                          onTap: () => _showServerUrlDialog(context, vibe),
                        ),
                        ListTile(
                          title: const Text(
                            'Open ShreyX Vibe',
                            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            vibe.isInRoom ? 'In Room: ${vibe.room?.code}' : 'Host or join a synchronized room',
                            style: TextStyle(color: vibe.isInRoom ? AppTheme.neon : AppTheme.textSecondary, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.sensors_rounded, color: AppTheme.neon),
                          onTap: () {
                            Navigator.of(context).pop();
                            VibeHomeSheet.show(context);
                          },
                        ),
                      ],
                    );
                  },
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

  void _showServerUrlDialog(BuildContext context, VibeProvider vibe) {
    final config = vibe.config;
    final isDev = config.isDevMode;
    final currentVal = isDev ? config.customDevUrl : config.customProdUrl;
    final ctrl = TextEditingController(text: currentVal);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isDev ? 'Configure Local Server URL' : 'Configure Production Server URL',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isDev
                  ? 'Default: ws://127.0.0.1:8080/ws\n(Use adb reverse tcp:8080 tcp:8080 for USB)'
                  : 'Default: wss://shreyx-vibe.onrender.com/ws\n(Supports secure WSS on free Render host)',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: isDev ? 'ws://127.0.0.1:8080/ws' : 'wss://...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Reset Default', style: TextStyle(color: AppTheme.danger)),
            onPressed: () {
              if (isDev) {
                vibe.updateConfig(customDevUrl: '');
              } else {
                vibe.updateConfig(customProdUrl: '');
              }
              Navigator.of(ctx).pop();
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neon, foregroundColor: Colors.black),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final val = ctrl.text.trim();
              if (isDev) {
                vibe.updateConfig(customDevUrl: val);
              } else {
                vibe.updateConfig(customProdUrl: val);
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
}
