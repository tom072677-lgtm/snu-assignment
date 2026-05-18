enum VenueCategory { restaurant, cafe, convenience }

enum VenueType { snuco, static, instagram }

class TimeRange {
  final String open;  // "HH:mm"
  final String close; // "HH:mm"
  const TimeRange({required this.open, required this.close});

  factory TimeRange.fromJson(Map<String, dynamic> j) =>
      TimeRange(open: j['open'] as String, close: j['close'] as String);
}

class DayHours {
  final List<TimeRange> ranges;
  final bool closed;
  const DayHours({required this.ranges, required this.closed});

  factory DayHours.fromJson(Map<String, dynamic> j) => DayHours(
        closed: j['closed'] as bool,
        ranges: (j['ranges'] as List)
            .map((e) => TimeRange.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VenueHours {
  final DayHours weekday;
  final DayHours saturday;
  final DayHours sunday;
  const VenueHours(
      {required this.weekday,
      required this.saturday,
      required this.sunday});

  factory VenueHours.fromJson(Map<String, dynamic> j) => VenueHours(
        weekday: DayHours.fromJson(j['weekday'] as Map<String, dynamic>),
        saturday: DayHours.fromJson(j['saturday'] as Map<String, dynamic>),
        sunday: DayHours.fromJson(j['sunday'] as Map<String, dynamic>),
      );
}

class Venue {
  final String id;
  final String name;
  final VenueCategory category;
  final VenueType type;
  final String building;
  final String address;
  final double lat;
  final double lng;
  final String? phone;
  final List<String> tags;
  final VenueHours hours;
  final String? snucoName;        // maps to SNUCO scraper name
  final String? instagramHandle;  // for instagram-type venues

  // Set externally after SNUCO fetch
  String? snucoBreakfast;
  String? snucoLunch;
  String? snucoDinner;

  // Set externally after Instagram fetch
  List<Map<String, dynamic>>? instagramPosts;

  Venue({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.building,
    required this.address,
    required this.lat,
    required this.lng,
    required this.hours,
    this.phone,
    this.tags = const [],
    this.snucoName,
    this.instagramHandle,
    this.snucoBreakfast,
    this.snucoLunch,
    this.snucoDinner,
    this.instagramPosts,
  });

  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
        id: j['id'] as String,
        name: j['name'] as String,
        category: VenueCategory.values.byName(j['category'] as String),
        type: VenueType.values.byName(j['type'] as String),
        building: j['building'] as String,
        address: j['address'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        phone: j['phone'] as String?,
        tags: (j['tags'] as List).map((e) => e as String).toList(),
        hours: VenueHours.fromJson(j['hours'] as Map<String, dynamic>),
        snucoName: j['snucoName'] as String?,
        instagramHandle: j['instagramHandle'] as String?,
      );

  /// Returns true if venue is open at [t] in KST (UTC+9).
  bool isOpenAt(DateTime t) {
    // Convert to KST
    final kst = t.toUtc().add(const Duration(hours: 9));
    final weekday = kst.weekday; // Mon=1 … Sun=7

    final DayHours day;
    if (weekday == 6) {
      day = hours.saturday;
    } else if (weekday == 7) {
      day = hours.sunday;
    } else {
      day = hours.weekday;
    }

    if (day.closed || day.ranges.isEmpty) return false;

    final now = kst.hour * 60 + kst.minute;
    for (final r in day.ranges) {
      final open = _toMinutes(r.open);
      var close = _toMinutes(r.close);
      // Handle overnight (e.g. 08:00–02:00)
      if (close < open) close += 24 * 60;
      if (now >= open && now < close) return true;
    }
    return false;
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Today's lunch 1-line preview (SNUCO only)
  String? get lunchPreview => snucoLunch?.split('\n').first;
}
