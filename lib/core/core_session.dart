import 'dart:ffi';

import 'native_core.dart';

class CoreStartupReport {
  const CoreStartupReport({
    required this.libraryLoaded,
    required this.sessionCreated,
    this.errorMessage,
  });

  final bool libraryLoaded;
  final bool sessionCreated;
  final String? errorMessage;

  bool get success => libraryLoaded && sessionCreated && errorMessage == null;
}

abstract class CoreSessionPort {
  bool get isClosed;
  String get lastError;
  int get noteCount;
  CoreNoteSnapshot? noteSnapshot(int index);
  bool addNormalNote({
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
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
      final session = bindings.createSession();
      if (session == nullptr) {
        return const CoreStartupReport(
          libraryLoaded: true,
          sessionCreated: false,
          errorMessage: 'mce_session_create returned null.',
        );
      }
      bindings.destroySession(session);
      return const CoreStartupReport(libraryLoaded: true, sessionCreated: true);
    } catch (e) {
      return CoreStartupReport(
        libraryLoaded: false,
        sessionCreated: false,
        errorMessage: e.toString(),
      );
    }
  }

  static CoreSession open() {
    final bindings = NativeCoreBindings.open();
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
  int get noteCount => _bindings.noteCount(_session);

  @override
  CoreNoteSnapshot? noteSnapshot(int index) {
    _ensureOpen();
    return _bindings.noteSnapshot(_session, index);
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
