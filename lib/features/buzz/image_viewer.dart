import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ══════════════════════════════════════════════
// 🖼️ IMAGE VIEWER
// Fullscreen viewer with pinch-zoom, swipe-dismiss,
// hero animation, download + share
// ══════════════════════════════════════════════

/// Call this to open the image viewer
void openImageViewer(
  BuildContext context, {
  required String imageUrl,
  String heroTag = 'buzz_image',
  String? posterName,
  String? timeAgo,
}) {
  HapticFeedback.lightImpact();
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => _ImageViewerScreen(
        imageUrl: imageUrl,
        heroTag: heroTag,
        posterName: posterName,
        timeAgo: timeAgo,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
    ),
  );
}

// ── Main Viewer Screen ──
class _ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String heroTag;
  final String? posterName;
  final String? timeAgo;

  const _ImageViewerScreen({
    required this.imageUrl,
    required this.heroTag,
    this.posterName,
    this.timeAgo,
  });

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformCtrl = TransformationController();
  late AnimationController _bgCtrl;
  late Animation<double> _bgOpacity;

  // drag-to-dismiss state
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isZoomed = false;
  bool _showUI = true;



  double get _dismissProgress =>
      (_dragOffset.dy.abs() / 220).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _bgOpacity = _bgCtrl.drive(CurveTween(curve: Curves.easeOut));

    _transformCtrl.addListener(() {
      final scale = _transformCtrl.value.getMaxScaleOnAxis();
      final zoomed = scale > 1.05;
      if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _transformCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta;
      _showUI = _dismissProgress < 0.1;
    });
    _bgCtrl.value = 1.0 - _dismissProgress * 0.8;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dismissProgress > 0.35 ||
        details.velocity.pixelsPerSecond.dy.abs() > 600) {
      _dismiss();
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _isDragging = false;
        _showUI = true;
      });
      _bgCtrl.animateTo(1.0);
    }
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _bgOpacity,
        builder: (_, __) => Stack(children: [
          // ── Background ──
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showUI = !_showUI),
              child: Container(
                color: Colors.black.withOpacity(_bgOpacity.value * 0.95),
              ),
            ),
          ),

          // ── Image with pan/zoom/drag ──
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: AnimatedContainer(
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                transform: Matrix4.translationValues(
                  _dragOffset.dx * 0.3,
                  _dragOffset.dy,
                  0,
                )..scale(1.0 - _dismissProgress * 0.12),
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 0.8,
                  maxScale: 5.0,
                  clipBehavior: Clip.none,
                  child: Center(
                    child: Hero(
                      tag: widget.heroTag,
                      child: Image.network(
                        widget.imageUrl,
                        fit: BoxFit.contain,
                        width: size.width,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return SizedBox(
                            width: size.width,
                            height: size.height * 0.6,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                              progress.expectedTotalBytes!
                                          : null,
                                      color: const Color(0xFF818CF8),
                                      strokeWidth: 2,
                                      backgroundColor:
                                          Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'loading...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          width: size.width,
                          height: 300,
                          color: Colors.white.withOpacity(0.05),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined,
                                    color: Colors.white.withOpacity(0.3),
                                    size: 48),
                                const SizedBox(height: 12),
                                Text('failed to load',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.3),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar (close + poster info) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: _showUI ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 24,
              ),
              child: Row(children: [
                // Close button
                GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15)),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                // Poster info
                if (widget.posterName != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.posterName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (widget.timeAgo != null)
                          Text(
                            widget.timeAgo!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
              ]),
            ),
          ),


          // ── Swipe hint ──
          if (!_isZoomed && _dismissProgress == 0 && _showUI)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: 0.3,
                  duration: const Duration(milliseconds: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 18),
                      Text(
                        'swipe to close',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}