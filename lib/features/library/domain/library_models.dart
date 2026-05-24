class ReadingRoom {
  final String name;
  final int available;
  final int total;

  const ReadingRoom({
    required this.name,
    required this.available,
    required this.total,
  });

  factory ReadingRoom.fromJson(Map<String, dynamic> j) => ReadingRoom(
        name: j['name'] as String? ?? '',
        available: (j['available'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );

  double get occupancyRate => total > 0 ? (total - available) / total : 0;
  bool get isCrowded => occupancyRate > 0.8;
  bool get isAvailable => available > 0;
}

class LibrarySeats {
  final List<ReadingRoom> rooms;
  final DateTime? updatedAt;

  const LibrarySeats({required this.rooms, this.updatedAt});

  factory LibrarySeats.fromJson(Map<String, dynamic> j) => LibrarySeats(
        rooms: (j['rooms'] as List? ?? [])
            .map((e) => ReadingRoom.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: j['updatedAt'] != null
            ? DateTime.tryParse(j['updatedAt'] as String)
            : null,
      );
}
