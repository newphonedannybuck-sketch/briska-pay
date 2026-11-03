import 'models.dart';

List<String> recentSiteNameSuggestions(
  Iterable<WorkEntry> entries, {
  String query = '',
  int limit = 8,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final seen = <String>{};
  final suggestions = <String>[];
  final sorted = entries.toList()..sort((a, b) => b.date.compareTo(a.date));

  for (final entry in sorted) {
    if (entry.entryType != 'WorkDay') continue;
    final name = entry.siteName.trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (!seen.add(key)) continue;
    if (normalizedQuery.isNotEmpty && !key.contains(normalizedQuery)) continue;
    suggestions.add(name);
    if (suggestions.length >= limit) break;
  }

  return suggestions;
}
