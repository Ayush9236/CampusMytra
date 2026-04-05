import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import '../settings/theme_provider.dart';

final _sb = Supabase.instance.client;

// Gen-Z palette — matches buzz_screen
const _indigo   = Color(0xFF818CF8);
const _pink     = Color(0xFFE879F9);
const _darkBg   = Color(0xFF0A0E1A);
const _darkCard = Color(0xFF141828);
const _darkSurf = Color(0xFF1A1F35);

// ══════════════════════════════════════════════════════════
// 💬 COMMENTS SHEET
// ══════════════════════════════════════════════════════════
class CommentsSheet extends StatefulWidget {
  final String postId;
  final String postOwnerId;
  final bool isAnonymousPost;
  final String postContent;

  const CommentsSheet({
    Key? key,
    required this.postId,
    required this.postOwnerId,
    required this.isAnonymousPost,
    this.postContent = '',
  }) : super(key: key);

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _ctrl    = TextEditingController();
  final _focus   = FocusNode();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading  = true;
  bool _posting  = false;
  bool _anon     = false;
  String? _myId;
  String? _myName;
  String? _myEmoji;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _myId = _sb.auth.currentUser?.id;
    _loadProfile();
    _loadComments();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scrollCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_myId == null) return;
    try {
      final p = await _sb.from('profiles')
          .select('username, avatar_emoji')
          .eq('id', _myId!).maybeSingle();
      setState(() {
        _myName  = p?['username']?.toString() ?? 'Student';
        _myEmoji = p?['avatar_emoji']?.toString() ?? '🎓';
      });
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      final data = await _sb.from('post_comments')
          .select()
          .eq('post_id', widget.postId)
          .order('created_at');
      setState(() {
        _comments = List<Map<String, dynamic>>.from(data);
        _loading  = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  void _subscribeRealtime() {
    _channel = _sb.channel('comments_${widget.postId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'post_comments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'post_id',
          value: widget.postId),
        callback: (payload) {
          final newComment = payload.newRecord;
          if (!_comments.any((c) => c['id'] == newComment['id'])) {
            setState(() => _comments.add(newComment));
            _scrollToBottom();
          }
        })
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'post_comments',
        callback: (payload) {
          final deleted = payload.oldRecord;
          setState(() => _comments.removeWhere((c) => c['id'] == deleted['id']));
        })
      .subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
    });
  }

  Future<void> _postComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _myId == null || _posting) return;
    setState(() => _posting = true);
    try {
      await _sb.from('post_comments').insert({
        'post_id':      widget.postId,
        'user_id':      _myId,
        'content':      text,
        'is_anonymous': _anon,
        'poster_name':  _anon ? null : _myName,
        'poster_emoji': _anon ? null : _myEmoji,
      });
      _ctrl.clear();
      _focus.unfocus();

      // 🔔 Notify post owner
      if (!_anon &&
          widget.postOwnerId.isNotEmpty &&
          widget.postOwnerId != _myId) {
        NotificationService.sendCommentNotification(
          postId: widget.postId,
          postOwnerId: widget.postOwnerId,
          actorName: _myName ?? 'Someone',
          postPreview: widget.postContent,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(String commentId, String commentUserId) async {
    final isOwn       = commentUserId == _myId;
    final isPostOwner = widget.postOwnerId == _myId;
    if (!isOwn && !isPostOwner) return;

    final confirm = await showDialog<bool>(context: context, builder: (_) =>
      AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete comment?',
          style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.w800)),
        content: Text('This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textHint(context)))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Delete', style: TextStyle(color: AppColors.text(context)))),
        ]));
    if (confirm != true) return;
    await _sb.from('post_comments').delete().eq('id', commentId);
  }

  String _timeAgo(String dateStr) {
    final d    = DateTime.parse(dateStr).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inHours   < 1)  return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1)  return '${diff.inHours}h ago';
    if (diff.inDays    == 1) return 'Yesterday';
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final bottom   = MediaQuery.of(context).viewInsets.bottom;
    final isDark   = AppColors.isDark(context);
    final bgColor  = isDark ? _darkCard   : Colors.white;
    final surfColor= isDark ? _darkSurf   : const Color(0xFFF4F4F8);
    final textCol  = AppColors.text(context);
    final subCol   = AppColors.textSecondary(context);
    final borderCol= AppColors.border(context);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Gradient handle bar ──
        Container(
          margin: const EdgeInsets.only(top: 14),
          width: 36, height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
            borderRadius: BorderRadius.circular(2))),

        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  _indigo.withOpacity(0.2),
                  _pink.withOpacity(0.2),
                ]),
                borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: Text('💬', style: TextStyle(fontSize: 16)))),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFFE879F9)],
              ).createShader(b),
              child: Text('Comments',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _indigo.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _indigo.withOpacity(0.25))),
              child: Text('${_comments.length}',
                style: TextStyle(
                  color: _indigo,
                  fontSize: 12,
                  fontWeight: FontWeight.w800))),
          ])),

        Divider(color: borderCol, height: 1),

        // ── Comments list ──
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: _loading
            ? Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(
                    color: _indigo, strokeWidth: 2,
                    backgroundColor: _indigo.withOpacity(0.1)))))
            : _comments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _indigo.withOpacity(0.15),
                          _pink.withOpacity(0.15),
                        ]),
                        borderRadius: BorderRadius.circular(20)),
                      child: Center(
                        child: Text('💬', style: TextStyle(fontSize: 28)))),
                    const SizedBox(height: 12),
                    Text('No comments yet',
                      style: TextStyle(
                        color: textCol,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Be the first to say something!',
                      style: TextStyle(color: subCol, fontSize: 12)),
                  ]))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c          = _comments[i];
                    final isAnon     = c['is_anonymous'] as bool? ?? false;
                    final isOwn      = c['user_id'] == _myId;
                    final isPostOwner= widget.postOwnerId == _myId;
                    final canDelete  = isOwn || isPostOwner;
                    final name  = isAnon ? 'Anonymous' : (c['poster_name'] ?? 'Student');
                    final emoji = isAnon ? '🎭' : (c['poster_emoji'] ?? '🎓');

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(colors: [
                                isAnon
                                  ? Colors.purple.withOpacity(0.3)
                                  : _indigo.withOpacity(0.25),
                                Colors.transparent,
                              ]),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isAnon
                                  ? Colors.purple.withOpacity(0.3)
                                  : _indigo.withOpacity(0.3),
                                width: 1.5)),
                            child: Center(child: Text(emoji,
                              style: TextStyle(fontSize: 17)))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(name, style: TextStyle(
                                  color: textCol,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5)),
                                const SizedBox(width: 6),
                                Text(_timeAgo(c['created_at'].toString()),
                                  style: TextStyle(color: subCol, fontSize: 10)),
                                if (isOwn) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        _indigo.withOpacity(0.2),
                                        _pink.withOpacity(0.2),
                                      ]),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _indigo.withOpacity(0.3))),
                                    child: Text('you',
                                      style: TextStyle(
                                        color: _indigo,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3)))],
                                if (isAnon) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.purple.withOpacity(0.25))),
                                    child: Text('anon',
                                      style: TextStyle(
                                        color: Colors.purpleAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3)))],
                              ]),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: surfColor,
                                  borderRadius: const BorderRadius.only(
                                    topRight:    Radius.circular(14),
                                    bottomLeft:  Radius.circular(14),
                                    bottomRight: Radius.circular(14)),
                                  border: Border.all(color: borderCol)),
                                child: Text(c['content'].toString(),
                                  style: TextStyle(
                                    color: textCol,
                                    fontSize: 13.5,
                                    height: 1.45))),
                            ])),
                          if (canDelete)
                            GestureDetector(
                              onTap: () => _deleteComment(
                                c['id'].toString(), c['user_id'].toString()),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6, top: 10),
                                child: Icon(Icons.close_rounded,
                                  color: subCol.withOpacity(0.4), size: 15))),
                        ]));
                  })),

        Divider(color: borderCol, height: 1),

        // ── Input row ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _anon = !_anon);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _anon
                    ? Colors.purple.withOpacity(0.15)
                    : surfColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _anon
                      ? Colors.purple.withOpacity(0.5)
                      : borderCol,
                    width: 1.5)),
                child: Center(child: Text(_anon ? '🎭' : (_myEmoji ?? '🎓'),
                  style: TextStyle(fontSize: 20))))),
            const SizedBox(width: 10),
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: surfColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol)),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(color: textCol, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _anon
                    ? 'Comment anonymously...'
                    : 'Add a comment...',
                  hintStyle: TextStyle(
                    color: subCol, fontSize: 13,
                    fontStyle: FontStyle.italic),
                  filled: false,
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10)),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _postComment()))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _posting ? null : _postComment,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: _posting ? null : const LinearGradient(
                    colors: [Color(0xFF818CF8), Color(0xFFE879F9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                  color: _posting ? surfColor : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _posting ? null : [
                    BoxShadow(
                      color: _indigo.withOpacity(0.35),
                      blurRadius: 10, offset: const Offset(0, 4))]),
                child: _posting
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: _indigo, strokeWidth: 2))
                  : Icon(Icons.send_rounded,
                      color: Colors.white, size: 20))),
          ])),
      ]));
  }
}


// ══════════════════════════════════════════════════════════
// 📊 POLL WIDGET (shown inside buzz card)
// ══════════════════════════════════════════════════════════
class PollWidget extends StatefulWidget {
  final String postId;
  final String? myUserId;
  final bool isOwner; // ← NEW: true when the viewer is the post creator

  const PollWidget({
    Key? key,
    required this.postId,
    this.myUserId,
    this.isOwner = false, // ← NEW
  }) : super(key: key);

  @override
  State<PollWidget> createState() => _PollWidgetState();
}

class _PollWidgetState extends State<PollWidget> {
  // Static cache — survives widget rebuilds, cleared only on app restart
  static final Map<String, Map<String, dynamic>?> _pollCache = {};
  static final Map<String, List<Map<String, dynamic>>> _votesCache = {};

  Map<String, dynamic>? _poll;
  List<Map<String, dynamic>> _votes = [];
  int? _myVote;
  bool _loading = true;
  bool _voting  = false;

  // ── NEW: refresh timer for poll owner ──
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Poll owner gets live vote count refresh every 10 seconds
    if (widget.isOwner) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) _loadFresh();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel(); // ← NEW: clean up timer
    super.dispose();
  }

  Future<void> _load() async {
    // Owners always bypass cache so they see fresh vote counts immediately
    // Non-owners serve from cache to avoid DB hit on every scroll rebuild
    if (!widget.isOwner && _pollCache.containsKey(widget.postId)) {
      final cached = _pollCache[widget.postId];
      final cachedVotes = List<Map<String, dynamic>>.from(
          _votesCache[widget.postId] ?? []);
      // Always recompute _myVote from the live votes list —
      // never trust a cached int since the user may have changed/removed their vote
      int? myVote;
      if (cached != null && widget.myUserId != null) {
        try {
          myVote = cachedVotes
              .firstWhere((v) => v['user_id'] == widget.myUserId)['option_index'] as int;
        } catch (_) { myVote = null; }
      }
      if (mounted) setState(() {
        _poll    = cached;
        _votes   = cachedVotes;
        _myVote  = myVote;
        _loading = false;
      });
      return;
    }

    try {
      final pollData = await _sb.from('post_polls')
          .select()
          .eq('post_id', widget.postId)
          .maybeSingle();
      if (!mounted) return;
      if (pollData == null) {
        _pollCache[widget.postId] = null;
        setState(() { _poll = null; _loading = false; });
        return;
      }

      final votesRaw = await _sb.from('poll_votes')
          .select()
          .eq('poll_id', pollData['id'].toString());
      if (!mounted) return;
      final votes = List<Map<String, dynamic>>.from(votesRaw as List);

      int? myVote;
      if (widget.myUserId != null) {
        try {
          final myVoteRow = votes.firstWhere(
            (v) => v['user_id'] == widget.myUserId);
          myVote = myVoteRow['option_index'] as int;
        } catch (_) { myVote = null; }
      }

      if (!mounted) return;
      _pollCache[widget.postId]  = pollData;
      _votesCache[widget.postId] = votes;
      setState(() {
        _poll    = pollData;
        _votes   = votes;
        _myVote  = myVote;
        _loading = false;
      });
    } catch (e) {
      debugPrint('PollWidget error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── NEW: lightweight vote-only refresh (skips poll meta re-fetch) ──
  // Called every 10s for the post owner so they see live vote counts.
  // Only fetches poll_votes — not post_polls — since the poll structure
  // doesn't change after creation.
  Future<void> _loadFresh() async {
    if (_poll == null) return; // poll not loaded yet, skip
    try {
      final votesRaw = await _sb.from('poll_votes')
          .select()
          .eq('poll_id', _poll!['id'].toString());
      if (!mounted) return;
      final votes = List<Map<String, dynamic>>.from(votesRaw as List);

      int? myVote;
      if (widget.myUserId != null) {
        try {
          final myVoteRow = votes.firstWhere(
            (v) => v['user_id'] == widget.myUserId);
          myVote = myVoteRow['option_index'] as int;
        } catch (_) { myVote = null; }
      }

      // Update shared cache with fresh list from DB
      _votesCache[widget.postId] = List<Map<String, dynamic>>.from(votes);

      if (mounted) setState(() {
        _votes  = votes;
        _myVote = myVote;
      });
    } catch (_) {
      // Silent fail — next timer tick will retry
    }
  }

  Future<void> _vote(int optionIndex) async {
    if (_voting || widget.myUserId == null || _poll == null) return;

    // Check if poll is closed
    final closesAt = _poll!['closes_at'] != null
        ? DateTime.parse(_poll!['closes_at'].toString()) : null;
    if (closesAt != null && DateTime.now().isAfter(closesAt)) return;

    // Optimistically mark voting in progress
    if (mounted) setState(() => _voting = true);
    try {
      final alreadyVoted = _myVote != null;
      final sameOption   = _myVote == optionIndex;

      if (alreadyVoted && sameOption) {
        // ── REMOVE vote: tapped same option again ──
        await _sb.from('poll_votes')
            .delete()
            .eq('poll_id', _poll!['id'].toString())
            .eq('user_id', widget.myUserId!);
        if (mounted) setState(() {
          _votes.removeWhere((v) => v['user_id'] == widget.myUserId);
          _myVote = null;
        });
      } else if (alreadyVoted && !sameOption) {
        // ── CHANGE vote: tapped a different option ──
        await _sb.from('poll_votes')
            .delete()
            .eq('poll_id', _poll!['id'].toString())
            .eq('user_id', widget.myUserId!);
        await _sb.from('poll_votes').insert({
          'poll_id':      _poll!['id'],
          'user_id':      widget.myUserId,
          'option_index': optionIndex,
        });
        if (mounted) setState(() {
          _votes.removeWhere((v) => v['user_id'] == widget.myUserId);
          _votes.add({
            'poll_id':      _poll!['id'],
            'user_id':      widget.myUserId,
            'option_index': optionIndex,
          });
          _myVote = optionIndex;
        });
      } else {
        // ── NEW vote: first time voting ──
        await _sb.from('poll_votes').insert({
          'poll_id':      _poll!['id'],
          'user_id':      widget.myUserId,
          'option_index': optionIndex,
        });
        if (mounted) setState(() {
          _myVote = optionIndex;
          _votes.add({
            'poll_id':      _poll!['id'],
            'user_id':      widget.myUserId,
            'option_index': optionIndex,
          });
        });
      }

      // Always write the full updated votes list back to cache so that
      // if the widget rebuilds (scroll away/back), _myVote is recomputed
      // correctly from this fresh list
      _votesCache[widget.postId] = List<Map<String, dynamic>>.from(_votes);
    } catch (_) {
      // On any DB error reload fresh state so UI isn't stuck
      _loadFresh();
    } finally {
      // Always release the voting lock — must happen even if widget
      // was disposed mid-flight, so we guard with mounted check
      if (mounted) setState(() => _voting = false);
    }
  }

  bool get _isClosed {
    if (_poll == null) return false;
    final closesAt = _poll!['closes_at'] != null
        ? DateTime.parse(_poll!['closes_at'].toString()) : null;
    return closesAt != null && DateTime.now().isAfter(closesAt);
  }

  String _closesLabel() {
    if (_poll == null || _poll!['closes_at'] == null) return '';
    final closesAt = DateTime.parse(_poll!['closes_at'].toString()).toLocal();
    if (_isClosed) return '🔒 Poll closed';
    final diff = closesAt.difference(DateTime.now());
    if (diff.inDays > 0) return '⏱ ${diff.inDays}d left';
    if (diff.inHours > 0) return '⏱ ${diff.inHours}h left';
    return '⏱ ${diff.inMinutes}m left';
  }

  void _showVoters(BuildContext context, int optionIndex, String optionLabel) {
    final voters = _votes.where((v) => v['option_index'] == optionIndex).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Builder(builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.isDark(ctx) ? _darkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 14),
            width: 36, height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
              borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              Expanded(child: Text('Voted for "$optionLabel"',
                style: TextStyle(color: Color(0xFF818CF8),
                  fontSize: 15, fontWeight: FontWeight.w900))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color(0xFF818CF8).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
                child: Text('${voters.length}',
                  style: TextStyle(color: Color(0xFF818CF8),
                    fontSize: 12, fontWeight: FontWeight.w800))),
            ])),
          Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: voters.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No votes yet',
                    style: TextStyle(color: AppColors.textHint(context))))
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchVoterProfiles(voters),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(
                        color: _indigo, strokeWidth: 2)));
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: snap.data!.length,
                      itemBuilder: (_, i) {
                        final p = snap.data![i];
                        return ListTile(
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(colors: [
                                const Color(0xFF818CF8).withOpacity(0.25),
                                Colors.transparent,
                              ]),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF818CF8).withOpacity(0.3))),
                            child: Center(child: Text(
                              p['avatar_emoji'] ?? '🎓',
                              style: TextStyle(fontSize: 18)))),
                          title: Text(p['username'] ?? 'Unknown',
                            style: TextStyle(
                              color: AppColors.text(ctx),
                              fontWeight: FontWeight.w700, fontSize: 13)),
                          subtitle: Text(p['branch_name'] ?? '',
                            style: TextStyle(
                              color: AppColors.textSecondary(ctx),
                              fontSize: 11)),
                        );
                      });
                  })),
          const SizedBox(height: 16),
        ]))));
  }

  Future<List<Map<String, dynamic>>> _fetchVoterProfiles(
      List<Map<String, dynamic>> voters) async {
    try {
      final ids = voters.map((v) => v['user_id'].toString()).toList();
      final profiles = await _sb.from('profiles')
          .select('id, username, avatar_emoji, branch_name')
          .inFilter('id', ids);
      return List<Map<String, dynamic>>.from(profiles);
    } catch (_) { return []; }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(color: _indigo, strokeWidth: 2))));
    if (_poll == null) return const SizedBox.shrink();

    final options     = (_poll!['options'] as List).cast<String>();
    final question    = _poll!['question'].toString();
    final total       = _votes.length;
    final hasVoted    = _myVote != null;
    final isAnonPoll  = _poll!['is_anonymous'] as bool? ?? true;
    // Always show results once there are votes, or after user votes
    final showResults = hasVoted || _isClosed || total > 0;

    final isDark = AppColors.isDark(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? _darkSurf : const Color(0xFFF4F4F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _indigo.withOpacity(isDark ? 0.2 : 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('📊', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('POLL', style: TextStyle(color: Color(0xFF818CF8),
            fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (isAnonPoll ? Colors.purple : Colors.orange).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text(isAnonPoll ? '🎭 Anon' : '👁️ Public',
              style: TextStyle(
                color: isAnonPoll ? Colors.purple.shade200 : Colors.orange.shade300,
                fontSize: 9, fontWeight: FontWeight.w800))),
          const Spacer(),
          // ── NEW: live indicator for owner ──
          if (widget.isOwner) ...[
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF4ADE80),
                shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('live', style: TextStyle(
              color: const Color(0xFF4ADE80),
              fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
            const SizedBox(width: 8),
          ],
          if (_closesLabel().isNotEmpty)
            Text(_closesLabel(), style: TextStyle(
              color: _isClosed ? Colors.red.shade300 : Colors.white38,
              fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(question, style: TextStyle(
          color: AppColors.text(context), fontSize: 14, fontWeight: FontWeight.w800,
          height: 1.3)),
        const SizedBox(height: 10),
        ...List.generate(options.length, (i) {
          final voteCount = _votes.where((v) =>
            v['option_index'] == i).length;
          final pct = total == 0 ? 0.0 : voteCount / total;
          final isMyChoice = _myVote == i;
          final optColor = isMyChoice ? _indigo
            : showResults ? AppColors.border(context)
            : AppColors.border(context);

          return GestureDetector(
            onTap: () {
              if (_isClosed) return;
              // Always delegate to _vote() — it reads fresh _myVote from
              // state at call time, so stale closure values don't matter
              _vote(i);
            },
            onLongPress: () {
              // Long-press on any option in a public poll shows voters
              if (!isAnonPoll && showResults) {
                _showVoters(context, i, options[i]);
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: optColor)),
              child: Stack(children: [
                // Progress bar
                if (showResults)
                  FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isMyChoice
                          ? _indigo.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10)))),
                // Label
                SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      if (isMyChoice)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_circle,
                            color: _indigo, size: 16)),
                      Expanded(child: Text(options[i],
                        style: TextStyle(
                          color: isMyChoice ? _indigo : AppColors.text(context),
                          fontSize: 13,
                          fontWeight: isMyChoice
                            ? FontWeight.w700 : FontWeight.w500))),
                      if (showResults)
                        Text('${(pct * 100).round()}%',
                          style: TextStyle(
                            color: isMyChoice ? _indigo : AppColors.textSecondary(context),
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    ]))),
              ])));
        }),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            Text(total == 0 ? 'No votes yet' : '$total vote${total == 1 ? '' : 's'}',
              style: TextStyle(color: AppColors.textSecondary(context),
                fontSize: 11)),
            if (!_isClosed) ...[
              const SizedBox(width: 8),
              Text(
                hasVoted
                  ? '· Tap to change or remove'
                  : '· Tap to vote',
                style: TextStyle(color: _indigo.withOpacity(0.6),
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ],
            if (!isAnonPoll && showResults) ...[
              const SizedBox(width: 8),
              Text('· Long press to see voters',
                style: TextStyle(color: Colors.white.withOpacity(0.3),
                  fontSize: 10)),
            ],
            if (hasVoted) ...[
              const SizedBox(width: 8),
              Text('· Voted ✓',
                style: TextStyle(color: Colors.green.withOpacity(0.7),
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ])),
      ]));
  }
}

// ══════════════════════════════════════════════════════════
// ➕ POLL CREATOR (used inside _NewPostSheet)
// ══════════════════════════════════════════════════════════
class PollCreator extends StatefulWidget {
  final void Function(PollData? poll) onChange;
  const PollCreator({Key? key, required this.onChange}) : super(key: key);

  @override
  State<PollCreator> createState() => _PollCreatorState();
}

class PollData {
  final String question;
  final List<String> options;
  final DateTime? closesAt;
  final bool isAnonymous;
  PollData({required this.question, required this.options, this.closesAt, this.isAnonymous = true});
}

class _PollCreatorState extends State<PollCreator> {
  bool _enabled = false;
  bool _isAnonymousPoll = true;
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  DateTime? _closesAt;
  String _duration = 'never';

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_enabled) { widget.onChange(null); return; }
    final question = _questionCtrl.text.trim();
    final options  = _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (question.isEmpty || options.length < 2) {
      widget.onChange(null); return;
    }
    widget.onChange(PollData(
      question: question,
      options: options,
      closesAt: _closesAt,
      isAnonymous: _isAnonymousPoll));
  }

  void _setDuration(String val) {
    setState(() {
      _duration = val;
      switch (val) {
        case '1d': _closesAt = DateTime.now().add(const Duration(days: 1)); break;
        case '3d': _closesAt = DateTime.now().add(const Duration(days: 3)); break;
        case '7d': _closesAt = DateTime.now().add(const Duration(days: 7)); break;
        default:   _closesAt = null;
      }
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Toggle
      GestureDetector(
        onTap: () {
          setState(() => _enabled = !_enabled);
          _notify();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _enabled
              ? _indigo.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _enabled
              ? _indigo.withOpacity(0.4)
              : Colors.white.withOpacity(0.1))),
          child: Row(children: [
            Text('📊', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('Add Poll', style: TextStyle(
              color: _enabled ? _indigo : Colors.white60,
              fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            Container(
              width: 36, height: 20,
              decoration: BoxDecoration(
                color: _enabled ? _indigo : Colors.white24,
                borderRadius: BorderRadius.circular(10)),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _enabled
                  ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)))),
          ])),
      ),

      if (_enabled) ...[
        const SizedBox(height: 10),
        // Question
        TextField(
          controller: _questionCtrl,
          onChanged: (_) => _notify(),
          maxLength: 200,
          style: TextStyle(color: Colors.white, fontSize: 13),
          decoration: _deco('Poll question...'),
        ),
        const SizedBox(height: 8),
        // Options
        ...List.generate(_optionCtrls.length, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _optionCtrls[i],
              onChanged: (_) => _notify(),
              maxLength: 80,
              style: TextStyle(color: Colors.white, fontSize: 13),
              decoration: _deco('Option ${i + 1}'),
            )),
            if (i >= 2)
              GestureDetector(
                onTap: () {
                  setState(() { _optionCtrls.removeAt(i); });
                  _notify();
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.remove_circle_outline,
                    color: Colors.red.shade300, size: 20))),
          ]))),
        // Add option button
        if (_optionCtrls.length < 4)
          GestureDetector(
            onTap: () {
              setState(() => _optionCtrls.add(TextEditingController()));
              _notify();
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.add_circle_outline, color: _indigo, size: 18),
                const SizedBox(width: 6),
                Text('Add option',
                  style: TextStyle(color: _indigo, fontSize: 12,
                    fontWeight: FontWeight.w600)),
              ]))),
        // Duration picker
        Text('Poll duration:',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          _DurChip(label: 'No limit', val: 'never',
            selected: _duration == 'never', onTap: () => _setDuration('never')),
          _DurChip(label: '1 day',    val: '1d',
            selected: _duration == '1d',    onTap: () => _setDuration('1d')),
          _DurChip(label: '3 days',   val: '3d',
            selected: _duration == '3d',    onTap: () => _setDuration('3d')),
          _DurChip(label: '7 days',   val: '7d',
            selected: _duration == '7d',    onTap: () => _setDuration('7d')),
        ]),
        const SizedBox(height: 10),
        // Anonymous votes toggle
        GestureDetector(
          onTap: () {
            setState(() => _isAnonymousPoll = !_isAnonymousPoll);
            _notify();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              Text(_isAnonymousPoll ? '🎭' : '👁️',
                style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_isAnonymousPoll ? 'Anonymous votes' : 'Public votes',
                  style: TextStyle(color: AppColors.text(context),
                    fontSize: 12, fontWeight: FontWeight.w700)),
                Text(_isAnonymousPoll
                  ? 'No one can see who voted what'
                  : 'Anyone can see who voted what',
                  style: TextStyle(color: Colors.white.withOpacity(0.4),
                    fontSize: 10)),
              ]),
              const Spacer(),
              Container(
                width: 36, height: 20,
                decoration: BoxDecoration(
                  color: _isAnonymousPoll ? _indigo : Colors.orange,
                  borderRadius: BorderRadius.circular(10)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: _isAnonymousPoll
                    ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle)))),
            ])),
        ),
      ],
    ]);
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
    filled: true, fillColor: _darkSurf, counterText: '',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10));
}

class _DurChip extends StatelessWidget {
  final String label, val; final bool selected; final VoidCallback onTap;
  const _DurChip({required this.label, required this.val,
    required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? _indigo.withOpacity(0.15) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? _indigo : Colors.white.withOpacity(0.1))),
      child: Text(label, style: TextStyle(
        color: selected ? _indigo : Colors.white54,
        fontSize: 11, fontWeight: FontWeight.w700))));
}