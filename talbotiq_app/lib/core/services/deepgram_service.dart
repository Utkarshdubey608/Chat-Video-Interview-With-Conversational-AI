// lib/core/services/deepgram_service.dart
import 'package:http/http.dart' as http;
import '../../models/app_models.dart';

class DeepgramService {
  String _apiKey = '';

  void setKey(String key) {
    _apiKey = key;
  }

  String getKey() => _apiKey;

  static final Set<String> fillerWords = {
    'um', 'uh', 'hmm', 'er', 'erm', 'ah', 'like', 'basically', 'literally',
    'actually', 'right', 'okay', 'so', 'you know', 'i mean', 'kind of', 'sort of',
  };

  int countFillers(String text) {
    if (text.isEmpty) return 0;
    final words = text.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), '').split(RegExp(r'\s+'));
    int count = 0;
    
    // Count exact matches of individual filler words
    for (var w in words) {
      if (fillerWords.contains(w)) count++;
    }
    
    // Also scan for double-word phrases like 'you know', 'i mean', 'kind of', 'sort of'
    final lowerText = text.toLowerCase();
    final phrases = ['you know', 'i mean', 'kind of', 'sort of'];
    for (var phrase in phrases) {
      int index = 0;
      while (true) {
        index = lowerText.indexOf(phrase, index);
        if (index == -1) break;
        count++; // Increment count for phrase match
        index += phrase.length;
      }
    }

    return count;
  }

  int countWords(List<TranscriptEntry> entries) {
    return entries
        .where((e) => e.role == 'candidate')
        .fold(0, (acc, e) => acc + e.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
  }

  int calcWpm(List<TranscriptEntry> entries) {
    final candidate = entries.where((e) => e.role == 'candidate').toList();
    if (candidate.length < 2) return 0;
    final durationMs = candidate.last.timestamp - candidate.first.timestamp;
    if (durationMs <= 0) return 0;
    final words = countWords(entries);
    return ((words / durationMs) * 60000).round();
  }

  Future<Map<String, dynamic>> testConnection() async {
    if (_apiKey.isEmpty) {
      return {'ok': false, 'message': 'No API key set'};
    }
    try {
      // Direct call to Deepgram projects list to verify API Key
      final response = await http.get(
        Uri.parse('https://api.deepgram.com/v1/projects'),
        headers: {
          'Authorization': 'Token $_apiKey',
        },
      );
      if (response.statusCode == 200) {
        return {'ok': true, 'message': 'Deepgram Nova-3 connected'};
      } else if (response.statusCode == 401) {
        return {'ok': false, 'message': 'Invalid API key (401)'};
      } else {
        return {'ok': false, 'message': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }
}

final deepgramService = DeepgramService();
