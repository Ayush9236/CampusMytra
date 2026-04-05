import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/fitness_models.dart';
import 'services/fitness_ai_service.dart';
import 'widgets/buddy_character.dart';
import 'fitness_buddy_screen.dart' show buddyColor;
import 'fitness_theme.dart';

class BuddyChatScreen extends StatefulWidget {
  final FitnessProfile profile;
  final FitnessPlan? plan;
  final BuddyState? buddy;

  const BuddyChatScreen({
    super.key,
    required this.profile,
    this.plan,
    this.buddy,
  });

  @override
  State<BuddyChatScreen> createState() => _BuddyChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  _ChatMessage({required this.text, required this.isUser}) : time = DateTime.now();
}

// Quick prompts shown when conversation is fresh
const _kQuickPrompts = [
  ('💪', 'What\'s my workout today?'),
  ('🍱', 'What should I eat now?'),
  ('🔥', 'Motivate me!'),
  ('📈', 'How do I level up faster?'),
  ('😴', 'Tips for better sleep?'),
  ('💊', 'Supplement advice'),
];

class _BuddyChatScreenState extends State<BuddyChatScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final intro = widget.profile.buddyIntro ??
        'Hey! I\'m ${widget.profile.buddyName}. Ask me anything about your fitness journey!';
    _messages.add(_ChatMessage(text: intro, isUser: false));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt(String text) async {
    _controller.text = text;
    await _send();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _loading = true;
    });
    _scrollToBottom();

    final reply = await FitnessAiService.chat(text, widget.profile, widget.plan);

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: reply, isUser: false));
      _loading = false;
    });
    _scrollToBottom();
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

  bool get _showQuickPrompts => _messages.length <= 1 && !_loading;

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final color = buddyColor(widget.profile.buddyPersonality);
    final stage = widget.buddy?.displayStage ?? 1;

    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        // Subtle gradient background
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.6),
              radius: 0.8,
              colors: [color.withValues(alpha: 0.07), fc.bg],
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            // ── App bar ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              decoration: BoxDecoration(
                color: fc.card.withValues(alpha: 0.95),
                border: Border(bottom: BorderSide(color: fc.border)),
              ),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: fc.textSecondary, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
                SizedBox(
                  width: 46, height: 46,
                  child: BuddyCharacter(personality: widget.profile.buddyPersonality, stage: stage, size: 46, gender: widget.profile.gender),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.profile.buddyName,
                    style: TextStyle(color: fc.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Container(
                      width: 7, height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(color: kFitGreen, shape: BoxShape.circle),
                    ),
                    Text('Online · Stage $stage · ${widget.profile.buddyPersonality.toUpperCase()}',
                      style: TextStyle(color: fc.textHint, fontSize: 10)),
                  ]),
                ])),
                // Streak badge
                if (widget.buddy != null && widget.buddy!.streakDays > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: kFitRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kFitRed.withValues(alpha: 0.3)),
                    ),
                    child: Text('🔥 ${widget.buddy!.streakDays}d',
                      style: TextStyle(color: kFitRed, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),

            // ── Messages ───────────────────────────────────────────────
            Expanded(
              child: GestureDetector(
                onTap: () => _focusNode.unfocus(),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length + (_loading ? 1 : 0) + (_showQuickPrompts ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    // Quick prompts tile after first message
                    if (_showQuickPrompts && i == 1) {
                      return _QuickPrompts(color: color, onTap: _sendPrompt);
                    }
                    final msgIndex = _showQuickPrompts && i > 1 ? i - 1 : i;
                    if (msgIndex == _messages.length) return _TypingIndicator(color: color);
                    final msg = _messages[msgIndex];
                    return _MessageBubble(
                      message: msg,
                      buddyColor: color,
                      personality: widget.profile.buddyPersonality,
                      stage: stage,
                      gender: widget.profile.gender,
                    );
                  },
                ),
              ),
            ),

            // ── Input ─────────────────────────────────────────────────
            _InputBar(
              controller: _controller,
              focusNode: _focusNode,
              loading: _loading,
              accentColor: color,
              onSend: _send,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Quick Prompts ────────────────────────────────────────────────────────────

class _QuickPrompts extends StatelessWidget {
  final Color color;
  final void Function(String) onTap;
  const _QuickPrompts({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 42, bottom: 8),
          child: Text('Quick questions', style: TextStyle(color: fc.textDisabled, fontSize: 11)),
        ),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kQuickPrompts.map((p) => GestureDetector(
            onTap: () => onTap(p.$2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(p.$1, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(p.$2, style: TextStyle(color: fc.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
          )).toList(),
        ),
      ]),
    );
  }
}

// ─── Message Bubble ──────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final Color buddyColor;
  final String personality;
  final int stage;
  final String gender;

  const _MessageBubble({
    required this.message,
    required this.buddyColor,
    required this.personality,
    required this.stage,
    this.gender = 'male',
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final isUser = message.isUser;
    final timeStr = '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            SizedBox(
              width: 34, height: 34,
              child: BuddyCharacter(personality: personality, stage: stage, size: 34, gender: gender),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  decoration: BoxDecoration(
                    color: isUser ? buddyColor : fc.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser ? buddyColor.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8, offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : fc.textPrimary,
                      fontSize: 14, height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(timeStr, style: TextStyle(color: fc.textDisabled, fontSize: 10)),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─── Typing Indicator ────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, child) => Row(
              children: List.generate(3, (i) {
                final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
                final opacity = (t < 0.5 ? t : 1.0 - t) * 2;
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.3 + opacity * 0.7),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Input Bar ───────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Color accentColor;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.accentColor,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottom),
      decoration: BoxDecoration(
        color: fc.card,
        border: Border(top: BorderSide(color: fc.border.withValues(alpha: 0.5))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: fc.inputFill,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: fc.border.withValues(alpha: 0.6)),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: fc.textPrimary, fontSize: 14),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Ask ${controller.text.isEmpty ? "your buddy" : ""}...',
                hintStyle: TextStyle(color: fc.textHint, fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: loading ? null : onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: loading ? accentColor.withValues(alpha: 0.35) : accentColor,
              shape: BoxShape.circle,
              boxShadow: loading ? [] : [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: loading
                ? const Padding(padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
