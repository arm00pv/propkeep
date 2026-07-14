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
// RESPONSIVE HELPERS
// ============================================================
class Screen {
  static double width(BuildContext ctx) => MediaQuery.of(ctx).size.width;
  static double height(BuildContext ctx) => MediaQuery.of(ctx).size.height;
  static bool isSmallPhone(BuildContext ctx) => width(ctx) < 380;
  static bool isTablet(BuildContext ctx) => width(ctx) > 600;
  static double scaleFont(BuildContext ctx, double base) {
    final w = width(ctx);
    if (w < 380) return base * 0.85;
    if (w > 600) return base * 1.15;
    return base;
  }
  static double maxBubbleWidth(BuildContext ctx) {
    final w = width(ctx);
    if (w > 600) return w * 0.7;
    return w * 0.85;
  }
  static int stateGridColumns(BuildContext ctx) {
    final w = width(ctx);
    if (w < 380) return 2;
    if (w < 600) return 3;
    return 4;
  }
}

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
        children: [ChatScreen(), ComplianceScreen(), ScenariosScreen()],
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
// CHAT SCREEN
// ============================================================
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
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
    final modelPath = await OnDeviceLLM.findModel();
    setState(() {
      _modelAvailable = modelPath != null;
      _modelName = OnDeviceLLM.modelName;
    });
    _loadHistory();
  }

  Future<List<String>> _getStates() async {
    try {
      final res = await http.get(Uri.parse('$API_BASE/api/propkeep/states/')).timeout(Duration(seconds: 5));
      if (res.statusCode == 200) return List<String>.from(json.decode(res.body)['states'] ?? []);
    } catch (_) {}
    return KnowledgeBase.getStates();
  }

  void _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('propkeep_chat_history');
    if (saved != null) setState(() => _messages = List<Map<String, dynamic>>.from(json.decode(saved)));
  }

  void _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = _messages.length > 20 ? _messages.sublist(_messages.length - 20) : _messages;
    prefs.setString('propkeep_chat_history', json.encode(toSave));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: Duration(milliseconds: 300), curve: Curves.easeOut);
    });
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
    _scrollToBottom();

    String answer = '';
    String source = '';
    bool rag = false;
    String? detectedState;

    final effectiveState = _selectedState ?? KnowledgeBase.detectState(question);
    detectedState = effectiveState;

    if (_mode == AIMode.online || _mode == AIMode.hybrid) {
      try {
        final res = await http.post(Uri.parse('$API_BASE/api/propkeep/ask/'),
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
      } catch (_) { source = 'offline'; }
    }

    if (answer.isEmpty) {
      source = 'offline';
      if (_llmLoaded) {
        try {
          answer = await OnDeviceLLM.generate(question, state: effectiveState);
          rag = true;
        } catch (_) { answer = _knowledgeBaseFallback(question, effectiveState); }
      } else if (_modelAvailable && !_llmLoaded) {
        final loaded = await OnDeviceLLM.loadModel();
        if (loaded) {
          setState(() { _llmLoaded = true; _modelName = OnDeviceLLM.modelName; });
          answer = await OnDeviceLLM.generate(question, state: effectiveState);
          rag = true;
        } else { answer = _knowledgeBaseFallback(question, effectiveState); }
      } else { answer = _knowledgeBaseFallback(question, effectiveState); }
    }

    setState(() {
      _messages.add({'role': 'assistant', 'text': answer, 'state': detectedState, 'source': source, 'rag': rag, 'model': _llmLoaded ? _modelName : 'knowledge_base'});
      _loading = false;
    });
    _saveHistory();
    _scrollToBottom();
  }

  String _knowledgeBaseFallback(String question, String? state) {
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

  void _clearHistory() { setState(() => _messages.clear()); _saveHistory(); }

  @override
  Widget build(BuildContext context) {
    final fontScale = Screen.scaleFont(context, 1.0);
    return Scaffold(
      appBar: AppBar(
        title: Text('🏠 PROPKEEP'),
        actions: [
          PopupMenuButton<AIMode>(
            icon: Icon(_mode == AIMode.online ? Icons.cloud : (_mode == AIMode.offline ? Icons.phone_android : Icons.swap_horiz)),
            onSelected: (m) => setState(() => _mode = m),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: AIMode.hybrid, child: Text('🔀 Hybrid (auto-switch)')),
              PopupMenuItem(value: AIMode.online, child: Text('☁️ Online (server AI)')),
              PopupMenuItem(value: AIMode.offline, child: Text('📱 Offline (on-device AI)')),
            ],
          ),
          if (_messages.isNotEmpty) IconButton(icon: Icon(Icons.delete_outline), onPressed: _clearHistory),
        ],
      ),
      body: Column(
        children: [
          // Status bar — compact, no truncation
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Color(0xFF0D1B2A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_mode == AIMode.online ? Icons.cloud : (_mode == AIMode.offline ? Icons.phone_android : Icons.swap_horiz), size: 12, color: _mode == AIMode.online ? Colors.blue : Colors.green),
                      SizedBox(width: 4),
                      Flexible(child: Text(_mode == AIMode.online ? 'Online' : (_mode == AIMode.offline ? 'Offline' : 'Hybrid'), style: TextStyle(color: Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _llmLoaded
                      ? [Icon(Icons.memory, size: 12, color: Colors.green), SizedBox(width: 3), Flexible(child: Text(_modelName, style: TextStyle(color: Colors.green, fontSize: 10), overflow: TextOverflow.ellipsis))]
                      : _modelAvailable
                        ? [Text('Model ready', style: TextStyle(color: Colors.amber, fontSize: 10))]
                        : [Text('Online only', style: TextStyle(color: Colors.white30, fontSize: 10))],
                  ),
                ),
              ],
            ),
          ),
          // State selector
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: DropdownButton<String>(
              value: _selectedState,
              hint: Text('All States (auto-detect)', style: TextStyle(color: Colors.white54, fontSize: Screen.scaleFont(context, 13))),
              isExpanded: true,
              dropdownColor: Color(0xFF151B2E),
              items: [DropdownMenuItem(value: null, child: Text('All States (auto-detect)')), ..._states.map((s) => DropdownMenuItem(value: s, child: Text(s)))],
              onChanged: (v) => setState(() => _selectedState = v),
            ),
          ),
          // Quick questions
          Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickQuestions.length,
              itemBuilder: (ctx, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: ActionChip(
                  label: Text(_quickQuestions[i], style: TextStyle(fontSize: Screen.scaleFont(context, 10)), overflow: TextOverflow.ellipsis, maxLines: 1),
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
                  controller: _scrollController,
                  padding: EdgeInsets.all(12),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _messages.length && _loading) return _buildLoadingBubble();
                    return _buildMessageBubble(_messages[i]);
                  },
                ),
          ),
          // Input
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(color: Color(0xFF151B2E), border: Border(top: BorderSide(color: Colors.white10))),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Ask about deposits, evictions, leases...',
                        hintStyle: TextStyle(fontSize: Screen.scaleFont(context, 13)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _ask(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  SizedBox(width: 8),
                  CircleAvatar(backgroundColor: Colors.green, child: IconButton(icon: Icon(Icons.send, color: Colors.white, size: 20), onPressed: _ask)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.home_work, size: 64, color: Colors.white10),
        SizedBox(height: 16),
        Text('Ask a property management question', style: TextStyle(color: Colors.white30, fontSize: Screen.scaleFont(context, 16))),
        SizedBox(height: 8),
        Text('52 states + PR · Federal law · On-device AI', style: TextStyle(color: Colors.white20, fontSize: Screen.scaleFont(context, 11))),
      ],
    ));
  }

  Widget _buildLoadingBubble() {
    return Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      SpinKitThreeBounce(color: Colors.green, size: 20),
      SizedBox(width: 12),
      Text('Thinking...', style: TextStyle(color: Colors.white30, fontSize: 14)),
    ]));
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
          constraints: BoxConstraints(maxWidth: Screen.maxBubbleWidth(context)),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser ? Colors.green.withOpacity(0.15) : Color(0xFF151B2E),
            borderRadius: BorderRadius.circular(12),
            border: isUser ? null : Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser)
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (msg['state'] != null) _badge(Icons.location_on, msg['state'], Colors.lightBlueAccent),
                      if (msg['rag'] == true) _badge(Icons.library_books, 'RAG', Colors.green),
                      _badge(isOnline ? Icons.cloud : Icons.phone_android, isOnline ? 'Online' : 'Offline', isOnline ? Colors.blue : Colors.green),
                    ],
                  ),
                ),
              Text(msg['text'], style: TextStyle(color: isUser ? Colors.white : Colors.white70, fontSize: Screen.scaleFont(context, 14), height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 11, color: color), SizedBox(width: 3), Text(label, style: TextStyle(color: color, fontSize: 10))],
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
  void initState() { super.initState(); _loadStates(); }

  void _loadStates() async {
    await KnowledgeBase.load();
    setState(() => _states = KnowledgeBase.getStates());
  }

  void _lookup(String state) async {
    setState(() { _selectedState = state; _loading = true; _compliance = null; });
    try {
      final res = await http.get(Uri.parse('$API_BASE/api/propkeep/compliance/?state=${Uri.encodeComponent(state)}')).timeout(Duration(seconds: 5));
      if (res.statusCode == 200) { setState(() { _compliance = json.decode(res.body); _loading = false; }); return; }
    } catch (_) {}
    final c = KnowledgeBase.getStateCompliance(state);
    setState(() { _compliance = c; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cols = Screen.stateGridColumns(context);
    return Scaffold(
      appBar: AppBar(title: Text('📋 State Compliance')),
      body: Column(children: [
        Expanded(
          flex: 2,
          child: GridView.builder(
            padding: EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: 2.5, crossAxisSpacing: 6, mainAxisSpacing: 6),
            itemCount: _states.length,
            itemBuilder: (ctx, i) {
              final s = _states[i];
              final isSelected = s == _selectedState;
              return GestureDetector(
                onTap: () => _lookup(s),
                child: Container(
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green.withOpacity(0.2) : Color(0xFF151B2E),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected ? Border.all(color: Colors.green) : Border.all(color: Colors.white12),
                  ),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(s, style: TextStyle(color: isSelected ? Colors.green : Colors.white70, fontSize: Screen.scaleFont(context, 11), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
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
      ]),
    );
  }

  Widget _buildComplianceCard(Map<String, dynamic> c) {
    return Card(
      margin: EdgeInsets.all(8),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['state'] ?? '', style: TextStyle(fontSize: Screen.scaleFont(context, 22), fontWeight: FontWeight.bold, color: Colors.green)),
          SizedBox(height: 12),
          _row('Security Deposit', c['security_deposit_limit'] ?? 'No statutory limit'),
          _row('Deposit Return', '${c['deposit_return_deadline_days'] ?? '?'} days'),
          _row('Notice to Vacate', '${c['notice_to_vacate_days'] ?? '?'} days'),
          _row('Eviction Notice', '${c['eviction_notice_days'] ?? '?'} days'),
          _row('Rent Control', c['rent_control'] ?? 'None', highlight: (c['rent_control'] ?? 'none').toLowerCase() != 'none'),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white30, fontSize: Screen.scaleFont(context, 10), fontWeight: FontWeight.w500)),
      SizedBox(height: 3),
      Text(value, style: TextStyle(color: highlight ? Colors.amber : Colors.white, fontSize: Screen.scaleFont(context, 14))),
      Divider(color: Colors.white10, height: 8),
    ]));
  }
}

// ============================================================
// SCENARIOS SCREEN — Split into General + State-Specific tabs
// ============================================================
class ScenariosScreen extends StatefulWidget {
  @override
  _ScenariosScreenState createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  List<Map<String, dynamic>> _scenarios = [];
  bool _loading = true;
  int _tabIndex = 0; // 0=general, 1=state-specific

  @override
  void initState() { super.initState(); _loadScenarios(); }

  void _loadScenarios() async {
    await KnowledgeBase.load();
    setState(() { _scenarios = KnowledgeBase.getScenarios(); _loading = false; });
  }

  List<Map<String, dynamic>> get _generalScenarios => _scenarios.where((s) => s['category'] == 'general').toList();
  List<Map<String, dynamic>> get _stateScenarios => _scenarios.where((s) => s['category'] == 'state_specific').toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: Text('⚠️ Scenarios')), body: Center(child: SpinKitCircle(color: Colors.green)));
    
    final general = _generalScenarios;
    final stateSpecific = _stateScenarios;
    final current = _tabIndex == 0 ? general : stateSpecific;
    
    return Scaffold(
      appBar: AppBar(title: Text('⚠️ Compliance Scenarios')),
      body: Column(children: [
        // Tab bar for General / State-Specific
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _tabButton('General (${general.length})', 0),
              SizedBox(width: 8),
              _tabButton('State-Specific (${stateSpecific.length})', 1),
            ],
          ),
        ),
        // Scenarios list
        Expanded(
          child: current.isEmpty
            ? Center(child: Text('No scenarios in this category yet', style: TextStyle(color: Colors.white30)))
            : ListView.builder(
                padding: EdgeInsets.all(10),
                itemCount: current.length,
                itemBuilder: (ctx, i) {
                  final sc = current[i];
                  return Card(
                    margin: EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      title: Text(
                        sc['scenario'] ?? '',
                        style: TextStyle(color: Colors.amber, fontSize: Screen.scaleFont(context, 13), fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: _tabIndex == 1 && sc['state'] != 'all'
                        ? Padding(padding: EdgeInsets.only(top: 4), child: Text(sc['state'] ?? '', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11)))
                        : null,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(14),
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
        ),
      ]),
    );
  }

  Widget _tabButton(String label, int index) {
    final isActive = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.green.withOpacity(0.2) : Color(0xFF151B2E),
          borderRadius: BorderRadius.circular(20),
          border: isActive ? Border.all(color: Colors.green) : Border.all(color: Colors.white10),
        ),
        child: Text(label, style: TextStyle(color: isActive ? Colors.green : Colors.white54, fontSize: Screen.scaleFont(context, 11), fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _scRow(IconData icon, String label, String text, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: color, size: 16), SizedBox(width: 6), Expanded(child: Text(label, style: TextStyle(color: color, fontSize: Screen.scaleFont(context, 11), fontWeight: FontWeight.bold)))]),
      SizedBox(height: 6),
      Text(text, style: TextStyle(color: Colors.white70, fontSize: Screen.scaleFont(context, 13), height: 1.4)),
      SizedBox(height: 14),
    ]);
  }
}