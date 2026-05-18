class Restaurant {
  final String name;
  final String breakfast;
  final String lunch;
  final String dinner;

  const Restaurant({
    required this.name,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        name: json['name'] as String,
        breakfast: json['breakfast'] as String? ?? '',
        lunch: json['lunch'] as String? ?? '정보 없음',
        dinner: json['dinner'] as String? ?? '',
      );
}
