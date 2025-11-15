import 'dart:io';
import 'dart:typed_data';

/// Manages download state using bitfield format with header/CRC for robustness.
/// Each bit represents one segment (0 = not downloaded, 1 = downloaded).
class BitfieldStateManager {
  final String stateFilePath;
  
  // Bitfield header structure:
  // - Magic number (4 bytes): 0x4D335538 = "M3U8" in hex
  // - Version (2 bytes): format version for compatibility
  // - Segment count (4 bytes): total number of segments
  // - CRC32 (4 bytes): checksum for data integrity
  // - Bitfield data (variable): segment completion bits
  
  static const int _magicNumber = 0x4D335538; // "M3U8"
  static const int _currentVersion = 1;
  static const int _headerSize = 14; // 4 + 2 + 4 + 4 = 14 bytes
  
  BitfieldStateManager(this.stateFilePath);
  
  /// Calculate CRC32 checksum for data integrity
  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
  
  /// Save state to file with header and CRC, using atomic write pattern
  Future<void> save(Uint8List bitfield, int segmentCount) async {
    final tempPath = '$stateFilePath.tmp';
    
    // Create header
    final header = ByteData(_headerSize);
    header.setUint32(0, _magicNumber, Endian.big);
    header.setUint16(4, _currentVersion, Endian.big);
    header.setUint32(6, segmentCount, Endian.big);
    
    // Calculate CRC for bitfield data
    final crc = _crc32(bitfield);
    header.setUint32(10, crc, Endian.big);
    
    // Combine header and bitfield
    final totalSize = _headerSize + bitfield.length;
    final fileData = Uint8List(totalSize);
    fileData.setRange(0, _headerSize, header.buffer.asUint8List());
    fileData.setRange(_headerSize, totalSize, bitfield);
    
    // Atomic write: write to temp, flush, sync, then rename
    final tempFile = File(tempPath);
    final raf = await tempFile.open(mode: FileMode.write);
    try {
      await raf.writeFrom(fileData);
      await raf.flush();
      await raf.close();
      
      // Sync to disk (platform-specific)
      if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        // On Unix-like systems, fsync is available via close()
        // The close() above should handle it, but we can try sync if available
        try {
          await raf.flush(); // Already closed, but this was done above
        } catch (e) {
          // Ignore if not supported
        }
      }
      
      // Atomic rename
      await tempFile.rename(stateFilePath);
    } catch (e) {
      // Clean up temp file on error
      try {
        await raf.close();
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }
  
  /// Load state from file, validating header and CRC
  Future<BitfieldLoadResult?> load() async {
    final file = File(stateFilePath);
    
    if (!await file.exists()) {
      return null;
    }
    
    try {
      final data = await file.readAsBytes();
      
      if (data.length < _headerSize) {
        print('⚠️ Bitfield file too small, possibly corrupted');
        return null;
      }
      
      // Read header
      final header = ByteData.sublistView(data, 0, _headerSize);
      final magic = header.getUint32(0, Endian.big);
      final version = header.getUint16(4, Endian.big);
      final segmentCount = header.getUint32(6, Endian.big);
      final storedCrc = header.getUint32(10, Endian.big);
      
      // Validate magic number
      if (magic != _magicNumber) {
        print('⚠️ Invalid bitfield magic number, file may be corrupted');
        return null;
      }
      
      // Check version compatibility (forward compatible: accept same or lower version)
      if (version > _currentVersion) {
        print('⚠️ Bitfield version $version is newer than supported $_currentVersion');
        return null;
      }
      
      // Extract bitfield data
      final bitfield = Uint8List.sublistView(data, _headerSize);
      
      // Calculate and validate CRC
      final calculatedCrc = _crc32(bitfield);
      if (calculatedCrc != storedCrc) {
        print('⚠️ Bitfield CRC mismatch: stored=$storedCrc, calculated=$calculatedCrc');
        print('⚠️ State file corrupted, will start fresh');
        return null;
      }
      
      return BitfieldLoadResult(
        bitfield: bitfield,
        segmentCount: segmentCount,
        version: version,
      );
    } catch (e) {
      print('⚠️ Error loading bitfield state: $e');
      return null;
    }
  }
  
  /// Check if a segment is downloaded (bit is set)
  static bool isSegmentDownloaded(Uint8List bitfield, int segmentIndex) {
    if (segmentIndex < 0) return false;
    final byteIndex = segmentIndex ~/ 8;
    if (byteIndex >= bitfield.length) return false;
    final bitIndex = 7 - (segmentIndex % 8); // MSB first
    return (bitfield[byteIndex] & (1 << bitIndex)) != 0;
  }
  
  /// Mark a segment as downloaded (set bit)
  static void markSegmentDownloaded(Uint8List bitfield, int segmentIndex) {
    if (segmentIndex < 0) return;
    final byteIndex = segmentIndex ~/ 8;
    if (byteIndex >= bitfield.length) return;
    final bitIndex = 7 - (segmentIndex % 8); // MSB first
    bitfield[byteIndex] |= (1 << bitIndex);
  }
  
  /// Count completed segments
  static int countCompleted(Uint8List bitfield) {
    int count = 0;
    for (int i = 0; i < bitfield.length; i++) {
      final byte = bitfield[i];
      // Count set bits in byte
      for (int j = 0; j < 8; j++) {
        if ((byte & (1 << (7 - j))) != 0) {
          count++;
        }
      }
    }
    return count;
  }
  
  /// Create a new bitfield for given segment count
  static Uint8List createBitfield(int segmentCount) {
    // Calculate bytes needed: ceil(segmentCount / 8)
    final byteCount = (segmentCount + 7) ~/ 8;
    return Uint8List(byteCount);
  }
  
  /// Delete state file (for cleanup or restart)
  Future<void> delete() async {
    final file = File(stateFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    // Also clean up temp file if it exists
    final tempFile = File('$stateFilePath.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}

/// Result of loading bitfield state
class BitfieldLoadResult {
  final Uint8List bitfield;
  final int segmentCount;
  final int version;
  
  BitfieldLoadResult({
    required this.bitfield,
    required this.segmentCount,
    required this.version,
  });
}

