import 'dart:convert';

import 'package:http/http.dart' as http;

/// City search using the free [Open-Meteo Geocoding API](https://open-meteo.com/en/docs/geocoding-api)
/// (no API key; use fairly and cache/debounce in the UI).
abstract final class GeocodingService {
  static Future<List<GeocodeSuggestion>> searchCities(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      return [];
    }
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '10',
      'language': 'en',
      'format': 'json',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      return [];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return [];
    }
    final raw = decoded['results'];
    if (raw is! List<dynamic>) {
      return [];
    }
    final out = <GeocodeSuggestion>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final name = item['name'] as String?;
      final lat = item['latitude'];
      final lng = item['longitude'];
      if (name == null || lat is! num || lng is! num) {
        continue;
      }
      final admin1 = item['admin1'] as String?;
      final country = item['country'] as String?;
      final countryCode = item['country_code'] as String?;
      final subtitle = [
        if (admin1 != null && admin1.isNotEmpty) admin1,
        if (country != null && country.isNotEmpty) country,
        if (countryCode != null && countryCode.isNotEmpty) countryCode,
      ].join(', ');
      out.add(
        GeocodeSuggestion(
          label: subtitle.isEmpty ? name : '$name · $subtitle',
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
        ),
      );
    }
    return out;
  }
}

class GeocodeSuggestion {
  const GeocodeSuggestion({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}
