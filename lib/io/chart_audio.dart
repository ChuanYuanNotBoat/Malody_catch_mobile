import 'dart:async';

import 'package:just_audio/just_audio.dart';

enum ChartAudioPlaybackState {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
}

abstract class ChartAudioPort {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<ChartAudioPlaybackState> get stateStream;

  Duration get currentPosition;
  Duration? get currentDuration;
  ChartAudioPlaybackState get currentState;

  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> stop();
  Future<void> dispose();
}

class ChartAudio implements ChartAudioPort {
  ChartAudio() : _player = AudioPlayer();

  final AudioPlayer _player;
  Stream<ChartAudioPlaybackState>? _stateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<ChartAudioPlaybackState> get stateStream {
    _stateStream ??= _player.playerStateStream
        .map(_mapPlayerState)
        .distinct()
        .asBroadcastStream();
    return _stateStream!;
  }

  @override
  Duration get currentPosition => _player.position;

  @override
  Duration? get currentDuration => _player.duration;

  @override
  ChartAudioPlaybackState get currentState =>
      _mapPlayerState(_player.playerState);

  @override
  Future<void> loadFile(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setRate(double rate) async {
    await _player.setSpeed(rate);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }

  ChartAudioPlaybackState _mapPlayerState(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        return ChartAudioPlaybackState.idle;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return ChartAudioPlaybackState.loading;
      case ProcessingState.ready:
        if (state.playing) {
          return ChartAudioPlaybackState.playing;
        }
        return ChartAudioPlaybackState.paused;
      case ProcessingState.completed:
        return ChartAudioPlaybackState.completed;
    }
  }
}
