import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'on_device_ai.dart';
import 'on_device_llm.dart';

// ============================================================
// CONFIG
// ============================================================
const String API_BASE = 'https://novel-kenny-deployment-framed.trycloudflare.com';

// ============================================================
// MAIN
// ============================================================
void main() {
  runApp(PropkeepApp());
}

class PropkeepApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROPKEEP',
      theme: ThemeData(
        primarySwatch: Colors.green,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF0A0E27),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF0A0E27),
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        cardTheme: CardThemeData(
          color: Color(0xFF151B2E),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1A1F3A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
          hintStyle: TextStyle(color: Colors.white30),
        ),
      ),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================
// AI MODE
// ============================================================
enum AIMode { online, offline, hybrid }

// ============================================================
// MAIN SCREEN
// ============================================================
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatScreen(),
          ComplianceScreen(),
          ScenariosScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: Color(0xFF151B2E),
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.white30,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Ask'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'States'),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Scenarios'),
        ],
      ),
    );
  }
}

// ============================================================
// CHAT SCREEN — Uses hybrid online/offline AI
// ============================================================
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  String? _selectedState;
  List<String> _states = [];
  AIMode _mode = AIMode.hybrid;
  bool _llmLoaded = false;
  bool _modelAvailable = false;
  String _modelName = 'None';

  final _quickQuestions = [
    "How much can I charge for a security deposit?",
    "Can I refuse to rent to someone with children?",
    "Do I have to allow emotional support animals?",
    "What are the lead paint disclosure requirements?",
    "Can I change the locks if a tenant hasn't paid rent?",
    "How long do I have to return a security deposit?",
    "What is the implied warranty of habitability?",
    "Can I enter the rental unit without notice?",
  ];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  void _initApp() async {
    await KnowledgeBase.load();
    final s = await _getStates();
    setState(() => _states = s);
    
    // Check if on-device model is available
    final modelPath = await OnDeviceLLM.findModel();
    setState(() {
      _modelAvailable = modelPath != null;
      _modelName = OnDeviceLLM.modelName;
    });
    
    _loadHistory();
  }

  Future<List<String>> _getStates() async {
    // Try online first
    try {
      final res = await http.get(Uri.parse('$API_BASE/api/propkeep/states/')).timeout(Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return List<String>.from(data['states'] ?? []);
      }
    } catch (_) {}
    // Fallback to on-device knowledge base
    return KnowledgeBase.getStates();
  }

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('propkeep_chat_history');
    if (saved != null) {
      setState(() => _messages = List<Map<String, dynamic>>.from(json.decode(saved)));
    }
  }

  void _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = _messages.length > 20 ? _messages.sublist(_messages.length - 20) : _messages;
    prefs.setString('propkeep_chat_history', json.encode(toSave));
  }

  void _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _messages.add({'role': 'user', 'text': question, 'state': _selectedState});
      _loading = true;
    });
    _controller.clear();
    _saveHistory();

    String answer = '';
    String source = '';
    bool rag = false;
    String? detectedState;

    // Auto-detect state from question if not manually selected
    final effectiveState = _selectedState ?? KnowledgeBase.detectState(question);
    detectedState = effectiveState;
    
    // Try online first (if hybrid or online mode)
    if (_mode == AIMode.online || _mode == AIMode.hybrid) {
      try {
        final res = await http.post(
          Uri.parse('$API_BASE/api/propkeep/ask/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'question': question, if (effectiveState != null) 'state': effectiveState}),
        ).timeout(Duration(seconds: 90));
        
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          answer = data['answer'] ?? '';
          source = 'online';
          rag = data['context_used'] ?? false;
          detectedState = data['state'];
        }
      } catch (_) {
        source = 'offline'; // Will try offline
      }
    }

    // If online failed or offline mode, use on-device
    if (answer.isEmpty) {
      source = 'offline';
      
      // Try on-device LLM if loaded
      if (_llmLoaded) {
        try {
          answer = await OnDeviceLLM.generate(question, state: effectiveState);
          rag = true;
        } catch (_) {
          answer = _knowledgeBaseFallback(question);
        }
      } else {
        // Try to load the model on first use
        if (_modelAvailable && !_llmLoaded) {
          final loaded = await OnDeviceLLM.loadModel();
          if (loaded) {
            setState(() {
              _llmLoaded = true;
              _modelName = OnDeviceLLM.modelName;
            });
            answer = await OnDeviceLLM.generate(question, state: effectiveState);
            rag = true;
          } else {
            answer = _knowledgeBaseFallback(question);
          }
        } else {
          answer = _knowledgeBaseFallback(question);
        }
      }
      
      // State already detected above
    }

    setState(() {
      _messages.add({
        'role': 'assistant',
        'text': answer,
        'state': detectedState,
        'source': source,
        'rag': rag,
        'model': _llmLoaded ? _modelName : 'knowledge_base',
      });
      _loading = false;
    });
    _saveHistory();
  }

  String _knowledgeBaseFallback(String question) {
    // Auto-detect state from question
    final detectedState = _selectedState ?? KnowledgeBase.detectState(question);
    
    // Simple keyword matching from bundled knowledge base
    var bestScore = 0.0;
    Map<String, dynamic>? best;
    for (var qa in KnowledgeBase.qaList) {
      final qaText = (qa['question'] + ' ' + qa['answer']).toLowerCase();
      double score = 0;
      for (var word in question.toLowerCase().split(' ')) {
        if (word.length > 3 && qaText.contains(word)) score += 1;
      }
      // Boost state-specific matches
      if (detectedState != null && qa['state'] == detectedState) score += 5;
      if (score > bestScore) { bestScore = score; best = qa; }
    }
    if (best != null && bestScore > 0) {
      // Prepend state info if detected
      if (detectedState != null) {
        return '📍 $detectedState\n\n' + best!['answer'];
      }
      return best!['answer'];
    }
    return 'No specific information found. Try online mode for more answers.';
  }

  void _clearHistory() {
    setState(() => _messages.clear());
    _saveHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🏠 PROPKEEP'),
        actions: [
          // Mode indicator
          PopupMenuButton<AIMode>(
            icon: Icon(_mode == AIMode.online ? Icons.cloud : (_mode == AIMode.offline ? Icons.phone_android : Icons.swap_horiz)),
            onSelected: (m) => setState(() => _mode = m),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: AIMode.hybrid, child: Text('🔀 Hybrid (auto-switch)')),
              PopupMenuItem(value: AIMode.online, child: Text('☁️ Online (server AI)')),
              PopupMenuItem(value: AIMode.offline, child: Text('📱 Offline (on-device AI)')),
            ],
          ),
          if (_messages.isNotEmpty)
            IconButton(icon: Icon(Icons.delete_outline), onPressed: _clearHistory),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Color(0xFF0D1B2A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _mode == AIMode.online ? Icons.cloud : (_mode == AIMode.offline ? Icons.phone_android : Icons.swap_horiz),
                      size: 14, color: _mode == AIMode.online ? Colors.blue : Colors.green,
                    ),
                    SizedBox(width: 6),
                    Text(
                      _mode == AIMode.online ? 'Online' : (_mode == AIMode.offline ? 'Offline' : 'Hybrid'),
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                if (_llmLoaded)
                  Row(
                    children: [
                      Icon(Icons.memory, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(_modelName, style: TextStyle(color: Colors.green, fontSize: 11)),
                    ],
                  )
                else if (_modelAvailable)
                  Text('Model ready', style: TextStyle(color: Colors.amber, fontSize: 10))
                else
                  Text('Online only', style: TextStyle(color: Colors.white30, fontSize: 10)),
              ],
            ),
          ),

          // State selector
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButton<String>(
              value: _selectedState,
              hint: Text('All States (auto-detect from question)', style: TextStyle(color: Colors.white54, fontSize: 13)),
              isExpanded: true,
              dropdownColor: Color(0xFF151B2E),
              items: [
                DropdownMenuItem(value: null, child: Text('All States (auto-detect)')),
                ..._states.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _selectedState = v),
            ),
          ),

          // Quick questions
          Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickQuestions.length,
              itemBuilder: (ctx, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ActionChip(
                  label: Text(
                    _quickQuestions[i],
                    style: TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  backgroundColor: Color(0xFF1E293B),
                  labelStyle: TextStyle(color: Colors.lightBlueAccent),
                  onPressed: () => _controller.text = _quickQuestions[i],
                ),
              ),
            ),
          ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length && _loading) return _buildLoadingBubble();
                      final msg = _messages[i];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),

          // Input
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFF151B2E),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Ask about security deposits, evictions, leases...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _ask(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _ask,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_work, size: 64, color: Colors.white10),
          SizedBox(height: 16),
          Text('Ask a property management question', style: TextStyle(color: Colors.white30, fontSize: 16)),
          SizedBox(height: 8),
          Text('50 states + PR · Federal law · On-device AI', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SpinKitThreeBounce(color: Colors.green, size: 20),
          SizedBox(width: 12),
          Text('Thinking...', style: TextStyle(color: Colors.white30, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final source = msg['source'] as String? ?? '';
    final isOnline = source == 'online';
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser ? Colors.green.withOpacity(0.15) : Color(0xFF151B2E),
            borderRadius: BorderRadius.circular(12),
            border: isUser ? null : Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser)
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (msg['state'] != null) ...[
                        Icon(Icons.location_on, size: 12, color: Colors.lightBlueAccent),
                        SizedBox(width: 4),
                        Text(msg['state'], style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11)),
                      ],
                      if (msg['rag'] == true) ...[
                        SizedBox(width: 8),
                        Icon(Icons.library_books, size: 12, color: Colors.green),
                        SizedBox(width: 2),
                        Text('RAG', style: TextStyle(color: Colors.green, fontSize: 10)),
                      ],
                      Spacer(),
                      Icon(
                        isOnline ? Icons.cloud : Icons.phone_android,
                        size: 12,
                        color: isOnline ? Colors.blue : Colors.green,
                      ),
                      SizedBox(width: 4),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(color: isOnline ? Colors.blue : Colors.green, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              Text(
                msg['text'],
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
                overflow: TextOverflow.visible,
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMPLIANCE SCREEN
// ============================================================
class ComplianceScreen extends StatefulWidget {
  @override
  _ComplianceScreenState createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<String> _states = [];
  String? _selectedState;
  Map<String, dynamic>? _compliance;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  void _loadStates() async {
    await KnowledgeBase.load();
    setState(() => _states = KnowledgeBase.getStates());
  }

  void _lookup(String state) async {
    setState(() { _selectedState = state; _loading = true; _compliance = null; });
    
    // Try online first
    try {
      final res = await http.get(Uri.parse('$API_BASE/api/propkeep/compliance/?state=${Uri.encodeComponent(state)}')).timeout(Duration(seconds: 5));
      if (res.statusCode == 200) {
        setState(() { _compliance = json.decode(res.body); _loading = false; });
        return;
      }
    } catch (_) {}
    
    // Fallback to on-device
    final c = KnowledgeBase.getStateCompliance(state);
    setState(() { _compliance = c; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('📋 State Compliance')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: GridView.builder(
              padding: EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: _states.length,
              itemBuilder: (ctx, i) {
                final s = _states[i];
                final isSelected = s == _selectedState;
                return GestureDetector(
                  onTap: () => _lookup(s),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green.withOpacity(0.2) : Color(0xFF151B2E),
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected ? Border.all(color: Colors.green) : Border.all(color: Colors.white12),
                    ),
                    child: Text(s, style: TextStyle(color: isSelected ? Colors.green : Colors.white70, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
                  ),
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: _loading
                ? Center(child: SpinKitCircle(color: Colors.green))
                : _compliance == null
                    ? Center(child: Text('Select a state above', style: TextStyle(color: Colors.white30)))
                    : _buildComplianceCard(_compliance!),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceCard(Map<String, dynamic> c) {
    return Card(
      margin: EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['state'] ?? '', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
          SizedBox(height: 16),
          _row('Security Deposit Limit', c['security_deposit_limit'] ?? 'No statutory limit'),
          _row('Deposit Return Deadline', '${c['deposit_return_deadline_days'] ?? '?'} days'),
          _row('Notice to Vacate', '${c['notice_to_vacate_days'] ?? '?'} days'),
          _row('Eviction Notice', '${c['eviction_notice_days'] ?? '?'} days'),
          _row('Rent Control', c['rent_control'] ?? 'None', highlight: (c['rent_control'] ?? 'none').toLowerCase() != 'none'),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w500)),
        SizedBox(height: 4),
        Text(value, style: TextStyle(color: highlight ? Colors.amber : Colors.white, fontSize: 14)),
        Divider(color: Colors.white10),
      ]),
    );
  }
}

// ============================================================
// SCENARIOS SCREEN
// ============================================================
class ScenariosScreen extends StatefulWidget {
  @override
  _ScenariosScreenState createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  List<Map<String, dynamic>> _scenarios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadScenarios();
  }

  void _loadScenarios() async {
    await KnowledgeBase.load();
    setState(() { _scenarios = KnowledgeBase.getScenarios(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('⚠️ Compliance Scenarios')),
      body: _loading
          ? Center(child: SpinKitCircle(color: Colors.green))
          : ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: _scenarios.length,
              itemBuilder: (ctx, i) {
                final sc = _scenarios[i];
                return Card(
                  margin: EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text(sc['scenario'] ?? '', style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.w600)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _scRow(Icons.check_circle, 'CORRECT ACTION', sc['correct_action'] ?? '', Colors.green),
                          _scRow(Icons.cancel, 'COMMON MISTAKE', sc['common_mistake'] ?? '', Colors.red),
                          _scRow(Icons.attach_money, 'PENALTY IF WRONG', sc['penalty_if_wrong'] ?? '', Colors.orange),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _scRow(IconData icon, String label, String text, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: color, size: 16), SizedBox(width: 6), Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))]),
      SizedBox(height: 8),
      Text(text, style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
      SizedBox(height: 16),
    ]);
  }
}