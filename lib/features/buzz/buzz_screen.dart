import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'comment_poll.dart';
import 'image_viewer.dart';
import '../profile/user_profile_screen.dart';
import 'notification_service.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../settings/theme_provider.dart';
import '../badges/badge_system.dart';
import '../buzz/moderation.dart';

final supabase = Supabase.instance.client;

// Top-level so all private classes in this file can call it
void _openProfile(BuildContext context, String userId) {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => UserProfileScreen(userId: userId)));
}

enum BuzzSort { newest, popular }
enum BuzzFeed { public, friends, college, branch }

// ══════════════════════════════════════════════
// 🖼️ BUZZ IMAGE SERVICE
// Handles compression → moderation → upload → metadata save
// ══════════════════════════════════════════════
class BuzzImageService {
  final _supabase = Supabase.instance.client;

  /// Step 1: Compress image before upload
  Future<Uint8List> compressImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();

    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1080,
      minHeight: 1080,
      quality: 75,
      format: CompressFormat.jpeg,
    );

    if (compressed.length > 5 * 1024 * 1024) {
      throw Exception('Image too large. Please pick a smaller image.');
    }

    return compressed;
  }

  /// Step 2: Moderate with AI via Supabase Edge Function
  Future<void> moderateImage(Uint8List imageBytes) async {
    try {
      final response = await _supabase.functions.invoke(
        'moderate-image',
        body: {'image': imageBytes},
      );
      final result = response.data as Map<String, dynamic>;
      final isSafe = result['safe'] as bool? ?? true;
      final reason = result['reason']?.toString() ?? '';
      if (!isSafe) {
        throw Exception(reason.isNotEmpty ? reason : 'Image not allowed');
      }
    } catch (e) {
      if (e.toString().contains('Image not allowed')) rethrow;
    }
  }

  /// Step 3: Upload compressed bytes to Supabase Storage
  Future<String> uploadImage(Uint8List bytes, String userId) async {
    final fileName =
        '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _supabase.storage.from('buzz-images').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        cacheControl: '3600',
      ),
    );
    return _supabase.storage.from('buzz-images').getPublicUrl(fileName);
  }

  /// Step 4: Save metadata to buzz_images table
  Future<void> saveImageMetadata({
    required String postId,
    required String imageUrl,
    required String uploadedBy,
  }) async {
    await _supabase.from('buzz_images').insert({
      'post_id': postId,
      'image_url': imageUrl,
      'uploaded_by': uploadedBy,
    });
  }

  /// Master method: compress → moderate → upload → save metadata
  Future<String> processAndUpload(XFile imageFile, String userId) async {
    final compressed = await compressImage(imageFile);
    await moderateImage(compressed);
    final url = await uploadImage(compressed, userId);
    return url;
  }
}

// ══════════════════════════════════════════════
// 📢 CAMPUS BUZZ SCREEN
// ══════════════════════════════════════════════
class CampusBuzzScreen extends StatefulWidget {
  const CampusBuzzScreen({Key? key}) : super(key: key);
  @override
  State<CampusBuzzScreen> createState() => _CampusBuzzScreenState();
}

class _CampusBuzzScreenState extends State<CampusBuzzScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _posts = [];
  Set<String> _likedPostIds = {};
  Set<String> _reportedPostIds = {};
  bool _isLoading = true;
  bool _isPosting = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const _pageSize = 20;
  BuzzSort _sort = BuzzSort.newest;
  BuzzFeed _feed = BuzzFeed.public;
  String? _myId;
  String? _myName;
  String? _myCollegeId;
  String? _myBranchId;
  String? _myCollegeName;
  String? _myBranchName;
  String? _myStudentId;

  // Moderation service instance
  final _moderationService = PostModerationService();

  late AnimationController _fabCtrl;
  late Animation<double> _fabScale;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _announcementChannel;
  RealtimeChannel? _adminBroadcastChannel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _fabCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fabScale =
        CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut);
    _loadProfile();
    _subscribeRealtime();
    _subscribeAnnouncements();
    _subscribeAdminBroadcast();
    _checkActiveAnnouncements();
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    _pollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _announcementChannel?.unsubscribe();
    _adminBroadcastChannel?.unsubscribe();
    super.dispose();
  }

  // ── Polling: new posts every 30s instead of realtime ──
  // Realtime on buzz_posts at 5K DAU exhausts Supabase concurrent connections.
  // Pull-to-refresh + 30s auto-poll is sufficient for a campus feed.
  void _subscribeRealtime() {
    // Keep realtime ONLY for deletes (low frequency, important for UX)
    _realtimeChannel = supabase
        .channel('buzz_posts_deletes_only')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'buzz_posts',
          callback: (payload) {
            if (!mounted) return;
            final deletedId = payload.oldRecord['id']?.toString();
            if (deletedId != null && deletedId.isNotEmpty) {
              setState(() => _posts
                  .removeWhere((p) => p['id'].toString() == deletedId));
            } else {
              _fetchPosts();
            }
          },
        )
        .subscribe();

    // Poll every 30s for new/updated posts
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchPosts(silent: true);
    });
  }

  // ── Realtime: admin broadcast deletions ──
  void _subscribeAdminBroadcast() {
    _adminBroadcastChannel = supabase
        .channel('admin_actions')
        .onBroadcast(
          event: 'post_deleted',
          callback: (payload) {
            if (!mounted) return;
            final deletedId = payload['post_id']?.toString();
            if (deletedId != null && deletedId.isNotEmpty) {
              setState(() => _posts
                  .removeWhere((p) => p['id'].toString() == deletedId));
            }
          },
        )
        .subscribe();
  }

  // ── Load user profile ──
  Future<void> _loadProfile() async {
    if (_myId == null) return;
    try {
      final p = await supabase
          .from('profiles')
          .select(
              'college_id, branch_id, college_name, branch_name, student_id, college_status, username')
          .eq('id', _myId!)
          .maybeSingle();
      if (p != null) {
        _myCollegeId   = p['college_id']?.toString();
        _myBranchId    = p['branch_id']?.toString();
        _myCollegeName = p['college_name']?.toString();
        _myBranchName  = p['branch_name']?.toString();
        _myStudentId   = p['student_id']?.toString();
        _myName        = p['username']?.toString();
        // ✅ FIX: verified users without college_id (edge case) still get college feed
        final status = p['college_status']?.toString();
        if (_myCollegeId == null && status == 'verified' && _myCollegeName != null) {
          // college_id not set yet but verified — treat college_name as identifier
          _myCollegeId = _myCollegeName; // fallback so tab isn't blocked
        }
      }
    } catch (_) {}
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait(
          [_fetchPosts(), _fetchMyLikes(), _fetchMyReports()]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _fabCtrl.forward();
      }
    }
  }

  // ── Fetch posts from buzz_feed VIEW ──
  Future<void> _fetchPosts({bool silent = false}) async {
    try {
      final orderCol =
          _sort == BuzzSort.newest ? 'created_at' : 'likes';

      // Get my friend IDs (accepted friendships)
      List<String> friendIds = [];
      try {
        final myId = supabase.auth.currentUser?.id;
        if (myId != null) {
          final asSender = await supabase.from('friendships')
              .select('receiver_id').eq('sender_id', myId).eq('status', 'accepted');
          final asReceiver = await supabase.from('friendships')
              .select('sender_id').eq('receiver_id', myId).eq('status', 'accepted');
          friendIds = [
            ...(asSender as List).map((r) => r['receiver_id'].toString()),
            ...(asReceiver as List).map((r) => r['sender_id'].toString()),
          ];
        }
      } catch (_) {}

      var query = supabase.from('buzz_feed').select();

      if (_feed == BuzzFeed.friends) {
        // Friends feed: only posts with visibility=friends from my friends
        if (friendIds.isEmpty) {
          if (mounted) setState(() => _posts = []);
          return;
        }
        final friendsPosts = await supabase.from('buzz_feed')
            .select()
            .eq('visibility', 'friends')
            .inFilter('user_id', friendIds)
            .order(orderCol, ascending: false)
            .limit(_pageSize);
        // Also include own friends-visibility posts
        final myId = supabase.auth.currentUser?.id;
        List myFriendsPosts = [];
        if (myId != null) {
          myFriendsPosts = await supabase.from('buzz_feed')
              .select()
              .eq('visibility', 'friends')
              .eq('user_id', myId)
              .order(orderCol, ascending: false)
              .limit(_pageSize);
        }
        final combined = [
          ...List<Map<String, dynamic>>.from(friendsPosts),
          ...List<Map<String, dynamic>>.from(myFriendsPosts),
        ];
        final seen = <String>{};
        final deduped = combined.where((p) => seen.add(p['id'].toString())).toList();
        deduped.sort((a, b) => orderCol == 'created_at'
            ? (b['created_at'] ?? '').compareTo(a['created_at'] ?? '')
            : ((b['likes'] ?? 0) as int).compareTo((a['likes'] ?? 0) as int));
        if (mounted) setState(() => _posts = deduped.take(_pageSize).toList());
        return;
      } else if (_feed == BuzzFeed.college && _myCollegeId != null) {
        // College feed: public + college posts
        query = query
            .eq('college_id', _myCollegeId!)
            .inFilter('visibility', ['public', 'college']);
      } else if (_feed == BuzzFeed.branch) {
        if (_myBranchId != null) {
          query = query
              .eq('branch_id', _myBranchId!)
              .eq('visibility', 'branch');
        } else if (_myBranchName != null &&
            _myBranchName!.isNotEmpty) {
          query = query
              .eq('college_id', _myCollegeId ?? '')
              .eq('branch_name', _myBranchName!)
              .eq('visibility', 'branch');
        } else {
          if (mounted) setState(() => _posts = []);
          return;
        }
      } else {
        // Public feed: only public posts
        query = query.eq('visibility', 'public');
      }

      final data =
          await query.order(orderCol, ascending: false).limit(_pageSize);
      final enriched = await _enrichWithBanners(List<Map<String, dynamic>>.from(data));
      if (mounted) {
        setState(() {
          _posts = enriched;
          _hasMore = data.length == _pageSize;
        });
      }
    } catch (e) {
      if (mounted && !silent) _showSnack('Failed to load posts', Colors.red);
    }
  }

  // ── Enrich posts with banner rank for non-anonymous posters ──────
  // Uses the existing _badgeCache from badge_system.dart's AsyncBadgeRow.
  // We do a single batch RPC call for uncached user IDs.
  final _bannerRankCache = <String, int>{};

  Future<List<Map<String, dynamic>>> _enrichWithBanners(
      List<Map<String, dynamic>> posts) async {
    // Collect unique non-anon user IDs not yet cached
    final ids = posts
        .where((p) => !(p['is_anonymous'] as bool? ?? true) && p['user_id'] != null)
        .map((p) => p['user_id'].toString())
        .toSet()
        .where((id) => !_bannerRankCache.containsKey(id))
        .toList();

    // Fetch badge data for uncached IDs (individually — reuse get_user_badge_data)
    await Future.wait(ids.map((uid) async {
      try {
        final result = await supabase
            .rpc('get_user_badge_data', params: {'p_user_id': uid});
        if (result == null) return;
        final row = (result is List && result.isNotEmpty)
            ? Map<String, dynamic>.from(result.first as Map)
            : Map<String, dynamic>.from(result as Map);
        final profile = <String, dynamic>{
          'user_id': uid,
          'admin_role':     row['admin_role'],
          'signup_rank':    (row['signup_rank'] as num?)?.toInt() ?? 999999,
          'college_status': row['college_status'],
          'uno_wins':       (row['uno_wins']       as num?)?.toInt() ?? 0,
          'dsa_wins':       (row['dsa_wins']       as num?)?.toInt() ?? 0,
          'post_count':     (row['post_count']     as num?)?.toInt() ?? 0,
          'max_post_likes': (row['max_post_likes'] as num?)?.toInt() ?? 0,
          'friend_count':   (row['friend_count']   as num?)?.toInt() ?? 0,
        };
        _bannerRankCache[uid] = computeBannerRank(profile).index;
      } catch (e) {
        debugPrint('[BannerEnrich] RPC failed for $uid: $e');
        // Don't cache on error — allow retry on next feed load
      }
    }));

    // Stamp each post with poster_banner_rank
    return posts.map((p) {
      final uid = p['user_id']?.toString();
      final isAnon = p['is_anonymous'] as bool? ?? true;
      final rankIdx = (!isAnon && uid != null) ? (_bannerRankCache[uid] ?? 0) : 0;
      return {...p, 'poster_banner_rank': rankIdx};
    }).toList();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _posts.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final orderCol = _sort == BuzzSort.newest ? 'created_at' : 'likes';
      final lastPost = _posts.last;
      final lastVal  = lastPost[orderCol];
      var query = supabase.from('buzz_feed').select();

      if (_feed == BuzzFeed.college && _myCollegeId != null) {
        query = query.eq('college_id', _myCollegeId!)
            .inFilter('visibility', ['public', 'college']);
      } else if (_feed == BuzzFeed.branch) {
        if (_myBranchId != null) {
          query = query.eq('branch_id', _myBranchId!).eq('visibility', 'branch');
        } else if (_myBranchName != null && _myBranchName!.isNotEmpty) {
          query = query.eq('college_id', _myCollegeId ?? '')
              .eq('branch_name', _myBranchName!).eq('visibility', 'branch');
        }
      } else if (_feed == BuzzFeed.friends) {
        // friends feed doesn't paginate the same way — skip for now
        if (mounted) setState(() { _isLoadingMore = false; _hasMore = false; });
        return;
      } else {
        query = query.eq('visibility', 'public');
      }

      final data = await query
          .lt(orderCol, lastVal)
          .order(orderCol, ascending: false)
          .limit(_pageSize);

      final enriched = await _enrichWithBanners(List<Map<String, dynamic>>.from(data));
      if (mounted) {
        setState(() {
          _posts.addAll(enriched);
          _hasMore = data.length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _fetchMyLikes() async {
    if (_myId == null) return;
    try {
      final data = await supabase
          .from('buzz_likes')
          .select('post_id')
          .eq('user_id', _myId!);
      if (mounted) {
        setState(() => _likedPostIds = Set<String>.from(
            (data as List).map((r) => r['post_id'].toString())));
      }
    } catch (_) {}
  }

  Future<void> _fetchMyReports() async {
    if (_myId == null) return;
    try {
      final data = await supabase
          .from('buzz_reports')
          .select('post_id')
          .eq('user_id', _myId!);
      if (mounted) {
        setState(() => _reportedPostIds = Set<String>.from(
            (data as List).map((r) => r['post_id'].toString())));
      }
    } catch (_) {}
  }

  // ── Toggle like ──
  Future<void> _toggleLike(String postId, int currentLikes) async {
    if (_myId == null) return;
    final alreadyLiked = _likedPostIds.contains(postId);
    HapticFeedback.lightImpact();
    setState(() {
      if (alreadyLiked) {
        _likedPostIds.remove(postId);
      } else {
        _likedPostIds.add(postId);
      }
      final idx = _posts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) {
        _posts[idx] = Map.from(_posts[idx])
          ..['likes'] = currentLikes + (alreadyLiked ? -1 : 1);
      }
    });
    try {
      if (alreadyLiked) {
        await supabase
            .from('buzz_likes')
            .delete()
            .eq('user_id', _myId!)
            .eq('post_id', postId);
        await supabase
            .from('buzz_posts')
            .update({'likes': currentLikes - 1}).eq('id', postId);
      } else {
        await supabase
            .from('buzz_likes')
            .insert({'user_id': _myId!, 'post_id': postId});
        await supabase
            .from('buzz_posts')
            .update({'likes': currentLikes + 1}).eq('id', postId);

        // 🔔 Notify post owner
        final post = _posts.firstWhere(
          (p) => p['id'].toString() == postId,
          orElse: () => {},
        );
        final postOwnerId = post['user_id']?.toString();
        if (postOwnerId != null && postOwnerId != _myId) {
          NotificationService.sendLikeNotification(
            postId: postId,
            postOwnerId: postOwnerId,
            actorName: _myName ?? 'Someone',
            postPreview: post['content']?.toString() ?? '',
          );
        }
      }
    } catch (_) {
      await _fetchPosts();
      await _fetchMyLikes();
    }
  }

  // ── Report post ──
  Future<void> _reportPost(String postId) async {
    if (_myId == null || _reportedPostIds.contains(postId)) return;
    try {
      await supabase
          .from('buzz_reports')
          .insert({'user_id': _myId!, 'post_id': postId});
      final post = _posts.firstWhere((p) => p['id'] == postId);
      final newReports = (post['reports'] ?? 0) + 1;
      await supabase
          .from('buzz_posts')
          .update({'reports': newReports}).eq('id', postId);
      setState(() {
        _reportedPostIds.add(postId);
        final idx = _posts.indexWhere((p) => p['id'] == postId);
        if (idx != -1) {
          _posts[idx] = Map.from(_posts[idx])
            ..['reports'] = newReports;
        }
      });
      _showSnack(
          newReports >= 20
              ? '🚩 Reported! Post flagged for review.'
              : '🚩 Reported! ($newReports/20)',
          Colors.orange);
    } catch (_) {}
  }

  // ── Delete own post ──
  Future<void> _deletePost(String postId) async {
    try {
      await supabase.from('buzz_images').delete().eq('post_id', postId);
      await supabase.from('buzz_posts').delete().eq('id', postId);
      setState(() => _posts.removeWhere((p) => p['id'] == postId));
      _showSnack('🗑️ Post deleted', Colors.red);
    } catch (e) {
      _showSnack('Delete failed: $e', Colors.red);
    }
  }

  // ── Rate limit check ──
  Future<bool> _checkRateLimit() async {
    try {
      final result = await supabase
          .rpc('can_post_buzz', params: {'p_user_id': _myId});
      return result as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  // ── Submit post (rate limit → moderate → insert → image) ──
  Future<void> _submitPost(
    String content,
    XFile? imageFile, {
    bool isAnonymous = true,
    String? posterName,
    String? posterEmoji,
    String? posterBranch,
    String? posterStudentId,
    String visibility = 'public',
    PollData? poll,
  }) async {
    if (_myId == null || content.trim().isEmpty) return;

    // Step 1: Rate limit
    final canPost = await _checkRateLimit();
    if (!canPost) {
      _showSnack('⏳ Too many posts! Max 5 per hour.', Colors.orange);
      return;
    }

    setState(() => _isPosting = true);
    try {
      // Step 2: Moderate content — client already warned,
      // server enforces final block here
      final modResult =
          await _moderationService.moderate(content);
      if (!modResult.allowed) {
        _showSnack(
            '🚫 ${modResult.reason ?? "Post not allowed."}',
            Colors.red);
        return;
      }

      // Step 3: Insert post to get post ID
      final postData = await supabase.from('buzz_posts').insert({
        'user_id': _myId,
        'content': content.trim(),
        'is_anonymous': isAnonymous,
        'poster_name': isAnonymous ? null : (posterName ?? ''),
        'poster_emoji': isAnonymous ? null : (posterEmoji ?? '🎓'),
        'poster_branch': isAnonymous ? null : (posterBranch ?? ''),
        'poster_student_id': isAnonymous
            ? null
            : (posterStudentId?.isNotEmpty == true
                ? posterStudentId
                : null),
        'visibility': visibility,
        'college_id': _myCollegeId,
        'college_name': _myCollegeName,
        'branch_id': visibility == 'branch' ? _myBranchId : null,
        'branch_name':
            visibility == 'branch' ? _myBranchName : null,
      }).select('id').single();

      final postId = postData['id'].toString();

      // Step 4b: Save poll if provided
      if (poll != null && poll.options.length >= 2) {
        try {
          await supabase.from('post_polls').insert({
            'post_id':      postId,
            'question':     poll.question,
            'options':      poll.options,
            'closes_at':    poll.closesAt?.toUtc().toIso8601String(),
            'is_anonymous': poll.isAnonymous,
          });
        } catch (e) {
          debugPrint('Poll save error: $e');
          _showSnack('⚠️ Post saved but poll failed: $e', Colors.orange);
        }
      }

      // Step 4: Handle image via BuzzImageService
      if (imageFile != null) {
        try {
          final imageService = BuzzImageService();
          final imageUrl =
              await imageService.processAndUpload(imageFile, _myId!);
          await imageService.saveImageMetadata(
            postId: postId,
            imageUrl: imageUrl,
            uploadedBy: _myId!,
          );
        } catch (e) {
          _showSnack(
              '⚠️ Post saved but image rejected: $e', Colors.orange);
          await _fetchPosts();
          return;
        }
      }

      await _fetchPosts();
      _showSnack(
        isAnonymous
            ? '🎭 Posted anonymously!'
            : '👤 Posted as $posterName!',
        const Color(0xFF00B8A3),
      );

      // 🔔 Notify college if college/branch post and not anonymous
      if (!isAnonymous &&
          _myCollegeId != null &&
          (visibility == 'college' || visibility == 'branch')) {
        NotificationService.sendCollegeBuzzNotification(
          postId: postId,
          collegeId: _myCollegeId!,
          actorName: posterName ?? _myName ?? 'Someone',
          postPreview: content.trim(),
        );
      }
    } catch (e) {
      _showSnack('Post failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // ── Announcements ──
  Future<void> _checkActiveAnnouncements() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Only fetch announcements that are scoped to a college or branch
      // (college_id IS NOT NULL). College-verification notices are handled
      // via profile flags — never via the announcements table anymore.
      final data = await supabase
          .from('announcements')
          .select()
          .eq('is_active', true)
          .not('college_id', 'is', null)   // ← skip global announcements
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null && mounted) {
        final collegeId  = data['college_id']?.toString();
        final branchId   = data['branch_id']?.toString();
        final isMyCollege = collegeId == _myCollegeId;
        final isMyBranch  = branchId  == _myBranchId;
        // Only show if it targets this user's college or branch
        if (isMyCollege || isMyBranch) {
          _showAnnouncementPopup(
            data['title']?.toString()   ?? '📢 Announcement',
            data['message']?.toString() ?? '',
          );
        }
      }
    } catch (_) {}
  }

  void _subscribeAnnouncements() {
    _announcementChannel = supabase
        .channel('announcements_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'announcements',
          callback: (payload) {
            if (!mounted) return;
            final rec       = payload.newRecord;
            final collegeId = rec['college_id']?.toString();
            final branchId  = rec['branch_id']?.toString();
            // Skip global announcements (college_id == null) —
            // college-verification notices use profile flags, not announcements
            if (collegeId == null) return;
            final isMyCollege = collegeId == _myCollegeId;
            final isMyBranch  = branchId  == _myBranchId;
            if (isMyCollege || isMyBranch) {
              _showAnnouncementPopup(
                rec['title']?.toString()   ?? '📢 Announcement',
                rec['message']?.toString() ?? '',
              );
            }
          },
        )
        .subscribe();
  }

  void _showAnnouncementPopup(String title, String message) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) =>
          _AnnouncementPopup(title: title, message: message),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3)));
  }

  void _openNewPostSheet() async {
    HapticFeedback.mediumImpact();
    Map<String, dynamic>? profile;
    try {
      profile = await supabase
          .from('profiles')
          .select('username, avatar_emoji, branch_name, college_name')
          .eq('id', _myId!)
          .maybeSingle();
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewPostSheet(
        posterName: profile?['username']?.toString() ?? 'Student',
        posterEmoji:
            profile?['avatar_emoji']?.toString() ?? '🎓',
        posterBranch:
            profile?['branch_name']?.toString() ?? '',
        posterStudentId: _myStudentId ?? '',
        collegeName: _myCollegeName ?? '',
        branchName: _myBranchName ?? '',
        moderationService: _moderationService,
        defaultVisibility: _feed == BuzzFeed.friends ? 'friends'     // ADD THIS
        : _feed == BuzzFeed.college ? 'college'
        : _feed == BuzzFeed.branch ? 'branch'
        : 'public',
        onPost: (content, imageFile, isAnonymous, visibility, poll) async {
          await _submitPost(
            content,
            imageFile,
            isAnonymous: isAnonymous,
            visibility: visibility,
            posterName: profile?['username']?.toString() ?? '',
            posterEmoji:
                profile?['avatar_emoji']?.toString() ?? '🎓',
            posterBranch:
                profile?['branch_name']?.toString() ?? '',
            posterStudentId: _myStudentId ?? '',
            poll: poll,
          );
        },
      ),
    );
  }

  void _showReportDialog(String postId) {
    if (_reportedPostIds.contains(postId)) {
      _showSnack('Already reported', Colors.grey);
      return;
    }
    final post = _posts.firstWhere((p) => p['id'] == postId);
    final currentReports = (post['reports'] ?? 0) as int;
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Report Post?',
                  style: TextStyle(
                      color: AppColors.text(context),
                      fontWeight: FontWeight.w800)),
              content:
                  Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Flag as inappropriate.',
                    style: TextStyle(
                        color: AppColors.textSecondary(context))),
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withOpacity(0.3))),
                    child: Column(children: [
                      Row(children: [
                        Text('📊',
                            style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                            '${currentReports + 1}/20 reports after yours',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                          value: (currentReports + 1) / 20,
                          backgroundColor:
                              Colors.orange.withOpacity(0.2),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  Colors.orange),
                          borderRadius: BorderRadius.circular(4)),
                    ])),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                            color:
                                AppColors.textSecondary(context)))),
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _reportPost(postId);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    child: Text('Report 🚩',
                        style: TextStyle(color: AppColors.text(context)))),
              ],
            ));
  }

  void _showDeleteDialog(String postId) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Delete Post?',
                  style: TextStyle(
                      color: AppColors.text(context),
                      fontWeight: FontWeight.w800)),
              content: Text('This cannot be undone.',
                  style: TextStyle(
                      color: AppColors.textSecondary(context))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                            color:
                                AppColors.textSecondary(context)))),
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deletePost(postId);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.text(context)))),
              ],
            ));
  }

  String _feedLabel() {
    switch (_feed) {
      case BuzzFeed.friends:
        return 'Friends';
      case BuzzFeed.college:
        return _myCollegeName ?? 'My College';
      case BuzzFeed.branch:
        return _myBranchName ?? 'My Branch';
      default:
        return 'Public';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
          child: Column(children: [
        // ── HEADER ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFE879F9), Color(0xFF818CF8), Color(0xFF38BDF8)],
                      stops: [0.0, 0.5, 1.0],
                    ).createShader(bounds),
                    child: Text('Campus Buzz',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text(context),
                        letterSpacing: -1.2,
                        height: 1.0,
                      )),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('anon · real · unfiltered',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w500,
                      )),
                  ]),
                ])),
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF818CF8).withOpacity(0.15),
                        const Color(0xFFE879F9).withOpacity(0.15),
                      ]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Icon(Icons.refresh_rounded,
                    color: AppColors.textSecondary(context), size: 18))),
            ]),
        ),
        const SizedBox(height: 16),

        // ── FEED TABS ──
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _FeedTab(
                  label: '🌍 Public',
                  selected: _feed == BuzzFeed.public,
                  color: const Color(0xFF6C63FF),
                  onTap: () {
                    setState(() => _feed = BuzzFeed.public);
                    _fetchPosts();
                  }),
              const SizedBox(width: 8),
              _FeedTab(
                  label: '👥 Friends',
                  selected: _feed == BuzzFeed.friends,
                  color: const Color(0xFFE879F9),
                  onTap: () {
                    setState(() => _feed = BuzzFeed.friends);
                    _fetchPosts();
                  }),
              const SizedBox(width: 8),
              _FeedTab(
                  label:
                      '🏫 ${_myCollegeName ?? "My College"}',
                  selected: _feed == BuzzFeed.college,
                  color: const Color(0xFF00B8A3),
                  onTap: () {
                    // ✅ FIX: Allow if college_id set OR college_name set (verified pending college_id)
                    if (_myCollegeId == null && (_myCollegeName == null || _myCollegeName!.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '⚠️ Update your profile to set your college first!'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating));
                      return;
                    }
                    setState(() => _feed = BuzzFeed.college);
                    _fetchPosts();
                  }),
              const SizedBox(width: 8),
              _FeedTab(
                  label:
                      '🎓 ${(_myBranchName != null && _myBranchName!.length > 6) ? _myBranchName!.split(' ').take(2).join(' ') : (_myBranchName ?? "My Branch")}',
                  selected: _feed == BuzzFeed.branch,
                  color: const Color(0xFFFFB800),
                  onTap: () {
                    if (_myBranchId == null &&
                        (_myBranchName == null ||
                            _myBranchName!.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '⚠️ Update your profile to set your branch first!'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating));
                      return;
                    }
                    setState(() => _feed = BuzzFeed.branch);
                    _fetchPosts();
                  }),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── SORT CHIPS ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
                child: _FilterChip(
                    label: '🕐 Newest',
                    selected: _sort == BuzzSort.newest,
                    onTap: () {
                      if (_sort != BuzzSort.newest) {
                        setState(() => _sort = BuzzSort.newest);
                        _fetchPosts();
                      }
                    })),
            const SizedBox(width: 10),
            Expanded(
                child: _FilterChip(
                    label: '🔥 Popular',
                    selected: _sort == BuzzSort.popular,
                    onTap: () {
                      if (_sort != BuzzSort.popular) {
                        setState(() => _sort = BuzzSort.popular);
                        _fetchPosts();
                      }
                    })),
          ]),
        ),
        const SizedBox(height: 12),

        // ── POSTS ──
        Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                        Text('📢',
                            style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 16),
                        CircularProgressIndicator(
                            color: primary, strokeWidth: 2)
                      ]))
                : _posts.isEmpty
                    ? _EmptyState(
                        onPost: _openNewPostSheet,
                        feedLabel: _feedLabel())
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: primary,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (s) {
                            if (s is ScrollEndNotification &&
                                s.metrics.extentAfter < 300) {
                              _loadMore();
                            }
                            return false;
                          },
                          child: ListView.builder(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          cacheExtent: 800,
                          padding: const EdgeInsets.fromLTRB(
                              20, 0, 20, 100),
                          itemCount: _posts.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _posts.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: _isLoadingMore
                                  ? CircularProgressIndicator(strokeWidth: 2)
                                  : const SizedBox.shrink()));
                            }
                            final post = _posts[i];
                            final postId = post['id'].toString();
                            final isOwn =
                                post['user_id'] == _myId;
                            final reports = post['reports'] ?? 0;
                            if (reports >= 20 && !isOwn) {
                              return const SizedBox.shrink();
                            }
                            return _BuzzCard(
                              key: ValueKey(postId),
                              post: post,
                              isOwn: isOwn,
                              isLiked:
                                  _likedPostIds.contains(postId),
                              isReported: _reportedPostIds
                                  .contains(postId),
                              onLike: () => _toggleLike(
                                  postId, post['likes'] ?? 0),
                              onReport: () =>
                                  _showReportDialog(postId),
                              onDelete: () =>
                                  _showDeleteDialog(postId),
                              onProfileTap: (uid) => _openProfile(context, uid),
                            );
                          },
                        )))),
      ])),
      floatingActionButton: ScaleTransition(
        scale: _fabScale,
        child: GestureDetector(
          onTap: _isPosting ? null : _openNewPostSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE879F9), Color(0xFF818CF8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF818CF8).withOpacity(0.4),
                  blurRadius: 20, offset: const Offset(0, 8)),
              ]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _isPosting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('*', style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(width: 8),
              Text(_isPosting ? 'posting...' : 'Buzz It',
                style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900,
                  fontSize: 14, letterSpacing: 0.5)),
            ]))),
      ),
    );
  }
}

// ── FEED TAB ──
class _FeedTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const _FeedTab(
      {required this.label,
      required this.selected,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? LinearGradient(
              colors: [color.withOpacity(0.25), color.withOpacity(0.1)],
            ) : null,
            color: selected ? null : AppColors.surfaceVariant(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? color.withOpacity(0.7) : AppColors.border(context),
              width: 1.5)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? color : AppColors.textSecondary(context),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 12,
                  letterSpacing: 0.2))));
}

// ── SORT CHIP ──
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                gradient: selected ? const LinearGradient(
                  colors: [Color(0xFF818CF8), Color(0xFFE879F9)],
                ) : null,
                color: selected ? null : AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected
                      ? Colors.transparent
                      : AppColors.border(context),
                    width: 1.5),
                boxShadow: selected ? [
                  BoxShadow(
                    color: const Color(0xFF818CF8).withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))
                ] : null),
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        color: selected ? Colors.white : AppColors.textSecondary(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 13)))));
  }
}

// ── BUZZ CARD ──
class _BuzzCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isOwn, isLiked, isReported;
  final VoidCallback onLike, onReport, onDelete;
  final void Function(String userId)? onProfileTap;

  const _BuzzCard(
      {super.key,
      required this.post,
      required this.isOwn,
      required this.isLiked,
      required this.isReported,
      required this.onLike,
      required this.onReport,
      required this.onDelete,
      this.onProfileTap});

  @override
  State<_BuzzCard> createState() => _BuzzCardState();
}

class _BuzzCardState extends State<_BuzzCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _likeCtrl;
  late Animation<double> _likeScale;

  @override
  void initState() {
    super.initState();
    _likeCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300));
    _likeScale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
        parent: _likeCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _likeCtrl.dispose();
    super.dispose();
  }

  String _timeAgo(String dateStr) {
    final d = DateTime.parse(dateStr).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _anonColor(String id) {
    final colors = [
      const Color(0xFF6C63FF),
      const Color(0xFF00B8A3),
      const Color(0xFFFF375F),
      const Color(0xFFFFB800),
      const Color(0xFF2E7D32)
    ];
    return colors[id.codeUnitAt(0) % colors.length];
  }

  String _anonEmoji(String id) {
    final emojis = [
      '🦊', '🐼', '🦁', '🐯', '🐸',
      '🦄', '🐲', '🤖', '👾', '🎭'
    ];
    return emojis[id.codeUnitAt(0) % emojis.length];
  }


  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final postId = post['id'].toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final likes = post['likes'] ?? 0;
    final imageUrl = post['image_url'] as String?;
    final visibility = post['visibility']?.toString() ?? 'public';

    final isAnonymous = post['is_anonymous'] as bool? ?? true;
    final posterName = post['poster_name']?.toString() ?? '';
    final posterEmoji = post['poster_emoji']?.toString() ?? '';
    final posterCollegeName=post['college_name']?.toString() ?? '';
    final showIdentity = !isAnonymous && posterName.isNotEmpty;

    // ── Banner rank for this poster ──
    final bannerRankInt = (post['poster_banner_rank'] as num?)?.toInt() ?? 0;
    final posterBannerRank = BannerRank.values[bannerRankInt.clamp(0, BannerRank.values.length - 1)];

    final displayName = showIdentity
        ? posterName
        : (widget.isOwn ? 'You (Anonymous)' : 'Anonymous');
    final displayEmoji =
        (showIdentity && posterEmoji.isNotEmpty)
            ? posterEmoji
            : _anonEmoji(postId);
    final avatarBg = showIdentity
        ? Theme.of(context).primaryColor
        : _anonColor(postId);

    // accent color per visibility
    final accentColor = visibility == 'branch'
        ? const Color(0xFFFBBF24)
        : visibility == 'college'
          ? const Color(0xFF34D399)
          : visibility == 'friends'
            ? const Color(0xFFE879F9)
            : const Color(0xFF818CF8);

    // Banner rank drives card border and glow
    final hasBanner = showIdentity && posterBannerRank != BannerRank.none;
    final bannerMeta = hasBanner ? kBanners[posterBannerRank] : null;
    final cardBorderColor = hasBanner
        ? bannerMeta!.primary.withOpacity(0.55)
        : widget.isOwn
          ? accentColor.withOpacity(0.5)
          : AppColors.border(context);
    final cardGlow = hasBanner
        ? bannerMeta!.primary.withOpacity(0.18)
        : widget.isOwn
          ? accentColor.withOpacity(0.08)
          : Colors.black.withOpacity(0.25);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cardBorderColor,
          width: hasBanner ? 1.5 : (widget.isOwn ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: cardGlow,
            blurRadius: hasBanner ? 24 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner strip ──
          PostBannerHeader(
            bannerRank: showIdentity ? posterBannerRank : BannerRank.none,
            fallbackAccent: accentColor,
          ),

          // ── Header row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Avatar
              GestureDetector(
                onTap: showIdentity && post['user_id'] != null
                  ? () => widget.onProfileTap?.call(post['user_id'].toString())
                  : null,
                child: Stack(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [avatarBg.withValues(alpha: 0.45), avatarBg.withValues(alpha: 0.15)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: avatarBg.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Center(child: Text(displayEmoji,
                      style: TextStyle(fontSize: 23))),
                  ),
                  if (!isAnonymous)
                    Positioned(right: 0, bottom: 0,
                      child: Container(
                        width: 13, height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface(context), width: 2),
                        ))),
                ]),
              ),
              const SizedBox(width: 10),
              // Name + meta
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: showIdentity && post['user_id'] != null
                      ? () => widget.onProfileTap?.call(post['user_id'].toString())
                      : null,
                    child: Text(displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: showIdentity || widget.isOwn
                          ? accentColor
                          : AppColors.text(context),
                        letterSpacing: -0.2,
                      )),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (posterCollegeName.isNotEmpty && (showIdentity || visibility == 'public'))
                      Flexible(child: Text(posterCollegeName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ))),
                    const Spacer(),
                    Text(_timeAgo(post['created_at'].toString()),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w400,
                      )),
                  ]),
                ],
              )),
              // More menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz,
                  color: AppColors.textSecondary(context), size: 20),
                color: AppColors.surface(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'report') widget.onReport();
                  if (val == 'delete') widget.onDelete();
                },
                itemBuilder: (_) => [
                  if (!widget.isOwn)
                    PopupMenuItem(
                      value: 'report',
                      child: Row(children: [
                        Icon(widget.isReported ? Icons.flag : Icons.flag_outlined,
                          color: widget.isReported ? Colors.grey : Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Text(widget.isReported ? 'Reported ✓' : 'Report',
                          style: TextStyle(
                            color: widget.isReported ? Colors.grey : Colors.orange,
                            fontWeight: FontWeight.w600)),
                      ])),
                  if (widget.isOwn)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                      ])),
                ],
              ),
            ]),
          ),

          // ── Content ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(post['content']?.toString() ?? '',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.text(context),
                height: 1.55,
                letterSpacing: 0.1,
              )),
          ),

          // ── Image ──
          if (imageUrl != null && imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GestureDetector(
                onTap: () => openImageViewer(
                  context,
                  imageUrl: imageUrl,
                  heroTag: 'buzz_img_$postId',
                  posterName: showIdentity ? posterName : 'Anonymous',
                  timeAgo: _timeAgo(post['created_at'].toString()),
                ),
                child: Hero(
                  tag: 'buzz_img_$postId',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(imageUrl,
                      width: double.infinity, height: 220,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(height: 220,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant(context),
                            borderRadius: BorderRadius.circular(14)),
                          child: Center(child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                            color: accentColor, strokeWidth: 2)));
                      },
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                ),
              )),

          // ── Poll ──
          PollWidget(
            key: ValueKey('poll_${widget.post['id']}'),
            postId: widget.post['id'].toString(),
            myUserId: Supabase.instance.client.auth.currentUser?.id,
          ),

          // ── Action bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Row(children: [
              // Like
              GestureDetector(
                onTap: () { _likeCtrl.forward(from: 0); widget.onLike(); },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ScaleTransition(scale: _likeScale,
                    child: Icon(
                      widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: widget.isLiked ? Colors.redAccent : AppColors.textSecondary(context),
                      size: 21,
                    )),
                  const SizedBox(width: 5),
                  Text('$likes',
                    style: TextStyle(
                      color: widget.isLiked ? Colors.redAccent : AppColors.textSecondary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                ]),
              ),
              const SizedBox(width: 22),
              // Comment
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => CommentsSheet(
                    postId: widget.post['id'].toString(),
                    postOwnerId: widget.post['user_id'].toString(),
                    isAnonymousPost: widget.post['is_anonymous'] as bool? ?? false,
                    postContent: widget.post['content']?.toString() ?? '',
                  )),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.textSecondary(context), size: 20),
                  const SizedBox(width: 5),
                  Text('${widget.post['comment_count'] ?? 0}',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── BADGE (legacy) ──
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)));
}


// ── EMPTY STATE ──
class _EmptyState extends StatelessWidget {
  final VoidCallback onPost;
  final String feedLabel;
  const _EmptyState({required this.onPost, required this.feedLabel});

  @override
  Widget build(BuildContext context) {
    final isFriends = feedLabel == 'Friends';
    return Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF818CF8), Color(0xFFE879F9)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(
            color: const Color(0xFF818CF8).withOpacity(0.3),
            blurRadius: 24, offset: const Offset(0, 8))]),
        child: Center(child: Text(
          isFriends ? '👥' : '🫙',
          style: TextStyle(fontSize: 40)))),
      const SizedBox(height: 20),
      Text(isFriends ? 'no friend posts yet' : 'nothing here yet',
        style: TextStyle(
          color: AppColors.text(context),
          fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      const SizedBox(height: 6),
      Text(
        isFriends
          ? 'when friends post to Friends only, it shows here'
          : 'be the first to buzz in $feedLabel',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center),
      const SizedBox(height: 24),
      if (!isFriends)
      GestureDetector(
        onTap: onPost,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE879F9), Color(0xFF818CF8)]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
              color: const Color(0xFF818CF8).withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))]),
          child: Text('drop a buzz',
            style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900,
              fontSize: 14, letterSpacing: 0.5)))),
    ]));
  }
}

// ── NEW POST SHEET ──
class _NewPostSheet extends StatefulWidget {
  final String posterName,
      posterEmoji,
      posterBranch,
      posterStudentId,
      collegeName,
      branchName;
    final String defaultVisibility; 
  final PostModerationService moderationService;
  final Future<void> Function(String content, XFile? image,
      bool isAnonymous, String visibility, PollData? poll) onPost;

  const _NewPostSheet(
      {required this.posterName,
      required this.posterEmoji,
      required this.posterBranch,
      required this.posterStudentId,
      required this.collegeName,
      required this.branchName,
      this.defaultVisibility = 'public',
      required this.moderationService,
      required this.onPost});

  @override
  State<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends State<_NewPostSheet> {
  final _ctrl = TextEditingController();
  XFile? _imageFile;
  Uint8List? _imageBytes;
  bool _isPosting = false;
  bool _isAnonymous = true;
  String _visibility = 'public';
  String? _moderationWarning; // client-side warning banner
  PollData? _pollData;
  int get _charsLeft => 300 - _ctrl.text.length;

  @override
  void initState() {
    super.initState();
    _visibility = widget.defaultVisibility;              // ADD THIS LINE
  // also force non-anonymous if friends
  if (_visibility == 'friends') _isAnonymous = false;
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  // ── Real-time client-side moderation warning as user types ──
  void _onTextChanged() {
    setState(() {}); // rebuild for char counter
    if (_ctrl.text.trim().length > 10) {
      final result =
          widget.moderationService.quickCheck(_ctrl.text);
      setState(() {
        _moderationWarning = result.allowed ? null : result.reason;
      });
    } else {
      setState(() => _moderationWarning = null);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1080);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageFile = picked;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty || _isPosting) return;
    // Block if client-side warning is active
    if (_moderationWarning != null) return;
    setState(() => _isPosting = true);
    try {
      await widget.onPost(
          _ctrl.text, _imageFile, _isAnonymous, _visibility, _pollData);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // bg handled by AppColors
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceVar = AppColors.surfaceVariant(context);
    final primary = Theme.of(context).primaryColor;
    final isOverLimit = _charsLeft < 0;
    final canPost = _ctrl.text.trim().isNotEmpty &&
        !isOverLimit &&
        !_isPosting &&
        _moderationWarning == null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
          child: SingleChildScrollView(
              child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Center(child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
                        borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),

                    // ── IDENTITY TOGGLE ──
                    GestureDetector(
                      onTap: () {
                        if (_visibility == 'friends') return; // no anon in friends
                        HapticFeedback.lightImpact();
                        setState(() => _isAnonymous = !_isAnonymous);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: _isAnonymous ? null : LinearGradient(
                            colors: [
                              const Color(0xFF818CF8).withOpacity(0.1),
                              const Color(0xFFE879F9).withOpacity(0.1),
                            ]),
                          color: _isAnonymous ? AppColors.surfaceVariant(context) : null,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _isAnonymous
                              ? AppColors.border(context)
                              : const Color(0xFF818CF8).withOpacity(0.4),
                            width: 1.5)),
                        child: Row(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(colors: [
                                (_isAnonymous ? Colors.white : const Color(0xFF818CF8)).withOpacity(0.15),
                                (_isAnonymous ? Colors.white : const Color(0xFF818CF8)).withOpacity(0.05),
                              ]),
                              shape: BoxShape.circle),
                            child: Center(child: Text(
                              _isAnonymous ? '🎭' : widget.posterEmoji,
                              style: TextStyle(fontSize: 22)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isAnonymous ? 'Anonymous' : widget.posterName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14,
                                  color: _isAnonymous
                                    ? AppColors.text(context)
                                    : const Color(0xFF818CF8),
                                  letterSpacing: -0.3)),
                              const SizedBox(height: 2),
                              Text(
                                _isAnonymous
                                  ? "nobody knows it's you"
                                  : 'posting as yourself - visible to all',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(context))),
                            ])),
                          // Toggle pill
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (_visibility == 'friends') return;
                              HapticFeedback.lightImpact();
                              setState(() => _isAnonymous = !_isAnonymous);
                            },
                            child: Container(
                              width: 46, height: 26,
                              decoration: BoxDecoration(
                                gradient: _isAnonymous
                                  ? null
                                  : const LinearGradient(
                                      colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
                                color: _isAnonymous
                                  ? AppColors.surfaceVariant(context)
                                  : null,
                                borderRadius: BorderRadius.circular(13)),
                              child: Stack(children: [
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  left: _isAnonymous ? 3.0 : 23.0,
                                  top: 3.0,
                                  child: Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.text(context),
                                      shape: BoxShape.circle)))
                              ]))),
                        ])),
                    ),
                    const SizedBox(height: 10),

                    // ── VISIBILITY PICKER ──
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                      Text('Post to:',
                          style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                              fontWeight: FontWeight.w600)),
                      _VisChip(
                          label: '🌍 Public',
                          value: 'public',
                          selected: _visibility == 'public',
                          onTap: () => setState(
                              () => _visibility = 'public')),
                      _VisChip(
                          label: '👥 Friends',
                          value: 'friends',
                          selected: _visibility == 'friends',
                          onTap: () => setState(() {
                            _visibility = 'friends';
                            _isAnonymous = false; // friends posts must be identified
                          })),
                      _VisChip(
                          label:
                              '🏫 ${widget.collegeName.isNotEmpty ? widget.collegeName.split(' ').first : "College"}',
                          value: 'college',
                          selected: _visibility == 'college',
                          enabled: widget.collegeName.isNotEmpty,
                          onTap: () => setState(
                              () => _visibility = 'college')),
                      _VisChip(
                          label:
                              '🎓 ${widget.branchName.isNotEmpty ? widget.branchName.split(' ').first : "Branch"}',
                          value: 'branch',
                          selected: _visibility == 'branch',
                          enabled: widget.branchName.isNotEmpty,
                          onTap: () => setState(
                              () => _visibility = 'branch')),
                    ]),
                    if (_visibility == 'friends')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          Text('🔒', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          Text('Friends posts are always identified — no anonymous',
                            style: TextStyle(
                              color: const Color(0xFFE879F9),
                              fontSize: 11, fontWeight: FontWeight.w600)),
                        ])),
                    const SizedBox(height: 10),

                    // ── TEXT FIELD ──
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.border(context), width: 1.5)),
                      child: TextField(
                        controller: _ctrl,
                        maxLines: 5,
                        maxLength: 300,
                        style: TextStyle(
                          color: AppColors.text(context), fontSize: 15, height: 1.6),
                        decoration: InputDecoration(
                          hintText: "what's on your mind?",
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 14, fontStyle: FontStyle.italic),
                          filled: false,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          counterStyle: TextStyle(
                            color: isOverLimit
                              ? Colors.red
                              : AppColors.textSecondary(context),
                            fontSize: 11)))),

                    // ── IMAGE PREVIEW ──
                    if (_imageBytes != null) ...[
                      const SizedBox(height: 8),
                      Stack(children: [
                        ClipRRect(
                            borderRadius:
                                BorderRadius.circular(12),
                            child: Image.memory(_imageBytes!,
                                height: 100,
                                width: double.infinity,
                                fit: BoxFit.cover)),
                        Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                                onTap: () => setState(() {
                                      _imageFile = null;
                                      _imageBytes = null;
                                    }),
                                child: Container(
                                    padding:
                                        const EdgeInsets.all(4),
                                    decoration:
                                        BoxDecoration(
                                            color: Colors.black54,
                                            shape:
                                                BoxShape.circle),
                                    child: Icon(
                                        Icons.close,
                                        color: AppColors.text(context),
                                        size: 14)))),
                      ]),
                    ],

                    // ── MODERATION WARNING BANNER ──
                    if (_moderationWarning != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    Colors.red.withOpacity(0.3))),
                        child: Row(children: [
                          Text('⚠️',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            _moderationWarning!,
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          )),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // ── POLL CREATOR ──
                    PollCreator(
                      onChange: (poll) => setState(() => _pollData = poll),
                    ),
                    const SizedBox(height: 10),

                    // ── BOTTOM ROW ──
                    Row(children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border(context))),
                          child: Icon(Icons.image_outlined,
                            color: AppColors.textSecondary(context), size: 20))),
                      const SizedBox(width: 10),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isOverLimit ? Colors.red : AppColors.textSecondary(context),
                          fontWeight: FontWeight.w800, fontSize: 12),
                        child: Text('$_charsLeft')),
                      const Spacer(),
                      GestureDetector(
                          onTap: canPost ? _submit : null,
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 13),
                              decoration: BoxDecoration(
                                gradient: canPost ? const LinearGradient(
                                  colors: [Color(0xFFE879F9), Color(0xFF818CF8)],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                                ) : null,
                                color: canPost ? null : AppColors.surfaceVariant(context),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: canPost
                                  ? [BoxShadow(
                                      color: const Color(0xFF818CF8).withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6))]
                                  : null),
                              child: _isPosting
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                                : Text('drop it *',
                                    style: TextStyle(
                                      color: AppColors.text(context),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 0.3)))),
                    ]),
                  ])))));
  }
}

// ── VIS CHIP ──
class _VisChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _VisChip(
      {required this.label,
      required this.value,
      required this.selected,
      required this.onTap,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: selected
                    ? primary.withOpacity(0.15)
                    : AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color:
                        selected ? primary : Colors.transparent)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: !enabled
                        ? AppColors.textSecondary(context)
                            .withOpacity(0.3)
                        : selected
                            ? primary
                            : AppColors.textSecondary(
                                context)))));
  }
}

// ══════════════════════════════════════════════
// 📢 ANNOUNCEMENT POPUP
// ══════════════════════════════════════════════
class _AnnouncementPopup extends StatefulWidget {
  final String title, message;
  const _AnnouncementPopup(
      {required this.title, required this.message});
  @override
  State<_AnnouncementPopup> createState() =>
      _AnnouncementPopupState();
}

class _AnnouncementPopupState extends State<_AnnouncementPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500));
    _scale =
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _playBuzzSound();
  }

  void _playBuzzSound() {
    try {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 150),
          () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 300),
          () => HapticFeedback.heavyImpact());
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _fade,
        child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ScaleTransition(
                scale: _scale,
                child: Container(
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVariant(context),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                            color: const Color(0xFF6C63FF)
                                .withOpacity(0.6),
                            width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF6C63FF)
                                  .withOpacity(0.4),
                              blurRadius: 40,
                              spreadRadius: 4),
                        ]),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 20, horizontal: 20),
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF6C63FF),
                                        Color(0xFF3B37C8)
                                      ],
                                      begin: Alignment.topLeft,
                                      end:
                                          Alignment.bottomRight),
                                  borderRadius:
                                      BorderRadius.vertical(
                                          top: Radius.circular(
                                              26))),
                              child: Column(children: [
                                Text('📢',
                                    style:
                                        TextStyle(fontSize: 40)),
                                const SizedBox(height: 8),
                                Text('ANNOUNCEMENT',
                                    style: TextStyle(
                                        color: AppColors.textHint(context),
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w800,
                                        letterSpacing: 2)),
                                const SizedBox(height: 6),
                                Text(widget.title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.text(context),
                                        fontSize: 20,
                                        fontWeight:
                                            FontWeight.w900)),
                              ])),
                          Padding(
                              padding:
                                  const EdgeInsets.all(20),
                              child: Text(widget.message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                      height: 1.6))),
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                      20, 0, 20, 20),
                              child: GestureDetector(
                                  onTap: () =>
                                      Navigator.pop(context),
                                  child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets
                                          .symmetric(
                                          vertical: 14),
                                      decoration: BoxDecoration(
                                          gradient:
                                              const LinearGradient(
                                                  colors: [
                                                Color(0xFF6C63FF),
                                                Color(0xFF3B37C8)
                                              ]),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                                color: const Color(
                                                        0xFF6C63FF)
                                                    .withOpacity(
                                                        0.4),
                                                blurRadius: 12)
                                          ]),
                                      child: Center(
                                          child: Text(
                                              'Got it! 👍',
                                              style: TextStyle(
                                                  color: Colors
                                                      .white,
                                                  fontWeight:
                                                      FontWeight
                                                          .w800,
                                                  fontSize:
                                                      15)))))),
                        ])))));
  }
}