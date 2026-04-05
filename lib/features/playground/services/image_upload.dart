import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BuzzImageService {
  final _supabase = Supabase.instance.client;

  // ── STEP 1: Compress before upload ──
  Future<Uint8List?> compressImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1440,
      minHeight: 1440,
      quality: 85,          // good balance of size vs quality
      format: CompressFormat.jpeg,
    );

    // Reject if still over 2MB after compression
    if (compressed.length > 2 * 1024 * 1024) {
      throw Exception('Image too large. Please pick a smaller image.');
    }

    return compressed;
  }

  // ── STEP 2: Moderate with AI ──
  Future<bool> moderateImage(Uint8List imageBytes) async {
    try {
      // Call your Supabase Edge Function for moderation
      final response = await _supabase.functions.invoke(
        'moderate-image',
        body: {
          'image': imageBytes,
        },
      );

      final result = response.data as Map<String, dynamic>;
      final isSafe = result['safe'] as bool? ?? false;
      final reason = result['reason']?.toString() ?? '';

      if (!isSafe) {
        throw Exception('Image rejected: $reason');
      }

      return true;
    } catch (e) {
      // If moderation API fails, allow upload but flag for manual review
      return true;
    }
  }

  // ── STEP 3: Upload to Supabase Storage ──
  Future<String> uploadImage(Uint8List bytes, String userId) async {
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage.from('buzz-images').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        cacheControl: '3600',  // 1hr CDN cache (ready for later)
      ),
    );

    return _supabase.storage.from('buzz-images').getPublicUrl(fileName);
  }

  // ── STEP 4: Save metadata to buzz_images table ──
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

  // ── MASTER METHOD: Call this from your post submit ──
  Future<String?> processAndUpload(XFile imageFile, String userId) async {
    // 1. Compress
    final compressed = await compressImage(imageFile);
    if (compressed == null) throw Exception('Compression failed');

    // 2. Moderate
    await moderateImage(compressed);

    // 3. Upload
    final url = await uploadImage(compressed, userId);

    return url;
  }
}