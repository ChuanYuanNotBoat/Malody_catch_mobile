import 'package:flutter_test/flutter_test.dart';
import 'package:malody_catch_mobile/core/beat_time_mapper.dart';
import 'package:malody_catch_mobile/core/native_core.dart';

void main() {
  test(
    'beat/ms mapping is monotonic and near-reversible across bpm segments',
    () {
      final mapper = BeatTimeMapper.fromChart(
        bpms: const <CoreBpmSnapshot>[
          CoreBpmSnapshot(
            beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
            bpm: 120,
          ),
          CoreBpmSnapshot(
            beat: CoreBeat(measure: 4, numerator: 0, denominator: 1),
            bpm: 240,
          ),
          CoreBpmSnapshot(
            beat: CoreBeat(measure: 8, numerator: 0, denominator: 1),
            bpm: 90,
          ),
        ],
        offsetMs: 150,
      );

      const beats = <double>[0, 1.25, 3.75, 4, 6.5, 8.0, 10.25];
      var lastMs = -1 << 30;
      for (final beat in beats) {
        final ms = mapper.beatToMs(beat);
        expect(ms >= lastMs, isTrue);
        lastMs = ms;

        final roundtripBeat = mapper.msToBeat(ms);
        expect((roundtripBeat - beat).abs(), lessThan(0.02));
      }
    },
  );

  test('mapping handles negative offset and keeps beat progression', () {
    final mapper = BeatTimeMapper.fromChart(
      bpms: const <CoreBpmSnapshot>[
        CoreBpmSnapshot(
          beat: CoreBeat(measure: 0, numerator: 0, denominator: 1),
          bpm: 180,
        ),
      ],
      offsetMs: -500,
    );

    final ms0 = mapper.beatToMs(0.0);
    final ms1 = mapper.beatToMs(2.0);
    expect(ms0, lessThan(0));
    expect(ms1, greaterThan(ms0));
    expect(mapper.msToBeat(ms1), closeTo(2.0, 0.02));
  });
}
