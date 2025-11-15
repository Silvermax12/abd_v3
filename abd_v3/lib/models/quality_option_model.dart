class QualityOption {
  final String src;
  final String resolution;
  final String audio;
  final String fansub;
  final String label;

  QualityOption({
    required this.src,
    required this.resolution,
    required this.audio,
    required this.fansub,
    required this.label,
  });

  factory QualityOption.fromJson(Map<String, dynamic> json) {
    return QualityOption(
      src: json['src'] as String? ?? '',
      resolution: json['resolution'] as String? ?? '',
      audio: json['audio'] as String? ?? '',
      fansub: json['fansub'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'src': src,
      'resolution': resolution,
      'audio': audio,
      'fansub': fansub,
      'label': label,
    };
  }

  @override
  String toString() {
    return label.isNotEmpty ? label : '$resolution - $audio ($fansub)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QualityOption &&
        other.src == src &&
        other.resolution == resolution &&
        other.audio == audio &&
        other.fansub == fansub;
  }

  @override
  int get hashCode {
    return src.hashCode ^
        resolution.hashCode ^
        audio.hashCode ^
        fansub.hashCode;
  }
}

