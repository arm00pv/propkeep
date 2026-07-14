// on_device_llm.dart — Real on-device LLM inference using flutter_litert_lm
import 'dart:io';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'on_device_ai.dart';

class OnDeviceLLM {
  static LiteLmEngine? _engine;
  static LiteLmConversation? _conversation;
  static bool _loaded = false;
  static String _modelName = 'None';

  static bool get isLoaded => _loaded;
  static String get modelName => _modelName;

  /// Find model file — checks multiple locations
  static Future<String?> findModel() async {
    final locations = <String>[];
    
    // 1. App private storage (where downloaded models go)
    try {
      final dir = await getApplicationDocumentsDirectory();
      locations.add('${dir.path}/gemma4-e2b.litertlm');
      locations.add('${dir.path}/qwen3-0.6b.litertlm');
    } catch (_) {}
    
    // 2. App external storage (app-specific, always readable)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        locations.add('${extDir.path}/gemma4-e2b.litertlm');
        locations.add('${extDir.path}/qwen3-0.6b.litertlm');
        locations.add('${extDir.path}/Download/gemma4-e2b.litertlm');
        locations.add('${extDir.path}/Download/qwen3-0.6b.litertlm');
      }
    } catch (_) {}
    
    // 3. Public Download folders (may need storage permission)
    locations.add('/sdcard/Download/gemma4-e2b.litertlm');
    locations.add('/sdcard/Download/qwen3-0.6b.litertlm');
    locations.add('/storage/emulated/0/Download/gemma4-e2b.litertlm');
    locations.add('/storage/emulated/0/Download/qwen3-0.6b.litertlm');
    
    // 4. /data/local/tmp (where adb push goes)
    locations.add('/data/local/tmp/gemma4-e2b.litertlm');
    locations.add('/data/local/tmp/qwen3-0.6b.litertlm');
    
    for (var path in locations) {
      try {
        final file = File(path);
        if (await file.exists() && await file.length() > 50 * 1024 * 1024) {
          return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Load the on-device model
  static Future<bool> loadModel() async {
    if (_loaded) return true;
    
    final path = await findModel();
    if (path == null) return false;
    
    try {
      _modelName = path.contains('gemma') ? 'Gemma 4 E2B' : 'Qwen3 0.6B';
      
      _engine = await LiteLmEngine.create(
        LiteLmEngineConfig(
          modelPath: path,
          backend: LiteLmBackend.cpu,
        ),
      );
      
      _conversation = await _engine!.createConversation(
        LiteLmConversationConfig(
          systemInstruction: 'You are a property management compliance expert. '
              'Answer questions about landlord-tenant law, security deposits, '
              'evictions, fair housing, and rental compliance. Be specific, '
              'cite relevant laws, and include practical advice. '
              'If the answer depends on the state, mention that.',
          samplerConfig: const LiteLmSamplerConfig(
            temperature: 0.3,
            topK: 40,
            topP: 0.95,
          ),
        ),
      );
      
      _loaded = true;
      return true;
    } catch (e) {
      _loaded = false;
      _modelName = 'Load error';
      return false;
    }
  }

  /// Generate a response using the on-device LLM with RAG context
  static Future<String> generate(String question, {String? state}) async {
    if (!_loaded || _conversation == null) {
      return _knowledgeBaseFallback(question, state);
    }
    
    try {
      await KnowledgeBase.load();
      final detectedState = state ?? KnowledgeBase.detectState(question);
      final context = KnowledgeBase.retrieveContext(question, detectedState);
      
      final prompt = '''
LEGAL CONTEXT (from knowledge base):
$context

QUESTION: $question

Answer the question using the legal context above. Be specific and practical.''';
      
      final reply = await _conversation!.sendMessage(prompt);
      return reply.text;
    } catch (e) {
      return _knowledgeBaseFallback(question, state);
    }
  }

  /// Knowledge base fallback (no LLM)
  static String _knowledgeBaseFallback(String question, String? state) {
    final detectedState = state ?? KnowledgeBase.detectState(question);
    var bestScore = 0.0;
    Map<String, dynamic>? best;
    for (var qa in KnowledgeBase.qaList) {
      final qaText = (qa['question'] + ' ' + qa['answer']).toLowerCase();
      double score = 0;
      for (var word in question.toLowerCase().split(' ')) {
        if (word.length > 3 && qaText.contains(word)) score += 1;
      }
      if (detectedState != null && qa['state'] == detectedState) score += 5;
      if (score > bestScore) { bestScore = score; best = qa; }
    }
    if (best != null && bestScore > 0) {
      if (detectedState != null) return '📍 $detectedState\n\n' + best!['answer'];
      return best!['answer'];
    }
    return 'No specific information found. Try online mode for more answers.';
  }

  static Future<void> dispose() async {
    await _conversation?.dispose();
    await _engine?.dispose();
    _engine = null;
    _conversation = null;
    _loaded = false;
    _modelName = 'None';
  }
}
