import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SongScrubberBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool enabled;

  const SongScrubberBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.enabled = true,
  });

  @override
  State<SongScrubberBar> createState() => _SongScrubberBarState();
}

class _SongScrubberBarState extends State<SongScrubberBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds < 10 ? '0' : ''}$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final totalDurationMs = widget.duration.inMilliseconds.toDouble();
    final maxVal = totalDurationMs > 0 ? totalDurationMs : 1.0;

    final currentPositionMs = widget.position.inMilliseconds.toDouble().clamp(0.0, maxVal);
    final sliderValue = (_isDragging ? _dragValue : currentPositionMs).clamp(0.0, maxVal);

    final displayPos = _isDragging
        ? Duration(milliseconds: _dragValue.toInt())
        : widget.position;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // High-precision slider for seeking forward & backward
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            activeTrackColor: AppTheme.neon,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            thumbColor: widget.enabled ? Colors.white : Colors.transparent,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: widget.enabled ? (_isDragging ? 9.0 : 7.0) : 0.0,
              elevation: widget.enabled ? 4.0 : 0.0,
            ),
            overlayColor: AppTheme.neon.withValues(alpha: 0.25),
            overlayShape: widget.enabled ? const RoundSliderOverlayShape(overlayRadius: 18.0) : SliderComponentShape.noOverlay,
          ),
          child: Slider(
            min: 0.0,
            max: maxVal,
            value: sliderValue,
            onChangeStart: widget.enabled
                ? (val) {
                    setState(() {
                      _isDragging = true;
                      _dragValue = val;
                    });
                  }
                : null,
            onChanged: widget.enabled
                ? (val) {
                    setState(() {
                      _dragValue = val;
                    });
                  }
                : null,
            onChangeEnd: widget.enabled
                ? (val) {
                    setState(() {
                      _isDragging = false;
                    });
                    widget.onSeek(Duration(milliseconds: val.toInt()));
                  }
                : null,
          ),
        ),

        // Time labels: Current timestamp (left) & Total duration (right)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPos),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: _isDragging ? FontWeight.bold : FontWeight.w500,
                  color: _isDragging ? AppTheme.neon : AppTheme.textSecondary,
                ),
              ),
              Text(
                _formatDuration(widget.duration),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
