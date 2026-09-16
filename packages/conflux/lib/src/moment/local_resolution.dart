import 'package:conflux/result.dart';
import 'package:conflux/src/moment/moment_error.dart';
import 'package:conflux/src/moment/moment_parts.dart';
import 'package:conflux/src/moment/time_zone.dart';

/// Internal resolution of local fields in an explicit zone.
extension TimeZoneLocalResolution on TimeZone {
  /// Distinct historical offsets in ascending order, including fixed zones.
  List<Duration> get candidateOffsets => (switch (this) {
    FixedTimeZone(:final offset) => {offset},
    NamedTimeZone(:final location) =>
      location.zones.isEmpty ? {Duration.zero} : location.zones.map((z) => z.offset).toSet(),
  }).toList()..sort();

  /// Enumerates real occurrences, skipping gaps and retaining every overlap.
  ///
  /// The wall encoding is a calendar coordinate, not a UTC occurrence. Checking
  /// the offset at each candidate rejects obsolete offsets. Supply one offset
  /// snapshot for a whole Cron search.
  Iterable<int> localCandidates(int wallMicros, List<Duration> offsets) sync* {
    for (final offset in offsets) {
      final candidate = wallMicros - offset.inMicroseconds;
      if (offsetAt(candidate) == offset) yield candidate;
    }
  }

  /// Validates and resolves local fields; callers validate final instant ranges.
  Result<int, MomentError> resolveLocal(MomentParts parts, Disambiguation policy) {
    final encoded = parts.encodeValidated();
    if (encoded case Failure(:final error)) return Failure(error);

    final wallMicros = (encoded as Success<int, MomentError>).value;
    final candidates = localCandidates(wallMicros, candidateOffsets).toList()..sort();
    if (candidates.length == 1) return Success(candidates.single);

    if (candidates.length > 1) {
      if (policy == Disambiguation.reject) {
        return const Failure(
          MomentError(
            MomentErrorKind.ambiguousLocalTime,
            'Local fields identify multiple instants.',
          ),
        );
      }

      return Success(policy == Disambiguation.later ? candidates.last : candidates.first);
    }

    if (policy == Disambiguation.reject) {
      return const Failure(
        MomentError(MomentErrorKind.nonexistentLocalTime, 'Local fields lie in a timezone gap.'),
      );
    }

    if (this case NamedTimeZone(:final location)) {
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
}
