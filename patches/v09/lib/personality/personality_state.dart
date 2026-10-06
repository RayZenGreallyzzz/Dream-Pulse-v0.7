enum Mood {
  calm,
  warm,
  playful,
  cheeky,
  thoughtful,
  blue,
  energetic,
}

extension MoodLabels on Mood {
  String get label => switch (this) {
        Mood.calm => 'спокойная',
        Mood.warm => 'мягкая',
        Mood.playful => 'игривая',
        Mood.cheeky => 'дерзкая',
        Mood.thoughtful => 'задумчивая',
        Mood.blue => 'тихая',
        Mood.energetic => 'энергичная',
      };
}

Mood moodFromWire(String? raw) {
  for (final mood in Mood.values) {
    if (mood.name == raw) return mood;
  }
  return Mood.calm;
}

class PersonalityState {
  const PersonalityState({
    required this.mood,
    required this.energy,
    required this.warmth,
    required this.sass,
    required this.playfulness,
    required this.tenderness,
    required this.patience,
    required this.updatedAt,
  });

  final Mood mood;
  final double energy;
  final double warmth;
  final double sass;
  final double playfulness;
  final double tenderness;
  final double patience;
  final DateTime updatedAt;

  PersonalityState copyWith({
    Mood? mood,
    double? energy,
    double? warmth,
    double? sass,
    double? playfulness,
    double? tenderness,
    double? patience,
    DateTime? updatedAt,
  }) {
    return PersonalityState(
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      warmth: warmth ?? this.warmth,
      sass: sass ?? this.sass,
      playfulness: playfulness ?? this.playfulness,
      tenderness: tenderness ?? this.tenderness,
      patience: patience ?? this.patience,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap() => {
        'slot': 1,
        'mood': mood.name,
        'energy': energy,
        'warmth': warmth,
        'sass': sass,
        'playfulness': playfulness,
        'tenderness': tenderness,
        'patience': patience,
        'updated_at': updatedAt.toIso8601String(),
      };

  static PersonalityState fromDbMap(Map<String, Object?> row) {
    double readDouble(String key, double fallback) =>
        (row[key] as num?)?.toDouble() ?? fallback;

    return PersonalityState(
      mood: moodFromWire(row['mood']?.toString()),
      energy: readDouble('energy', 0.58),
      warmth: readDouble('warmth', 0.76),
      sass: readDouble('sass', 0.56),
      playfulness: readDouble('playfulness', 0.66),
      tenderness: readDouble('tenderness', 0.62),
      patience: readDouble('patience', 0.72),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
