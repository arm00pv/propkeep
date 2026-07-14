import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// ON-DEVICE AI SERVICE
// ============================================================
// Uses on-device RAG (knowledge base bundled in assets) + 
// optionally on-device LLM (GGUF model) for offline mode.
//
// Architecture:
//   Online:  App → Django API → Ollama + RAG (best quality)
//   Offline: App → on-device RAG (knowledge base) + on-device LLM
//
// The knowledge base (200KB) is bundled in the app assets.
// The GGUF model (1.0GB) is downloaded on first launch or
// bundled in the APK for Pro tier users.
// ============================================================

class OnDeviceQA {
  final String question;
  final String answer;
  final String state;
  final String source;

  OnDeviceQA({required this.question, required this.answer, this.state = '', this.source = 'on_device'});
}

class KnowledgeBase {
  static List<Map<String, dynamic>> _qaPairs = [];
  static List<Map<String, dynamic>> _facts = [];
  static Map<String, Map<String, String>> _stateFacts = {};
  static List<Map<String, dynamic>> _scenarios = [];
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;

    try {
      // Load Q&A pairs
      final qaData = await rootBundle.loadString('assets/data/propkeep_qa.jsonl');
      _qaPairs = qaData.split('\n').where((l) => l.trim().isNotEmpty).map((l) => json.decode(l)).toList();

      // Load federal facts
      final factsData = await rootBundle.loadString('assets/data/propkeep_facts.jsonl');
      _facts = factsData.split('\n').where((l) => l.trim().isNotEmpty).map((l) => json.decode(l)).toList();

      // Load state facts
      final stateData = await rootBundle.loadString('assets/data/propkeep_state_facts.jsonl');
      for (var line in stateData.split('\n')) {
        if (line.trim().isEmpty) continue;
        var fact = json.decode(line);
        String state = fact['source'] ?? '';
        if (!_stateFacts.containsKey(state)) _stateFacts[state] = {};
        _stateFacts[state]![fact['relation']] = fact['target'];
      }

      // Load scenarios
      final scData = await rootBundle.loadString('assets/data/propkeep_scenarios.jsonl');
      _scenarios = scData.split('\n').where((l) => l.trim().isNotEmpty).map((l) => json.decode(l)).toList();

      _loaded = true;
    } catch (e) {
      print('Error loading knowledge base: $e');
    }
  }

  static String? detectState(String question) {
    final states = [
      'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
      'Connecticut', 'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho',
      'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana',
      'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota',
      'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
      'New Hampshire', 'New Jersey', 'New Mexico', 'New York',
      'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon',
      'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
      'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington',
      'West Virginia', 'Wisconsin', 'Wyoming', 'Washington DC', 'Puerto Rico'
    ];
    
    final abbrevs = {
      'CA': 'California', 'TX': 'Texas', 'NY': 'New York', 'FL': 'Florida',
      'WA': 'Washington', 'OR': 'Oregon', 'IL': 'Illinois', 'PA': 'Pennsylvania',
      'OH': 'Ohio', 'GA': 'Georgia', 'NC': 'North Carolina', 'MI': 'Michigan',
      'NJ': 'New Jersey', 'VA': 'Virginia', 'MA': 'Massachusetts', 'AZ': 'Arizona',
      'CO': 'Colorado', 'MD': 'Maryland', 'MN': 'Minnesota', 'MO': 'Missouri',
      'NV': 'Nevada', 'UT': 'Utah', 'TN': 'Tennessee', 'IN': 'Indiana',
      'WI': 'Wisconsin', 'CT': 'Connecticut', 'OK': 'Oklahoma', 'LA': 'Louisiana',
      'KY': 'Kentucky', 'AL': 'Alabama', 'SC': 'South Carolina', 'IA': 'Iowa',
      'KS': 'Kansas', 'AR': 'Arkansas', 'MS': 'Mississippi', 'NM': 'New Mexico',
      'NE': 'Nebraska', 'WV': 'West Virginia', 'ID': 'Idaho', 'NH': 'New Hampshire',
      'ME': 'Maine', 'MT': 'Montana', 'RI': 'Rhode Island', 'DE': 'Delaware',
      'AK': 'Alaska', 'HI': 'Hawaii', 'ND': 'North Dakota', 'SD': 'South Dakota',
      'VT': 'Vermont', 'WY': 'Wyoming', 'DC': 'Washington DC',
      'PR': 'Puerto Rico',
    };
    
    for (var state in states) {
      if (question.toLowerCase().contains(state.toLowerCase())) return state;
    }
    for (var word in question.split()) {
      if (abbrevs.containsKey(word.toUpperCase())) return abbrevs[word.toUpperCase()];
    }
    return null;
  }

  static String retrieveContext(String question, [String? state]) {
    state ??= detectState(question);
    final parts = <String>[];
    
    // State-specific facts
    if (state != null && _stateFacts.containsKey(state)) {
      parts.add('=== $state STATE LAW ===');
      _stateFacts[state]!.forEach((relation, target) {
        parts.add('- $state $relation: $target');
      });
    }
    
    // Relevant Q&A (keyword matching)
    final qLower = question.toLowerCase();
    final scored = <MapEntry<double, Map<String, dynamic>>>[];
    
    for (var qa in _qaPairs) {
      final qaText = (qa['question'] + ' ' + qa['answer']).toLowerCase();
      double score = 0;
      for (var word in qLower.split()) {
        if (word.length > 3 && qaText.contains(word)) score += 1;
      }
      if (state != null && qa['state'] == state) score += 5;
      if (score > 0) scored.add(MapEntry(score, qa));
    }
    
    scored.sort((a, b) => b.key.compareTo(a.key));
    for (var entry in scored.take(3)) {
      parts.add('\nRELEVANT Q&A:');
      parts.add('Q: ${entry.value['question']}');
      parts.add('A: ${entry.value['answer']}');
    }
    
    // Scenarios
    for (var sc in _scenarios) {
      if (qLower.split().any((w) => w.length > 4 && sc['scenario'].toLowerCase().contains(w))) {
        parts.add('\nSCENARIO: ${sc['scenario']}');
        parts.add('CORRECT: ${sc['correct_action']}');
      }
    }
    
    return parts.join('\n');
  }

  static Map<String, dynamic>? getStateCompliance(String state) {
    if (!_stateFacts.containsKey(state)) return null;
    return {
      'state': state,
      'security_deposit_limit': _stateFacts[state]!['security_deposit_limit'] ?? 'No statutory limit',
      'deposit_return_deadline_days': _stateFacts[state]!['deposit_return_deadline_days'] ?? 'Not specified',
      'notice_to_vacate_days': _stateFacts[state]!['notice_to_vacate_days'] ?? 'Not specified',
      'eviction_notice_days': _stateFacts[state]!['eviction_notice_days'] ?? 'Not specified',
      'rent_control': _stateFacts[state]!['rent_control'] ?? 'None',
    };
  }

  static List<String> getStates() {
    return _stateFacts.keys.toList()..sort();
  }

  static List<Map<String, dynamic>> getScenarios() {
    return _scenarios;
  }

  static int get qaCount => _qaPairs.length;
  static int get factCount => _facts.length;
  static int get stateCount => _stateFacts.length;
  static int get scenarioCount => _scenarios.length;
  
  static bool get isLoaded => _loaded;
}
