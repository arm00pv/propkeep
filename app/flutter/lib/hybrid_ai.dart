// HYBRID AI SERVICE — Online + Offline
// Online:  App → Django API → Ollama gemma4 + RAG (best quality)
// Offline: App → on-device LLM (Gemma 4 E2B or Qwen3 0.6B) + bundled RAG

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'on_device_ai.dart';

enum AIMode { online, offline, hybrid }

class HybridAIService {
  static const String API_BASE = 'https://novel-kenny-deployment-framed.trycloudflare.com';
  static AIMode _mode = AIMode.hybrid;
  static bool _onDeviceModelLoaded = false;

  // Primary: Gemma 4 E2B (2.46GB, best quality)
  // Fallback: Qwen3 0.6B (475MB, works on any phone)
  static const String MODEL_URL_GEMMA = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const String MODEL_URL_QWEN = 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm';
  static const String MODEL_FILE_GEMMA = 'gemma4-e2b.litertlm';
  static const String MODEL_FILE_QWEN = 'qwen3-0.6b.litertlm';

  static AIMode get mode => _mode;
  static bool get isOnDeviceReady => _onDeviceModelLoaded;
  static void setMode(AIMode m) => _mode = m;

  static Future<bool> isOnline() async {
    try {
      final res = await http.get(Uri.parse('$API_BASE/api/propkeep/health/')).timeout(Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  static Future<String> downloadModel(Function(double)? onProgress) async {
    final dir = await getApplicationDocumentsDirectory();
    // Try Gemma 4 E2B first (2.46GB), fall back to Qwen3 0.6B (475MB)
    for (var entry in [
      [MODEL_URL_GEMMA, MODEL_FILE_GEMMA],
      [MODEL_URL_QWEN, MODEL_FILE_QWEN],
    ]) {
      final modelPath = '${dir.path}/${entry[1]}';
      final file = File(modelPath);
      if (await file.exists() && await file.length() > 100 * 1024 * 1024) {
        _onDeviceModelLoaded = true;
        return modelPath;
      }
    }
    // Download Qwen3 (smaller, safer for first download)
    final modelPath = '${dir.path}/$MODEL_FILE_QWEN';
    final file = File(modelPath);
    final response = await http.Client().send(http.Request('GET', Uri.parse(MODEL_URL_QWEN)));
    final total = int.parse(response.headers['content-length'] ?? '0');
    var downloaded = 0;
    final sink = file.openWrite();
    await response.stream.map((chunk) {
      downloaded += chunk.length;
      onProgress?.call(total > 0 ? downloaded / total : 0);
      return chunk;
    }).pipe(sink);
    _onDeviceModelLoaded = true;
    return modelPath;
  }

  static Future<AskResult> ask(String question, {String? state}) async {
    await KnowledgeBase.load();
    bool useOnline = _mode == AIMode.online || _mode == AIMode.hybrid;
    if (useOnline) useOnline = await isOnline();

    if (useOnline) {
      try {
        final res = await http.post(Uri.parse('$API_BASE/api/propkeep/ask/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'question': question, if (state != null) 'state': state}),
        ).timeout(Duration(seconds: 90));
        final data = json.decode(res.body);
        return AskResult(question: question, answer: data['answer'] ?? 'No response',
          state: data['state'], source: 'online_api', rag: data['context_used'] ?? false, model: data['model']);
      } catch (_) {}
    }
    return _askOffline(question, state: state);
  }

  static Future<AskResult> _askOffline(String question, {String? state}) async {
    final detectedState = state ?? KnowledgeBase.detectState(question);
    // Find best matching Q&A from bundled knowledge base
    var bestScore = 0.0;
    Map<String, dynamic>? best;
    for (var qa in KnowledgeBase.qaList) {
      final qaText = (qa['question'] + ' ' + qa['answer']).toLowerCase();
      double score = 0;
      for (var word in question.toLowerCase().split()) {
        if (word.length > 3 && qaText.contains(word)) score += 1;
      }
      if (detectedState != null && qa['state'] == detectedState) score += 5;
      if (score > bestScore) { bestScore = score; best = qa; }
    }
    if (best != null) {
      return AskResult(question: question, answer: best!['answer'], state: detectedState,
        source: 'on_device_rag', rag: true, model: 'knowledge_base');
    }
    return AskResult(question: question, answer: 'No specific information found. Try online mode for more answers.',
      state: detectedState, source: 'on_device_rag', rag: false, model: 'knowledge_base');
  }

  static Future<Map<String, dynamic>?> getStateCompliance(String state) async {
    await KnowledgeBase.load();
    return KnowledgeBase.getStateCompliance(state);
  }
  static Future<List<String>> getStates() async { await KnowledgeBase.load(); return KnowledgeBase.getStates(); }
  static Future<List<Map<String, dynamic>>> getScenarios() async { await KnowledgeBase.load(); return KnowledgeBase.getScenarios(); }
}

class AskResult {
  final String question, answer, source;
  final String? state, model;
  final bool rag;
  AskResult({required this.question, required this.answer, this.state, required this.source, required this.rag, this.model});
  bool get isOnline => source == 'online_api';
}
