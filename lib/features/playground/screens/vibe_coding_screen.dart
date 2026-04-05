import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/dsa_service.dart';
import '../../settings/theme_provider.dart';

class VibeCodingScreen extends StatefulWidget {
  const VibeCodingScreen({Key? key}) : super(key: key);

  @override
  State<VibeCodingScreen> createState() => _VibeCodingScreenState();
}

class _VibeCodingScreenState extends State<VibeCodingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  final _promptCtrl  = TextEditingController();
  final _codeCtrl    = TextEditingController();
  final _stdinCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();

  String _language   = 'Python';
  String _output     = '';
  bool _isThinking   = false;
  bool _isRunning    = false;

  // Conversation history sent to Groq
  final List<Map<String, String>> _history = [];
  // UI messages (includes extracted code separately)
  final List<_ChatMsg> _messages = [];

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _messages.add(_ChatMsg(
      isUser: false,
      text: 'Hi! I\'m your AI coding assistant. Tell me what you want to build and I\'ll write the code for you.\n\nExamples:\n• "Write a binary search function"\n• "Find all prime numbers up to n"\n• "Reverse a linked list"',
      code: null,
    ));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _promptCtrl.dispose();
    _codeCtrl.dispose();
    _stdinCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Extract code block from AI markdown response ──
  String? _extractCode(String text) {
    final regex = RegExp(r'```(?:\w+)?\n([\s\S]*?)```');
    final match = regex.firstMatch(text);
    return match?.group(1)?.trim();
  }

  // ── Strip code blocks for display text ──
  String _stripCode(String text) =>
      text.replaceAll(RegExp(r'```[\s\S]*?```'), '[code above]').trim();

  Future<void> _send() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _isThinking) return;

    _promptCtrl.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _isThinking = true;
      _messages.add(_ChatMsg(isUser: true, text: prompt, code: null));
      _history.add({'role': 'user', 'content': prompt});
    });
    _scrollToBottom();

    try {
      // Only send last 10 messages to stay within token limits
      final recentHistory = _history.length > 10
          ? _history.sublist(_history.length - 10)
          : List<Map<String, String>>.from(_history);

      final reply = await DsaService.askVibeCoding(
        messages: recentHistory,
        language: _language,
      );

      _history.add({'role': 'assistant', 'content': reply});

      final code = _extractCode(reply);
      final displayText = code != null ? _stripCode(reply) : reply;

      if (code != null) {
        _codeCtrl.text = code;
      }

      setState(() {
        _isThinking = false;
        _messages.add(_ChatMsg(isUser: false, text: displayText, code: code));
      });

      // Switch to code tab if code was generated
      if (code != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _tabCtrl.animateTo(1);
        });
      }
    } catch (e) {
      setState(() {
        _isThinking = false;
        _messages.add(_ChatMsg(
          isUser: false,
          text: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
          code: null,
        ));
      });
    }
    _scrollToBottom();
  }

  Future<void> _runCode() async {
    if (_codeCtrl.text.trim().isEmpty || _isRunning) return;
    setState(() { _isRunning = true; _output = ''; });
    HapticFeedback.lightImpact();
    try {
      final result = await DsaService.executeCode(
        code: _codeCtrl.text,
        language: _language,
        stdin: _stdinCtrl.text,
      );
      setState(() {
        _output = result['error'] != null
            ? 'Error: ${result['error']}'
            : (result['stdout']?.toString().isNotEmpty == true
                ? result['stdout'].toString()
                : result['stderr']?.toString().isNotEmpty == true
                    ? 'Error: ${result['stderr']}'
                    : '(no output)');
        _isRunning = false;
      });
    } catch (e) {
      setState(() { _output = 'Error: $e'; _isRunning = false; });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear Chat?',
            style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
        content: Text('This will clear the conversation history.',
            style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _history.clear();
                _messages.clear();
                _messages.add(_ChatMsg(
                  isUser: false,
                  text: 'Chat cleared. What do you want to build?',
                  code: null,
                ));
                _output = '';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.icon(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('🤖', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vibe Code',
                style: TextStyle(color: AppColors.text(context),
                    fontWeight: FontWeight.bold, fontSize: 17)),
            Text('Powered by Groq · Llama 3.3',
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 10)),
          ]),
        ]),
        actions: [
          // Language selector
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kPurple.withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _language,
                  dropdownColor: AppColors.surface(context),
                  style: TextStyle(color: AppColors.text(context), fontSize: 12),
                  icon: const Icon(Icons.expand_more,
                      color: Color(0xFF818CF8), size: 16),
                  items: DsaService.languageConfig.keys
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _language = v);
                  },
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: AppColors.textHint(context), size: 20),
            onPressed: _clearChat,
            tooltip: 'Clear chat',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _kPurple,
          indicatorWeight: 3,
          labelColor: AppColors.text(context),
          unselectedLabelColor: AppColors.textHint(context),
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: '💬 Chat'),
            Tab(text: '💻 Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildChatTab(),
          _buildCodeTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // CHAT TAB
  // ══════════════════════════════════════════
  Widget _buildChatTab() {
    return SafeArea(
      top: false,
      child: Column(children: [
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            itemCount: _messages.length + (_isThinking ? 1 : 0),
            itemBuilder: (_, i) {
              if (_isThinking && i == _messages.length) {
                return _buildThinkingBubble();
              }
              return _buildMessageBubble(_messages[i]);
            },
          ),
        ),

        // Suggestion chips (only when chat is empty-ish)
        if (_messages.length <= 1)
          _buildSuggestions(),

        // Input bar
        _buildInputBar(),
      ]),
    );
  }

  Widget _buildMessageBubble(_ChatMsg msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (msg.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? _kPurple.withOpacity(0.25)
                          : AppColors.surface(context),
                      borderRadius: BorderRadius.circular(14).copyWith(
                        topLeft: isUser
                            ? const Radius.circular(14)
                            : const Radius.circular(4),
                        topRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(14),
                      ),
                      border: Border.all(
                        color: isUser
                            ? _kPurple.withOpacity(0.4)
                            : AppColors.border(context),
                      ),
                    ),
                    child: Text(msg.text,
                        style: TextStyle(
                            color: isUser ? Colors.white : AppColors.text(context),
                            fontSize: 13, height: 1.5)),
                  ),
                if (msg.code != null) ...[
                  const SizedBox(height: 8),
                  _buildCodePreview(msg.code!),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.person, color: Colors.white, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCodePreview(String code) {
    final lines = code.split('\n');
    final preview = lines.take(4).join('\n');
    final hasMore = lines.length > 4;

    return GestureDetector(
      onTap: () => _tabCtrl.animateTo(1),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kTeal.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.code, color: Color(0xFF00B8A3), size: 14),
            const SizedBox(width: 6),
            Text('$_language code generated',
                style: const TextStyle(
                    color: Color(0xFF00B8A3),
                    fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Text('tap to edit →',
                style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
          const SizedBox(height: 8),
          Text(
            '$preview${hasMore ? '\n...' : ''}',
            style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontFamily: 'monospace', fontSize: 11),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(14).copyWith(
                topLeft: const Radius.circular(4)),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _ThinkingDot(delay: 0),
            const SizedBox(width: 4),
            _ThinkingDot(delay: 200),
            const SizedBox(width: 4),
            _ThinkingDot(delay: 400),
            const SizedBox(width: 8),
            Text('Thinking...',
                style: TextStyle(color: AppColors.textHint(context), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      'Write a binary search',
      'Find all prime numbers up to n',
      'Reverse a string',
      'Sort an array (merge sort)',
      'Fibonacci with memoization',
      'Detect cycle in linked list',
    ];
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            _promptCtrl.text = suggestions[i];
            _send();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kPurple.withOpacity(0.25)),
            ),
            child: Text(suggestions[i],
                style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final mq = MediaQuery.of(context);
    // When keyboard is visible, viewInsets.bottom > 0 and SafeArea handles
    // the system padding, so no extra bottom padding needed.
    final bottomPad = mq.viewInsets.bottom > 0 ? 0.0 : mq.padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.background(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kPurple.withOpacity(0.3)),
              ),
              child: TextField(
                controller: _promptCtrl,
                style: TextStyle(color: AppColors.text(context), fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Describe what you want to build...',
                  hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isThinking ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: _isThinking
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)]),
                color: _isThinking ? AppColors.surfaceVariant(context) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _isThinking
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: AppColors.textHint(context), strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  // CODE TAB
  // ══════════════════════════════════════════
  Widget _buildCodeTab() {
    return Column(children: [
      // Code editor
      Expanded(
        flex: 6,
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0D1117),
              child: TextField(
                controller: _codeCtrl,
                maxLines: null,
                expands: true,
                readOnly: false,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.6),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintText: 'AI-generated code will appear here.\nYou can also type or edit directly.',
                  hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.15),
                      fontFamily: 'monospace',
                      fontSize: 12),
                ),
              ),
            ),
          ),
          // Copy button
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _codeCtrl.text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Code copied!'),
                  backgroundColor: Color(0xFF131929),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy_rounded, color: Colors.white38, size: 13),
                  SizedBox(width: 4),
                  Text('Copy', style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ]),
      ),

      // Stdin + Run
      Container(
        color: AppColors.surface(context),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(children: [
          // Custom input
          Row(children: [
            Icon(Icons.input, color: AppColors.textHint(context), size: 14),
            const SizedBox(width: 6),
            Text('Input (stdin)',
                style: TextStyle(color: AppColors.textHint(context), fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: TextField(
              controller: _stdinCtrl,
              style: TextStyle(color: AppColors.textSecondary(context),
                  fontFamily: 'monospace', fontSize: 12),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Enter test input here (optional)',
                hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 12),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton(
              onPressed: _isRunning ? null : _runCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isRunning
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Running...',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700)),
                      ])
                  : const Text('▶  Run Code',
                      style: TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),

      // Output panel
      if (_output.isNotEmpty)
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 160),
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF0A0F1A),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(
                _output.startsWith('Error')
                    ? Icons.error_outline : Icons.check_circle_outline,
                color: _output.startsWith('Error')
                    ? Colors.red : _kTeal,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _output.startsWith('Error') ? 'Error' : 'Output',
                style: TextStyle(
                  color: _output.startsWith('Error') ? Colors.red : _kTeal,
                  fontSize: 11, fontWeight: FontWeight.w700,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Text(_output,
                    style: TextStyle(
                      color: _output.startsWith('Error')
                          ? Colors.red[300] : Colors.white70,
                      fontFamily: 'monospace', fontSize: 12, height: 1.5,
                    )),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ── Chat message model ──────────────────────────────
class _ChatMsg {
  final bool isUser;
  final String text;
  final String? code;
  _ChatMsg({required this.isUser, required this.text, required this.code});
}

// ── Animated thinking dot ───────────────────────────
class _ThinkingDot extends StatefulWidget {
  final int delay;
  const _ThinkingDot({required this.delay});
  @override
  State<_ThinkingDot> createState() => _ThinkingDotState();
}

class _ThinkingDotState extends State<_ThinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF818CF8),
            shape: BoxShape.circle,
          ),
        ),
      );
}
