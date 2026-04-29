import 'dart:ffi';

import 'native_core.dart';

class CoreStartupReport {
  const CoreStartupReport({
    required this.libraryLoaded,
    required this.sessionCreated,
    required this.coreVersion,
    required this.abiVersion,
    required this.minimumAbiVersion,
    this.errorMessage,
  });

  final bool libraryLoaded;
  final bool sessionCreated;
  final String coreVersion;
  final int abiVersion;
  final int minimumAbiVersion;
  final String? errorMessage;

  bool get abiCompatible => abiVersion >= minimumAbiVersion;
  bool get success =>
      libraryLoaded && sessionCreated && abiCompatible && errorMessage == null;
}

abstract class CoreSessionPort {
  bool get isClosed;
  String get lastError;
  String get lastErrorDetails;
  int get lastErrorCode;
  String get lastErrorName;
  int get noteCount;
  int get chartRevision;
  CoreChartSummary? chartSummary();
  CoreNoteSnapshot? noteSnapshot(int index);
  List<CoreNoteSnapshot> noteSnapshots({
    required int startIndex,
    required int maxCount,
  });
  bool addNormalNote({
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  });
  bool addRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  });
  bool moveRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  });
  bool addSoundNote({
    required String id,
    required CoreBeat beat,
    required String sound,
    required int volume,
    required int offsetMs,
  });
  bool removeNoteById(String id);
  bool get canUndo;
  bool get canRedo;
  bool undo();
  bool redo();
  void close();
}

typedef CoreSessionFactory = CoreSessionPort Function();

class CoreSession implements CoreSessionPort {
  CoreSession._(this._bindings, this._session);

  final NativeCoreBindings _bindings;
  final Pointer<MceSession> _session;
  bool _closed = false;

  static CoreStartupReport startupSelfCheck() {
    try {
      final bindings = NativeCoreBindings.open();
      final abi = bindings.abiVersion();
      final coreVersion = bindings.coreVersion();
      if (abi < mceMinimumAbiVersion) {
        return CoreStartupReport(
          libraryLoaded: true,
          sessionCreated: false,
          coreVersion: coreVersion,
          abiVersion: abi,
          minimumAbiVersion: mceMinimumAbiVersion,
          errorMessage:
              'ABI mismatch: found $abi, requires >= $mceMinimumAbiVersion.',
        );
      }
      final session = bindings.createSession();
      if (session == nullptr) {
        return CoreStartupReport(
          libraryLoaded: true,
          sessionCreated: false,
          coreVersion: coreVersion,
          abiVersion: abi,
          minimumAbiVersion: mceMinimumAbiVersion,
          errorMessage: 'mce_session_create returned null.',
        );
      }
      bindings.destroySession(session);
      return CoreStartupReport(
        libraryLoaded: true,
        sessionCreated: true,
        coreVersion: coreVersion,
        abiVersion: abi,
        minimumAbiVersion: mceMinimumAbiVersion,
      );
    } catch (e) {
      return CoreStartupReport(
        libraryLoaded: false,
        sessionCreated: false,
        coreVersion: '',
        abiVersion: -1,
        minimumAbiVersion: mceMinimumAbiVersion,
        errorMessage: e.toString(),
      );
    }
  }

  static CoreSession open() {
    final bindings = NativeCoreBindings.open();
    final abi = bindings.abiVersion();
    if (abi < mceMinimumAbiVersion) {
      throw StateError(
        'Unsupported core ABI $abi, requires >= $mceMinimumAbiVersion.',
      );
    }
    final session = bindings.createSession();
    if (session == nullptr) {
      throw StateError('Failed to create native core session.');
    }
    return CoreSession._(bindings, session);
  }

  @override
  bool get isClosed => _closed;

  @override
  String get lastError => _bindings.lastError(_session);

  @override
  String get lastErrorDetails => _bindings.lastErrorDetails(_session);

  @override
  int get lastErrorCode => _bindings.lastErrorCode(_session);

  @override
  String get lastErrorName => _bindings.errorCodeName(lastErrorCode);

  @override
  int get noteCount => _bindings.noteCount(_session);

  @override
  int get chartRevision => _bindings.chartRevision(_session);

  @override
  CoreChartSummary? chartSummary() {
    _ensureOpen();
    return _bindings.chartSummary(_session);
  }

  @override
  CoreNoteSnapshot? noteSnapshot(int index) {
    _ensureOpen();
    return _bindings.noteSnapshot(_session, index);
  }

  @override
  List<CoreNoteSnapshot> noteSnapshots({
    required int startIndex,
    required int maxCount,
  }) {
    _ensureOpen();
    return _bindings.noteSnapshots(
      session: _session,
      startIndex: startIndex,
      maxCount: maxCount,
    );
  }

  @override
  bool addNormalNote({
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  }) {
    _ensureOpen();
    return _bindings.addNormalNote(
      session: _session,
      id: id,
      measure: measure,
      numerator: numerator,
      denominator: denominator,
      x: x,
    );
  }

  @override
  bool addRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    _ensureOpen();
    return _bindings.addRainNote(
      session: _session,
      id: id,
      beat: beat,
      endBeat: endBeat,
      x: x,
    );
  }

  @override
  bool moveRainNote({
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    _ensureOpen();
    return _bindings.moveRainNote(
      session: _session,
      id: id,
      beat: beat,
      endBeat: endBeat,
      x: x,
    );
  }

  @override
  bool addSoundNote({
    required String id,
    required CoreBeat beat,
    required String sound,
    required int volume,
    required int offsetMs,
  }) {
    _ensureOpen();
    return _bindings.addSoundNote(
      session: _session,
      id: id,
      beat: beat,
      sound: sound,
      volume: volume,
      offsetMs: offsetMs,
    );
  }

  @override
  bool removeNoteById(String id) {
    _ensureOpen();
    return _bindings.removeNoteById(_session, id);
  }

  @override
  bool get canUndo {
    _ensureOpen();
    return _bindings.canUndo(_session);
  }

  @override
  bool get canRedo {
    _ensureOpen();
    return _bindings.canRedo(_session);
  }

  @override
  bool undo() {
    _ensureOpen();
    return _bindings.undo(_session);
  }

  @override
  bool redo() {
    _ensureOpen();
    return _bindings.redo(_session);
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _bindings.destroySession(_session);
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('CoreSession is already closed.');
    }
  }
}
