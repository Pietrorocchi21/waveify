/// Small helpers to read loosely-typed API payloads safely.
library;

Map<String, dynamic>? asRecord(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  return null;
}

List<Object?> asArray(Object? value) {
  if (value is List) return value;
  return const [];
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return '$value';
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return '$value';
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round() ?? fallback;
  return fallback;
}

double asDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return fallback;
}

/// A non empty string, or null.
String? trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The first value found under a key, at any depth.
///
/// Port of `findFirst` in `src/shared/utils/json.ts`.
Object? findFirst(Object? node, String key) {
  if (node is Map) {
    for (final entry in node.entries) {
      if (entry.key == key) return entry.value;
    }
    for (final value in node.values) {
      final found = findFirst(value, key);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = findFirst(value, key);
      if (found != null) return found;
    }
  }
  return null;
}

/// Every value found under a key, at any depth.
///
/// Port of `collectByKey` in `src/shared/utils/json.ts`.
List<Object?> collectByKey(Object? node, String key) {
  final found = <Object?>[];
  void walk(Object? current) {
    if (current is Map) {
      for (final entry in current.entries) {
        if (entry.key == key) found.add(entry.value);
      }
      for (final value in current.values) {
        walk(value);
      }
    } else if (current is List) {
      for (final value in current) {
        walk(value);
      }
    }
  }

  walk(node);
  return found;
}

/// Reads a duration that may arrive as `durationMs` or `duration_ms`.
int asDurationMs(Map<String, dynamic>? source) {
  if (source == null) return 0;
  final direct = source['durationMs'] ?? source['duration_ms'];
  if (direct is num) return direct.round();
  if (direct is String) {
    final parsed = int.tryParse(direct) ?? double.tryParse(direct)?.round();
    if (parsed != null) return parsed;
  }
  return 0;
}
