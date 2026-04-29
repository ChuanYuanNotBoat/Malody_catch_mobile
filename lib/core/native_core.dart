import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeCoreException implements Exception {
  const NativeCoreException(this.message);

  final String message;

  @override
  String toString() => 'NativeCoreException: $message';
}

final class MceSession extends Opaque {}

final class MceBeat extends Struct {
  @Int32()
  external int measure;

  @Int32()
  external int numerator;

  @Int32()
  external int denominator;
}

final class MceNoteSnapshot extends Struct {
  @Array(128)
  external Array<Char> id;

  @Int32()
  external int type;

  external MceBeat beat;

  external MceBeat endBeat;

  @Int32()
  external int x;

  @Array(260)
  external Array<Char> sound;

  @Int32()
  external int volume;

  @Int32()
  external int offsetMs;
}

class CoreBeat {
  const CoreBeat({
    required this.measure,
    required this.numerator,
    required this.denominator,
  });

  final int measure;
  final int numerator;
  final int denominator;
}

class CoreNoteSnapshot {
  const CoreNoteSnapshot({
    required this.id,
    required this.type,
    required this.beat,
    required this.endBeat,
    required this.x,
    required this.sound,
    required this.volume,
    required this.offsetMs,
  });

  final String id;
  final int type;
  final CoreBeat beat;
  final CoreBeat endBeat;
  final int x;
  final String sound;
  final int volume;
  final int offsetMs;
}

typedef _SessionCreateNative = Pointer<MceSession> Function();
typedef _SessionCreateDart = Pointer<MceSession> Function();

typedef _SessionDestroyNative = Void Function(Pointer<MceSession>);
typedef _SessionDestroyDart = void Function(Pointer<MceSession>);

typedef _LastErrorNative = Pointer<Char> Function(Pointer<MceSession>);
typedef _LastErrorDart = Pointer<Char> Function(Pointer<MceSession>);

typedef _NoteCountNative = Int32 Function(Pointer<MceSession>);
typedef _NoteCountDart = int Function(Pointer<MceSession>);

typedef _GetNoteSnapshotNative =
    Int32 Function(Pointer<MceSession>, Int32, Pointer<MceNoteSnapshot>);
typedef _GetNoteSnapshotDart =
    int Function(Pointer<MceSession>, int, Pointer<MceNoteSnapshot>);

typedef _AddNormalNoteNative =
    Int32 Function(Pointer<MceSession>, Pointer<Char>, MceBeat, Int32);
typedef _AddNormalNoteDart =
    int Function(Pointer<MceSession>, Pointer<Char>, MceBeat, int);

typedef _RemoveNoteNative = Int32 Function(Pointer<MceSession>, Pointer<Char>);
typedef _RemoveNoteDart = int Function(Pointer<MceSession>, Pointer<Char>);

typedef _SessionBoolNative = Int32 Function(Pointer<MceSession>);
typedef _SessionBoolDart = int Function(Pointer<MceSession>);

DynamicLibrary openMalodyCatchCoreLibrary() {
  final String name;
  if (Platform.isAndroid) {
    name = 'libmalody_catch_core_ffi.so';
  } else if (Platform.isWindows) {
    name = 'malody_catch_core_ffi.dll';
  } else if (Platform.isMacOS) {
    name = 'libmalody_catch_core_ffi.dylib';
  } else if (Platform.isLinux) {
    name = 'libmalody_catch_core_ffi.so';
  } else {
    throw const NativeCoreException(
      'Unsupported platform for Malody Catch core FFI.',
    );
  }

  try {
    return DynamicLibrary.open(name);
  } catch (e) {
    throw NativeCoreException('Failed to load native library "$name": $e');
  }
}

class NativeCoreBindings {
  NativeCoreBindings(DynamicLibrary library)
    : _create = library
          .lookupFunction<_SessionCreateNative, _SessionCreateDart>(
            'mce_session_create',
          ),
      _destroy = library
          .lookupFunction<_SessionDestroyNative, _SessionDestroyDart>(
            'mce_session_destroy',
          ),
      _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'mce_session_last_error',
      ),
      _noteCount = library.lookupFunction<_NoteCountNative, _NoteCountDart>(
        'mce_session_note_count',
      ),
      _getNoteSnapshot = library
          .lookupFunction<_GetNoteSnapshotNative, _GetNoteSnapshotDart>(
            'mce_session_get_note_snapshot',
          ),
      _addNormalNote = library
          .lookupFunction<_AddNormalNoteNative, _AddNormalNoteDart>(
            'mce_session_add_normal_note',
          ),
      _removeNoteById = library
          .lookupFunction<_RemoveNoteNative, _RemoveNoteDart>(
            'mce_session_remove_note_by_id',
          ),
      _canUndo = library.lookupFunction<_SessionBoolNative, _SessionBoolDart>(
        'mce_session_can_undo',
      ),
      _canRedo = library.lookupFunction<_SessionBoolNative, _SessionBoolDart>(
        'mce_session_can_redo',
      ),
      _undo = library.lookupFunction<_SessionBoolNative, _SessionBoolDart>(
        'mce_session_undo',
      ),
      _redo = library.lookupFunction<_SessionBoolNative, _SessionBoolDart>(
        'mce_session_redo',
      );

  factory NativeCoreBindings.open() {
    try {
      return NativeCoreBindings(openMalodyCatchCoreLibrary());
    } catch (e) {
      if (e is NativeCoreException) {
        rethrow;
      }
      throw NativeCoreException('Failed to create NativeCoreBindings: $e');
    }
  }

  final _SessionCreateDart _create;
  final _SessionDestroyDart _destroy;
  final _LastErrorDart _lastError;
  final _NoteCountDart _noteCount;
  final _GetNoteSnapshotDart _getNoteSnapshot;
  final _AddNormalNoteDart _addNormalNote;
  final _RemoveNoteDart _removeNoteById;
  final _SessionBoolDart _canUndo;
  final _SessionBoolDart _canRedo;
  final _SessionBoolDart _undo;
  final _SessionBoolDart _redo;

  Pointer<MceSession> createSession() => _create();

  void destroySession(Pointer<MceSession> session) {
    if (session != nullptr) {
      _destroy(session);
    }
  }

  String lastError(Pointer<MceSession> session) {
    final pointer = _lastError(session);
    if (pointer == nullptr) {
      return '';
    }
    return pointer.cast<Utf8>().toDartString();
  }

  int noteCount(Pointer<MceSession> session) => _noteCount(session);

  CoreNoteSnapshot? noteSnapshot(Pointer<MceSession> session, int index) {
    final out = calloc<MceNoteSnapshot>();
    try {
      final ok = _getNoteSnapshot(session, index, out);
      if (ok == 0) {
        return null;
      }
      final note = out.ref;
      return CoreNoteSnapshot(
        id: _charArrayToString(note.id, 128),
        type: note.type,
        beat: CoreBeat(
          measure: note.beat.measure,
          numerator: note.beat.numerator,
          denominator: note.beat.denominator,
        ),
        endBeat: CoreBeat(
          measure: note.endBeat.measure,
          numerator: note.endBeat.numerator,
          denominator: note.endBeat.denominator,
        ),
        x: note.x,
        sound: _charArrayToString(note.sound, 260),
        volume: note.volume,
        offsetMs: note.offsetMs,
      );
    } finally {
      calloc.free(out);
    }
  }

  bool addNormalNote({
    required Pointer<MceSession> session,
    required String id,
    required int measure,
    required int numerator,
    required int denominator,
    required int x,
  }) {
    final idPointer = id.toNativeUtf8().cast<Char>();
    final beat = calloc<MceBeat>();
    try {
      beat.ref
        ..measure = measure
        ..numerator = numerator
        ..denominator = denominator;
      return _addNormalNote(session, idPointer, beat.ref, x) != 0;
    } finally {
      calloc.free(beat);
      calloc.free(idPointer);
    }
  }

  bool removeNoteById(Pointer<MceSession> session, String id) {
    final idPointer = id.toNativeUtf8().cast<Char>();
    try {
      return _removeNoteById(session, idPointer) != 0;
    } finally {
      calloc.free(idPointer);
    }
  }

  bool canUndo(Pointer<MceSession> session) => _canUndo(session) != 0;
  bool canRedo(Pointer<MceSession> session) => _canRedo(session) != 0;
  bool undo(Pointer<MceSession> session) => _undo(session) != 0;
  bool redo(Pointer<MceSession> session) => _redo(session) != 0;
}

String _charArrayToString(Array<Char> chars, int capacity) {
  final bytes = <int>[];
  for (var i = 0; i < capacity; i++) {
    final value = chars[i];
    if (value == 0) {
      break;
    }
    bytes.add(value);
  }
  return String.fromCharCodes(bytes);
}
