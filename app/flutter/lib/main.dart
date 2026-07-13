import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// CONFIG — API base URL
// ============================================================
// For development: use your machine's IP or Cloudflare tunnel
// For production: your stable server URL
const String API_BASE = 'https://novel-kenny-deployment-framed.trycloudflare.com';

// ============================================================
// MODELS
// ============================================================

class PropkeepHealth {
  final String status;
  final String service;
  final int qaPairs;
  final int federalFacts;
  final int states;
  final int scenarios;

  PropkeepHealth({
    required this.status,
    required this.service,
    required this.qaPairs,
    required this.federalFacts,
    required this.states,
    required this.scenarios,
  });

  factory PropkeepHealth.fromJson(Map<String, dynamic> json) {
    return PropkeepHealth(
      status: json['status'] ?? 'unknown',
      service: json['service'] ?? 'PROPKEEP',
      qaPairs: json['qa_pairs'] ?? 0,
      federalFacts: json['federal_facts'] ?? 0,
      states: json['states'] ?? 0,
      scenarios: json['scenarios'] ?? 0,
    );
  }
}

class StateCompliance {
  final String state;
  final String securityDepositLimit;
  final String depositReturnDeadlineDays;
  final String noticeToVacateDays;
  final String evictionNoticeDays;
  final String rentControl;

  StateCompliance({
    required this.state,
    required this.securityDepositLimit,
    required this.depositReturnDeadlineDays,
    required this.noticeToVacateDays,
    required this.evictionNoticeDays,
    required this.rentControl,
  });

  factory StateCompliance.fromJson(Map<String, dynamic> json) {
    return StateCompliance(
      state: json['state'] ?? '',
      securityDepositLimit: json['security_deposit_limit'] ?? 'No statutory limit',
      depositReturnDeadlineDays: json['deposit_return_deadline_days']?.toString() ?? 'Not specified',
      noticeToVacateDays: json['notice_to_vacate_days']?.toString() ?? 'Not specified',
      evictionNoticeDays: json['eviction_notice_days']?.toString() ?? 'Not specified',
      rentControl: json['rent_control'] ?? 'None',
    );
  }
}

class AskResponse {
  final String question;
  final String answer;
  final String? state;
  final bool contextUsed;
  final String? model;
  final String? error;

  AskResponse({
    required this.question,
    required this.answer,
    this.state,
    this.contextUsed = false,
    this.model,
    this.error,
  });

  factory AskResponse.fromJson(Map<String, dynamic> json) {
    return AskResponse(
      question: json['question'] ?? '',
      answer: json['answer'] ?? 'No response',
      state: json['state'],
      contextUsed: json['context_used'] ?? false,
      model: json['model'],
      error: json['error'],
    );
  }
}

class Scenario {
  final String scenario;
  final String correctAction;
  final String commonMistake;
  final String penaltyIfWrong;

  Scenario({
    required this.scenario,
    required this.correctAction,
    required this.commonMistake,
    required this.penaltyIfWrong,
  });

  factory Scenario.fromJson(Map<String, dynamic> json) {
    return Scenario(
      scenario: json['scenario'] ?? '',
      correctAction: json['correct_action'] ?? '',
      commonMistake: json['common_mistake'] ?? '',
      penaltyIfWrong: json['penalty_if_wrong'] ?? '',
    );
  }
}

// ============================================================
// API SERVICE
// ============================================================

class PropkeepApi {
  static Future<PropkeepHealth> getHealth() async {
    final res = await http.get(Uri.parse('$API_BASE/api/propkeep/health/')).timeout(Duration(seconds: 15));
    return PropkeepHealth.fromJson(json.decode(res.body));
  }

  static Future<List<String>> getStates() async {
    final res = await http.get(Uri.parse('$API_BASE/api/propkeep/states/')).timeout(Duration(seconds: 10));
    final data = json.decode(res.body);
    return List<String>.from(data['states'] ?? []);
  }

  static Future<StateCompliance> getCompliance(String state) async {
    final res = await http.get(Uri.parse('$API_BASE/api/propkeep/compliance/?state=${Uri.encodeComponent(state)}')).timeout(Duration(seconds: 10));
    return StateCompliance.fromJson(json.decode(res.body));
  }

  static Future<AskResponse> ask(String question, {String? state}) async {
    final res = await http.post(
      Uri.parse('$API_BASE/api/propkeep/ask/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'question': question, if (state != null && state.isNotEmpty) 'state': state}),
    ).timeout(Duration(seconds: 90));
    return AskResponse.fromJson(json.decode(res.body));
  }

  static Future<List<Scenario>> getScenarios() async {
    final res = await http.get(Uri.parse('$API_BASE/api/propkeep/scenarios/')).timeout(Duration(seconds: 10));
    final data = json.decode(res.body);
    return (data['scenarios'] as List?)?.map((s) => Scenario.fromJson(s)).toList() ?? [];
  }
}

// ============================================================
// THEME
// ============================================================

ThemeData _buildTheme() {
  return ThemeData(
    primarySwatch: Colors.green,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Color(0xFF0A0E27),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF0A0E27),
      elevation: 0,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: Colors.white),
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
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
      bodySmall: TextStyle(color: Colors.white54),
    ),
  );
}

// ============================================================
// MAIN APP
// ============================================================

void main() {
  runApp(PropkeepApp());
}

class PropkeepApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROPKEEP',
      theme: _buildTheme(),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================
// MAIN SCREEN — Bottom navigation: Chat, Compliance, Scenarios
// ============================================================

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  PropkeepHealth? _health;
  bool _healthLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  void _loadHealth() async {
    try {
      final h = await PropkeepApi.getHealth();
      setState(() {
        _health = h;
        _healthLoading = false;
      });
    } catch (e) {
      setState(() => _healthLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatScreen(health: _health),
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
// CHAT SCREEN — Ask questions to the PROPKEEP brain
// ============================================================

class ChatScreen extends StatefulWidget {
  final PropkeepHealth? health;
  ChatScreen({this.health});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  String? _selectedState;
  List<String> _states = [];

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
    _loadStates();
    _loadHistory();
  }

  void _loadStates() async {
    try {
      final s = await PropkeepApi.getStates();
      setState(() => _states = s);
    } catch (e) {}
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
    // Keep only last 20 messages
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

    try {
      final response = await PropkeepApi.ask(question, state: _selectedState);
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': response.answer,
          'state': response.state,
          'model': response.model,
          'rag': response.contextUsed,
          'error': response.error,
        });
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': 'Error: $e', 'error': true});
        _loading = false;
      });
    }
    _saveHistory();
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
          if (_messages.isNotEmpty)
            IconButton(icon: Icon(Icons.delete_outline), onPressed: _clearHistory),
        ],
      ),
      body: Column(
        children: [
          // Health banner
          if (widget.health != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Color(0xFF0D1B2A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('Q&A', widget.health!.qaPairs),
                  _statChip('States', widget.health!.states),
                  _statChip('Scenarios', widget.health!.scenarios),
                ],
              ),
            ),

          // State selector
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButton<String>(
              value: _selectedState,
              hint: Text('All States (auto-detect)', style: TextStyle(color: Colors.white54, fontSize: 14)),
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
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickQuestions.length,
              itemBuilder: (ctx, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ActionChip(
                  label: Text(_quickQuestions[i], style: TextStyle(fontSize: 11)),
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
                      if (i == _messages.length && _loading) {
                        return _buildLoadingBubble();
                      }
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
              border: Border(top: BorderSide(color: Colors.white12)),
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

  Widget _statChip(String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value.toString(), style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white30, fontSize: 10)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_work, size: 64, color: Colors.white12),
          SizedBox(height: 16),
          Text('Ask a property management question', style: TextStyle(color: Colors.white30, fontSize: 16)),
          SizedBox(height: 8),
          Text('50 states + federal law knowledge base', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
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
            border: isUser ? null : Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser && msg['state'] != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: Colors.lightBlueAccent),
                      SizedBox(width: 4),
                      Text(msg['state'], style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11)),
                      if (msg['rag'] == true) ...[
                        SizedBox(width: 8),
                        Icon(Icons.library_books, size: 12, color: Colors.green),
                        SizedBox(width: 2),
                        Text('RAG', style: TextStyle(color: Colors.green, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
              Text(
                msg['text'],
                style: TextStyle(
                  color: isUser ? Colors.white : (msg['error'] == true ? Colors.red : Colors.white70),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMPLIANCE SCREEN — State-by-state quick facts
// ============================================================

class ComplianceScreen extends StatefulWidget {
  @override
  _ComplianceScreenState createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<String> _states = [];
  String? _selectedState;
  StateCompliance? _compliance;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  void _loadStates() async {
    try {
      final s = await PropkeepApi.getStates();
      setState(() => _states = s);
    } catch (e) {}
  }

  void _lookup(String state) async {
    setState(() {
      _selectedState = state;
      _loading = true;
      _compliance = null;
    });
    try {
      final c = await PropkeepApi.getCompliance(state);
      setState(() { _compliance = c; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('📋 State Compliance')),
      body: Column(
        children: [
          // State grid
          Expanded(
            flex: 2,
            child: GridView.builder(
              padding: EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
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
                    child: Text(
                      s,
                      style: TextStyle(
                        color: isSelected ? Colors.green : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
          // Compliance details
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

  Widget _buildComplianceCard(StateCompliance c) {
    return Card(
      margin: EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.state, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
            SizedBox(height: 16),
            _complianceRow('Security Deposit Limit', c.securityDepositLimit),
            _complianceRow('Deposit Return Deadline', '${c.depositReturnDeadlineDays} days'),
            _complianceRow('Notice to Vacate', '${c.noticeToVacateDays} days'),
            _complianceRow('Eviction Notice', '${c.evictionNoticeDays} days'),
            _complianceRow('Rent Control', c.rentControl, highlight: c.rentControl.toLowerCase() != 'none'),
          ],
        ),
      ),
    );
  }

  Widget _complianceRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w500)),
          SizedBox(height: 4),
          Text(value, style: TextStyle(color: highlight ? Colors.amber : Colors.white, fontSize: 14)),
          Divider(color: Colors.white12),
        ],
      ),
    );
  }
}

// ============================================================
// SCENARIOS SCREEN — Real-world compliance situations
// ============================================================

class ScenariosScreen extends StatefulWidget {
  @override
  _ScenariosScreenState createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends State<ScenariosScreen> {
  List<Scenario> _scenarios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadScenarios();
  }

  void _loadScenarios() async {
    try {
      final s = await PropkeepApi.getScenarios();
      setState(() { _scenarios = s; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
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
                    title: Text(sc.scenario, style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.w600)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 16),
                                SizedBox(width: 6),
                                Text('CORRECT ACTION', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(sc.correctAction, style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(Icons.cancel, color: Colors.red, size: 16),
                                SizedBox(width: 6),
                                Text('COMMON MISTAKE', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(sc.commonMistake, style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(Icons.attach_money, color: Colors.orange, size: 16),
                                SizedBox(width: 6),
                                Text('PENALTY IF WRONG', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(sc.penaltyIfWrong, style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}