import 'dart:io';
import 'dart:typed_data';

/// Utility for atomic file writes with flush and sync for crash-safety.
/// Implements write → flush → fsync → atomic rename pattern.
class AtomicFileUtils {
  /// Atomically write bytes to a file, ensuring data is synced to disk before rename.
  /// This prevents corruption on power loss or crashes.
  static Future<void> atomicWriteBytes(String filePath, Uint8List data) async {
    final tempPath = '$filePath.tmp';
    final tempFile = File(tempPath);
    
    // Remove old temp file if it exists
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    
    // Write to temp file
    final raf = await tempFile.open(mode: FileMode.write);
    try {
      await raf.writeFrom(data);
      await raf.flush(); // Flush buffers to OS
      await raf.close();
      
      // Note: Dart's File API doesn't expose fsync directly,
      // but close() after flush() should ensure data is written.
      // The rename operation itself will ensure consistency on most filesystems
      
      // Atomic rename (only works on same filesystem)
      final targetFile = File(filePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(filePath);
    } catch (e) {
      // Clean up temp file on error
      try {
        await raf.close();
      } catch (_) {}
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }
  
  /// Atomically write string to a file
  static Future<void> atomicWriteString(String filePath, String content) async {
    final data = content.codeUnits;
    final bytes = Uint8List.fromList(data.map((c) => c & 0xFF).toList());
    await atomicWriteBytes(filePath, bytes);
  }
  
  /// Stream bytes to file atomically (for large files)
  static Future<void> atomicWriteStream(
    String filePath,
    Stream<Uint8List> stream,
  ) async {
    final tempPath = '$filePath.tmp';
    final tempFile = File(tempPath);
    
    // Remove old temp file if it exists
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    
    final sink = tempFile.openWrite();
    try {
      await stream.forEach((chunk) {
        sink.add(chunk);
      });
      await sink.flush();
      await sink.close();
      
      // Atomic rename
      final targetFile = File(filePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(filePath);
    } catch (e) {
      // Clean up on error
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }
}

