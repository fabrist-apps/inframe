import 'package:conflux/result.dart';
import 'package:conflux/src/moment/moment_error.dart';
import 'package:conflux/src/moment/moment_parts.dart';
import 'package:conflux/src/moment/time_zone.dart';

/// Finds every instant with these local fields, without normalizing a gap.
///
/// The field encoding is a calendar coordinate, not a UTC occurrence. Checking
/// the offset at each candidate rejects obsolete offsets and retains overlaps.
List<int> localCandidates(int wallMicros, TimeZone zone) {
  final offsets = switch (zone) {
    FixedTimeZone(:final offset) => {offset},
    NamedTimeZone(:final location) =>
      location.zones.isEmpty ? {Duration.zero} : location.zones.map((z) => z.offset).toSet(),
  };
  return [
    for (final offset in offsets)
      if (zoneOffset(zone, wallMicros - offset.inMicroseconds) == offset)
        wallMicros - offset.inMicroseconds,
  ]..sort();
}

/// Resolves validated local fields; callers validate both final instant ranges.
Result<int, MomentError> resolveLocal(MomentParts parts, TimeZone zone, Disambiguation policy) {
  final error = validateParts(parts);
  if (error != null) return Failure(error);
  final wallMicros = encodeParts(parts).microsecondsSinceEpoch;
  final candidates = localCandidates(wallMicros, zone);
  if (candidates.length == 1) return Success(candidates.single);
  if (candidates.length > 1) {
    if (policy == Disambiguation.reject) {
      return const Failure(
        MomentError(MomentErrorKind.ambiguousLocalTime, 'Local fields identify multiple instants.'),
      );
    }
    return Success(policy == Disambiguation.later ? candidates.last : candidates.first);
  }
  if (policy == Disambiguation.reject) {
    return const Failure(
      MomentError(MomentErrorKind.nonexistentLocalTime, 'Local fields lie in a timezone gap.'),
    );
  }

  if (zone case NamedTimeZone(:final location)) {
    // A forward transition omits [transition + before, transition + after).
    // Use its real offsets rather than assuming a one-hour DST transition.
    for (final transition in location.transitionAt) {
      final before = location.timeZone(transition - 1).offset.inMicroseconds;
      final after = location.timeZone(transition).offset.inMicroseconds;
      if (after <= before) continue;
      final transitionMicros = transition * Duration.microsecondsPerMillisecond;
      if (wallMicros >= transitionMicros + before && wallMicros < transitionMicros + after) {
        return Success(wallMicros - (policy == Disambiguation.earlier ? after : before));
      }
    }
  }
  // A valid location must either represent the fields or contain their gap.
  // Malformed timezone data is a defect, not a user validation failure.
  throw StateError('Timezone data contains no candidate or transition for the local fields.');
}
