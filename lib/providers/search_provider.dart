import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';

class SearchProvider extends ChangeNotifier {
  final YoutubeExplode _yt = YoutubeExplode();

  String _query = '';
  List<String> _suggestions = [];
  List<Stem> _searchResults = [];
  bool _isLoading = false;
  String? _error;

  String get query => _query;
  List<String> get suggestions => _suggestions;
  List<Stem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> updateSuggestions(String text) async {
    _query = text;
    if (text.trim().isEmpty) {
      _suggestions = [];
      notifyListeners();
      return;
    }

    try {
      final uri = Uri.parse('https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=${Uri.encodeComponent(text)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = res.body;
        final start = body.indexOf('(');
        final end = body.lastIndexOf(')');
        if (start != -1 && end != -1) {
          final jsonStr = body.substring(start + 1, end);
          final data = jsonDecode(jsonStr) as List<dynamic>;
          if (data.length > 1) {
            final rawList = data[1] as List<dynamic>;
            _suggestions = rawList.map((item) => item[0] as String).take(6).toList();
            notifyListeners();
          }
        }
      }
    } catch (_) {
      _suggestions = [];
    }
  }

  Future<void> executeSearch(String queryText) async {
    final cleanQuery = queryText.trim();
    if (cleanQuery.isEmpty) return;

    _isLoading = true;
    _error = null;
    _suggestions = [];
    notifyListeners();

    final List<Stem> stems = [];
    int attempts = 0;
    while (attempts < 2 && stems.isEmpty) {
      attempts++;
      try {
        final searchList = await _yt.search.search(cleanQuery).timeout(const Duration(seconds: 10));
        for (final video in searchList.take(25)) {
          final durationSec = video.duration?.inSeconds ?? 0;
          final artUrl = video.thumbnails.highResUrl.isNotEmpty
              ? video.thumbnails.highResUrl
              : video.thumbnails.standardResUrl;

          stems.add(Stem(
            id: 'yt_${video.id.value}',
            title: video.title,
            artistName: video.author,
            artworkUrl: artUrl,
            durationSec: durationSec,
            sourceId: video.id.value,
          ));
        }
      } catch (e) {
        if (attempts >= 2) {
          _error = 'Search failed. Please check internet connection.';
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    if (stems.isNotEmpty) {
      _searchResults = stems;
      _error = null;
    }
    _isLoading = false;
    notifyListeners();
  }

  void clearSearch() {
    _query = '';
    _suggestions = [];
    _searchResults = [];
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}
