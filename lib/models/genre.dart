class Genre {
  final String genre;
  final String icon;
  final String text;
  bool active;

  Genre({
    required this.genre,
    required this.icon,
    required this.text,
    required this.active,
  });

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      genre: json['genre'] as String,
      icon: json['icon'] as String? ?? 'pop',
      text: json['text'] as String,
      active: json['active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'genre': genre,
      'icon': icon,
      'text': text,
      'active': active,
    };
  }
}
