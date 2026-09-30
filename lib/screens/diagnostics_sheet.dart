import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/playback_diagnostics_service.dart';
import '../theme/app_theme.dart';

class DiagnosticsSheet extends StatefulWidget {
  const DiagnosticsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DiagnosticsSheet(),
    );
  }

  @override
  State<DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<DiagnosticsSheet> {
  final PlaybackDiagnosticsService _diagnostics = PlaybackDiagnosticsService();

  @override
  Widget build(BuildContext context) {
    final sessions = _diagnostics.recentSessions;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppTheme.borderHairline)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header Handle & Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.neon.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.analytics_outlined, color: AppTheme.neon, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Playback Diagnostics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppTheme.cyan, size: 20),
                        tooltip: 'Export JSON',
                        onPressed: () {
                          final json = _diagnostics.exportJson();
                          Clipboard.setData(ClipboardData(text: json));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Diagnostics JSON copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                        tooltip: 'Clear',
                        onPressed: () {
                          setState(() {
                            _diagnostics.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.borderHairline, height: 1),

            if (sessions.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No playback sessions recorded yet.\nPlay a track to view latency benchmarks.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final tapToAudio = s.tapToFirstAudioMs;
                    final isFast = tapToAudio != null && tapToAudio < 1200;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderHairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title & Timestamp
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (tapToAudio != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isFast ? AppTheme.neon : Colors.amber).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${tapToAudio}ms',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isFast ? AppTheme.neon : Colors.amber,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.artist,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),

                          // Milestone Breakdown Chips
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildMetricChip('Resolver', s.resolverUsed ?? 'unknown', AppTheme.cyan),
                              if (s.codec != null)
                                _buildMetricChip('Codec', '${s.codec} (${s.container})', Colors.white70),
                              if (s.bitrate != null && s.bitrate! > 0)
                                _buildMetricChip('Bitrate', '${s.bitrate! ~/ 1000}k', Colors.white70),
                              if (s.wasCached)
                                _buildMetricChip('Cache', 'HIT', AppTheme.neon),
                              if (s.tapToResolutionMs != null)
                                _buildMetricChip('Resolution', '${s.tapToResolutionMs}ms', Colors.white70),
                              if (s.resolutionToPlayerReadyMs != null)
                                _buildMetricChip('Player Prepare', '${s.resolutionToPlayerReadyMs}ms', Colors.white70),
                              if (s.nativeExtractionMs != null)
                                _buildMetricChip('Native Ext', '${s.nativeExtractionMs}ms', Colors.white70),
                              if (s.dartExtractionMs != null)
                                _buildMetricChip('Dart Ext', '${s.dartExtractionMs}ms', Colors.white70),
                              if (s.errorReason != null)
                                _buildMetricChip('Error', s.errorReason!, AppTheme.danger),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
