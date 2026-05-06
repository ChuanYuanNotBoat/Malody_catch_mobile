import 'dart:async';

import 'package:malody_catch_mobile/io/chart_audio.dart';

class FakeChartAudio implements ChartAudioPort {
  FakeChartAudio({
    this.failOnLoad = false,
    this.failOnPlay = false,
    this.failOnPause = false,
    this.failOnSeek = false,
    this.failOnSetRate = false,
    Duration? initialDuration,
  }) : _duration = initialDuration ?? const Duration(minutes: 2);

  final bool failOnLoad;
  final bool failOnPlay;
  final bool failOnPause;
  final bool failOnSeek;
  final bool failOnSetRate;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<ChartAudioPlaybackState> _stateController =
      StreamController<ChartAudioPlaybackState>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration;
  ChartAudioPlaybackState _state = ChartAudioPlaybackState.idle;
  String? loadedPath;
  double currentRate = 1.0;
  bool disposed = false;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<ChartAudioPlaybackState> get stateStream => _stateController.stream;

  @override
  Duration get currentPosition => _position;

  @override
  Duration? get currentDuration => _duration;

  @override
  ChartAudioPlaybackState get currentState => _state;

  @override
  Future<void> loadFile(String path) async {
    if (failOnLoad) {
      throw StateError('load_failed');
    }
    loadedPath = path;
    _state = ChartAudioPlaybackState.ready;
    _position = Duration.zero;
    _stateController.add(_state);
    _durationController.add(_duration);
    _positionController.add(_position);
  }

  @override
  Future<void> play() async {
    if (failOnPlay) {
      throw StateError('play_failed');
    }
    _state = ChartAudioPlaybackState.playing;
    _stateController.add(_state);
  }

  @override
  Future<void> pause() async {
    if (failOnPause) {
      throw StateError('pause_failed');
    }
    _state = ChartAudioPlaybackState.paused;
    _stateController.add(_state);
  }

  @override
  Future<void> seek(Duration position) async {
    if (failOnSeek) {
      throw StateError('seek_failed');
    }
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setRate(double rate) async {
    if (failOnSetRate) {
      throw StateError('set_rate_failed');
    }
    currentRate = rate;
  }

  @override
  Future<void> stop() async {
    _position = Duration.zero;
    _positionController.add(_position);
    _state = ChartAudioPlaybackState.paused;
    _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _positionController.close();
    await _durationController.close();
    await _stateController.close();
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  void emitDuration(Duration? duration) {
    _duration = duration;
    _durationController.add(duration);
  }

  void emitState(ChartAudioPlaybackState state) {
    _state = state;
    _stateController.add(state);
  }
}
