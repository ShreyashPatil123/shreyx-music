import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/stem.dart';
import 'failed_track_registry.dart';

enum TrackPlaybackState {
  queued,
  preparing,
  ready,
  playing,
  completed,
  retrying,
  failed,
  unsupported,
  skipped,
}

class QueueTrackItem {
  final Stem stem;
  TrackPlaybackState state;
  String? errorMessage;
  int retryAttempts;

  QueueTrackItem({
    required this.stem,
    this.state = TrackPlaybackState.queued,
    this.errorMessage,
    this.retryAttempts = 0,
  });

  QueueTrackItem copyWith({
    Stem? stem,
    TrackPlaybackState? state,
    String? errorMessage,
    int? retryAttempts,
  }) =>
      QueueTrackItem(
        stem: stem ?? this.stem,
        state: state ?? this.state,
        errorMessage: errorMessage ?? this.errorMessage,
        retryAttempts: retryAttempts ?? this.retryAttempts,
      );
}

/// Authoritative queue manager maintaining queue state, shuffle, repeat,
/// and non-blocking failure recovery.
class PlaybackQueueController {
  final List<QueueTrackItem> _queue = [];
  final List<Stem> _originalOrder = [];
  int _currentIndex = -1;
  bool _isShuffled = false;
  LoopMode _loopMode = LoopMode.off;

  final FailedTrackRegistry _failedRegistry = FailedTrackRegistry();

  final _queueSubject = BehaviorSubject<List<QueueTrackItem>>.seeded([]);
  final _currentTrackSubject = BehaviorSubject<QueueTrackItem?>();
  final _currentIndexSubject = BehaviorSubject<int>.seeded(-1);

  Stream<List<QueueTrackItem>> get queueStream => _queueSubject.stream;
  Stream<QueueTrackItem?> get currentTrackStream => _currentTrackSubject.stream;
  Stream<int> get currentIndexStream => _currentIndexSubject.stream;

  List<QueueTrackItem> get queue => List.unmodifiable(_queue);
  List<Stem> get stems => _queue.map((item) => item.stem).toList();
  int get currentIndex => _currentIndex;
  bool get isShuffled => _isShuffled;
  LoopMode get loopMode => _loopMode;
  QueueTrackItem? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;

  void setLoopMode(LoopMode mode) {
    _loopMode = mode;
  }

  /// Sets the queue from a list of stems, preserving original order for un-shuffle.
  void setQueue(List<Stem> newStems, {Stem? initialStem, int initialIndex = 0}) {
    if (newStems.isEmpty) {
      clear();
      return;
    }

    _originalOrder.clear();
    _originalOrder.addAll(newStems);

    _queue.clear();
    for (final stem in newStems) {
      _queue.add(QueueTrackItem(stem: stem));
    }

    if (initialStem != null) {
      final idx = _queue.indexWhere((item) => item.stem.id == initialStem.id);
      _currentIndex = idx != -1 ? idx : 0;
    } else {
      _currentIndex = (initialIndex >= 0 && initialIndex < _queue.length) ? initialIndex : 0;
    }

    _notify();
  }

  void addToQueue(Stem stem) {
    _originalOrder.add(stem);
    _queue.add(QueueTrackItem(stem: stem));
    _notify();
  }

  void playNext(Stem stem) {
    final item = QueueTrackItem(stem: stem);
    _originalOrder.add(stem);
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, item);
    } else {
      _queue.add(item);
      _currentIndex = 0;
    }
    _notify();
  }

  void appendUniqueTracks(List<Stem> newTracks) {
    final existingIds = _queue.map((item) => item.stem.id).toSet();
    final toAdd = newTracks.where((s) => !existingIds.contains(s.id)).toList();
    if (toAdd.isEmpty) return;

    for (final stem in toAdd) {
      _originalOrder.add(stem);
      _queue.add(QueueTrackItem(stem: stem));
    }
    _notify();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removed = _queue.removeAt(index);
    _originalOrder.removeWhere((s) => s.id == removed.stem.id);

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
    }
    _notify();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0 || newIndex > _queue.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    _notify();
  }

  void setShuffled(bool enable) {
    if (_isShuffled == enable) return;
    _isShuffled = enable;

    if (enable) {
      if (_queue.length <= 1) return;
      final currentItem = currentTrack;
      final rest = _queue.where((item) => item != currentItem).toList()..shuffle();
      _queue.clear();
      if (currentItem != null) {
        _queue.add(currentItem);
        _queue.addAll(rest);
        _currentIndex = 0;
      } else {
        _queue.addAll(rest);
        _currentIndex = 0;
      }
    } else {
      // Restore original order
      final currentItem = currentTrack;
      _queue.clear();
      for (final stem in _originalOrder) {
        _queue.add(QueueTrackItem(stem: stem));
      }
      if (currentItem != null) {
        final idx = _queue.indexWhere((item) => item.stem.id == currentItem.stem.id);
        _currentIndex = idx != -1 ? idx : 0;
      } else {
        _currentIndex = 0;
      }
    }
    _notify();
  }

  /// Updates the state of the active track (e.g. preparing, playing, completed).
  void updateActiveTrackState(TrackPlaybackState state, {String? error}) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      final item = _queue[_currentIndex];
      item.state = state;
      item.errorMessage = error;
      _notify();
    }
  }

  /// Calculates the next index without modifying the state.
  int getNextIndex() {
    if (_queue.isEmpty) return -1;
    if (_currentIndex + 1 < _queue.length) {
      return _currentIndex + 1;
    } else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      return 0;
    }
    return -1;
  }

  /// Advances index to next playable track. Returns the next [QueueTrackItem] or null.
  QueueTrackItem? advanceToNext() {
    final nextIdx = getNextIndex();
    if (nextIdx != -1) {
      _currentIndex = nextIdx;
      _notify();
      return _queue[_currentIndex];
    }
    return null;
  }

  /// Retreats index to previous track.
  QueueTrackItem? retreatToPrevious() {
    if (_queue.isEmpty) return null;
    if (_currentIndex - 1 >= 0) {
      _currentIndex--;
      _notify();
      return _queue[_currentIndex];
    } else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = _queue.length - 1;
      _notify();
      return _queue[_currentIndex];
    }
    return null;
  }

  /// Handles failure for the currently active track in a non-blocking way (Safeguard 3 & Point 13).
  ///
  /// Marks current track as failed and automatically advances to the next track,
  /// preserving the rest of the queue, current indices, and shuffle state.
  QueueTrackItem? handleCurrentTrackFailure(String reason) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;

    final failedItem = _queue[_currentIndex];
    failedItem.state = TrackPlaybackState.failed;
    failedItem.errorMessage = reason;
    _failedRegistry.recordFailure(failedItem.stem.sourceId, reason);

    debugPrint('[PlaybackQueueController] ⏭️ Skipping failed track "${failedItem.stem.title}": $reason');

    // Auto-advance to next track in queue
    return advanceToNext();
  }

  void clear() {
    _queue.clear();
    _originalOrder.clear();
    _currentIndex = -1;
    _notify();
  }

  void _notify() {
    _queueSubject.add(List.unmodifiable(_queue));
    _currentIndexSubject.add(_currentIndex);
    _currentTrackSubject.add(currentTrack);
  }

  void dispose() {
    _queueSubject.close();
    _currentTrackSubject.close();
    _currentIndexSubject.close();
  }
}
