import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeCoreException implements Exception {
  const NativeCoreException(this.message);

  final String message;

  @override
  String toString() => 'NativeCoreException: $message';
}

const int mceMinimumAbiVersion = 2;

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

final class MceChartSummary extends Struct {
  @Int32()
  external int noteCount;

  @Int32()
  external int bpmCount;

  @Uint64()
  external int revision;

  @Int32()
  external int canUndo;

  @Int32()
  external int canRedo;

  @Array(128)
  external Array<Char> title;

  @Array(128)
  external Array<Char> artist;

  @Array(64)
  external Array<Char> difficulty;
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

class CoreChartSummary {
  const CoreChartSummary({
    required this.noteCount,
    required this.bpmCount,
    required this.revision,
    required this.canUndo,
    required this.canRedo,
    required this.title,
    required this.artist,
    required this.difficulty,
  });

  final int noteCount;
  final int bpmCount;
  final int revision;
  final bool canUndo;
  final bool canRedo;
  final String title;
  final String artist;
  final String difficulty;
}

typedef _SessionCreateNative = Pointer<MceSession> Function();
typedef _SessionCreateDart = Pointer<MceSession> Function();

typedef _SessionDestroyNative = Void Function(Pointer<MceSession>);
typedef _SessionDestroyDart = void Function(Pointer<MceSession>);

typedef _LastErrorNative = Pointer<Char> Function(Pointer<MceSession>);
typedef _LastErrorDart = Pointer<Char> Function(Pointer<MceSession>);

typedef _CoreVersionNative = Pointer<Char> Function();
typedef _CoreVersionDart = Pointer<Char> Function();

typedef _AbiVersionNative = Int32 Function();
typedef _AbiVersionDart = int Function();

typedef _LastErrorCodeNative = Int32 Function(Pointer<MceSession>);
typedef _LastErrorCodeDart = int Function(Pointer<MceSession>);

typedef _ErrorCodeNameNative = Pointer<Char> Function(Int32);
typedef _ErrorCodeNameDart = Pointer<Char> Function(int);

typedef _NoteCountNative = Int32 Function(Pointer<MceSession>);
typedef _NoteCountDart = int Function(Pointer<MceSession>);

typedef _ChartRevisionNative = Uint64 Function(Pointer<MceSession>);
typedef _ChartRevisionDart = int Function(Pointer<MceSession>);

typedef _GetNoteSnapshotNative =
    Int32 Function(Pointer<MceSession>, Int32, Pointer<MceNoteSnapshot>);
typedef _GetNoteSnapshotDart =
    int Function(Pointer<MceSession>, int, Pointer<MceNoteSnapshot>);

typedef _GetNoteSnapshotsNative =
    Int32 Function(Pointer<MceSession>, Int32, Int32, Pointer<MceNoteSnapshot>);
typedef _GetNoteSnapshotsDart =
    int Function(Pointer<MceSession>, int, int, Pointer<MceNoteSnapshot>);

typedef _GetChartSummaryNative =
    Int32 Function(Pointer<MceSession>, Pointer<MceChartSummary>);
typedef _GetChartSummaryDart =
    int Function(Pointer<MceSession>, Pointer<MceChartSummary>);

typedef _AddNormalNoteNative =
    Int32 Function(Pointer<MceSession>, Pointer<Char>, MceBeat, Int32);
typedef _AddNormalNoteDart =
    int Function(Pointer<MceSession>, Pointer<Char>, MceBeat, int);

typedef _AddRainNoteNative =
    Int32 Function(Pointer<MceSession>, Pointer<Char>, MceBeat, MceBeat, Int32);
typedef _AddRainNoteDart =
    int Function(Pointer<MceSession>, Pointer<Char>, MceBeat, MceBeat, int);

typedef _MoveRainNoteNative =
    Int32 Function(Pointer<MceSession>, Pointer<Char>, MceBeat, MceBeat, Int32);
typedef _MoveRainNoteDart =
    int Function(Pointer<MceSession>, Pointer<Char>, MceBeat, MceBeat, int);

typedef _AddSoundNoteNative =
    Int32 Function(
      Pointer<MceSession>,
      Pointer<Char>,
      MceBeat,
      Pointer<Char>,
      Int32,
      Int32,
    );
typedef _AddSoundNoteDart =
    int Function(
      Pointer<MceSession>,
      Pointer<Char>,
      MceBeat,
      Pointer<Char>,
      int,
      int,
    );

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
      _coreVersion = library
          .lookupFunction<_CoreVersionNative, _CoreVersionDart>(
            'mce_core_version',
          ),
      _abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'mce_ffi_abi_version',
      ),
      _lastErrorCode = library
          .lookupFunction<_LastErrorCodeNative, _LastErrorCodeDart>(
            'mce_session_last_error_code',
          ),
      _errorCodeName = library
          .lookupFunction<_ErrorCodeNameNative, _ErrorCodeNameDart>(
            'mce_error_code_name',
          ),
      _noteCount = library.lookupFunction<_NoteCountNative, _NoteCountDart>(
        'mce_session_note_count',
      ),
      _chartRevision = library
          .lookupFunction<_ChartRevisionNative, _ChartRevisionDart>(
            'mce_session_chart_revision',
          ),
      _getNoteSnapshot = library
          .lookupFunction<_GetNoteSnapshotNative, _GetNoteSnapshotDart>(
            'mce_session_get_note_snapshot',
          ),
      _getNoteSnapshots = library
          .lookupFunction<_GetNoteSnapshotsNative, _GetNoteSnapshotsDart>(
            'mce_session_get_note_snapshots',
          ),
      _getChartSummary = library
          .lookupFunction<_GetChartSummaryNative, _GetChartSummaryDart>(
            'mce_session_get_chart_summary',
          ),
      _addNormalNote = library
          .lookupFunction<_AddNormalNoteNative, _AddNormalNoteDart>(
            'mce_session_add_normal_note',
          ),
      _addRainNote = library
          .lookupFunction<_AddRainNoteNative, _AddRainNoteDart>(
            'mce_session_add_rain_note',
          ),
      _moveRainNote = library
          .lookupFunction<_MoveRainNoteNative, _MoveRainNoteDart>(
            'mce_session_move_rain_note',
          ),
      _addSoundNote = library
          .lookupFunction<_AddSoundNoteNative, _AddSoundNoteDart>(
            'mce_session_add_sound_note',
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
  final _CoreVersionDart _coreVersion;
  final _AbiVersionDart _abiVersion;
  final _LastErrorCodeDart _lastErrorCode;
  final _ErrorCodeNameDart _errorCodeName;
  final _NoteCountDart _noteCount;
  final _ChartRevisionDart _chartRevision;
  final _GetNoteSnapshotDart _getNoteSnapshot;
  final _GetNoteSnapshotsDart _getNoteSnapshots;
  final _GetChartSummaryDart _getChartSummary;
  final _AddNormalNoteDart _addNormalNote;
  final _AddRainNoteDart _addRainNote;
  final _MoveRainNoteDart _moveRainNote;
  final _AddSoundNoteDart _addSoundNote;
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

  String coreVersion() => _coreVersion().cast<Utf8>().toDartString();

  int abiVersion() => _abiVersion();

  int lastErrorCode(Pointer<MceSession> session) => _lastErrorCode(session);

  String errorCodeName(int code) {
    final pointer = _errorCodeName(code);
    if (pointer == nullptr) {
      return 'unknown';
    }
    return pointer.cast<Utf8>().toDartString();
  }

  String lastError(Pointer<MceSession> session) {
    final pointer = _lastError(session);
    if (pointer == nullptr) {
      return '';
    }
    return pointer.cast<Utf8>().toDartString();
  }

  String lastErrorDetails(Pointer<MceSession> session) {
    final code = lastErrorCode(session);
    final name = errorCodeName(code);
    final message = lastError(session);
    if (message.isEmpty) {
      return '$name($code)';
    }
    return '$name($code): $message';
  }

  int noteCount(Pointer<MceSession> session) => _noteCount(session);

  int chartRevision(Pointer<MceSession> session) => _chartRevision(session);

  CoreNoteSnapshot? noteSnapshot(Pointer<MceSession> session, int index) {
    final out = calloc<MceNoteSnapshot>();
    try {
      final ok = _getNoteSnapshot(session, index, out);
      if (ok == 0) {
        return null;
      }
      return _toCoreNote(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  List<CoreNoteSnapshot> noteSnapshots({
    required Pointer<MceSession> session,
    required int startIndex,
    required int maxCount,
  }) {
    if (maxCount <= 0) {
      return const <CoreNoteSnapshot>[];
    }
    final out = calloc<MceNoteSnapshot>(maxCount);
    try {
      final filled = _getNoteSnapshots(session, startIndex, maxCount, out);
      if (filled <= 0) {
        return const <CoreNoteSnapshot>[];
      }
      final list = <CoreNoteSnapshot>[];
      for (var i = 0; i < filled; i++) {
        list.add(_toCoreNote(out[i]));
      }
      return list;
    } finally {
      calloc.free(out);
    }
  }

  CoreChartSummary? chartSummary(Pointer<MceSession> session) {
    final out = calloc<MceChartSummary>();
    try {
      final ok = _getChartSummary(session, out);
      if (ok == 0) {
        return null;
      }
      final data = out.ref;
      return CoreChartSummary(
        noteCount: data.noteCount,
        bpmCount: data.bpmCount,
        revision: data.revision,
        canUndo: data.canUndo != 0,
        canRedo: data.canRedo != 0,
        title: _charArrayToString(data.title, 128),
        artist: _charArrayToString(data.artist, 128),
        difficulty: _charArrayToString(data.difficulty, 64),
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

  bool addRainNote({
    required Pointer<MceSession> session,
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    final idPointer = id.toNativeUtf8().cast<Char>();
    final beatPtr = calloc<MceBeat>();
    final endBeatPtr = calloc<MceBeat>();
    try {
      beatPtr.ref
        ..measure = beat.measure
        ..numerator = beat.numerator
        ..denominator = beat.denominator;
      endBeatPtr.ref
        ..measure = endBeat.measure
        ..numerator = endBeat.numerator
        ..denominator = endBeat.denominator;
      return _addRainNote(session, idPointer, beatPtr.ref, endBeatPtr.ref, x) !=
          0;
    } finally {
      calloc.free(endBeatPtr);
      calloc.free(beatPtr);
      calloc.free(idPointer);
    }
  }

  bool moveRainNote({
    required Pointer<MceSession> session,
    required String id,
    required CoreBeat beat,
    required CoreBeat endBeat,
    required int x,
  }) {
    final idPointer = id.toNativeUtf8().cast<Char>();
    final beatPtr = calloc<MceBeat>();
    final endBeatPtr = calloc<MceBeat>();
    try {
      beatPtr.ref
        ..measure = beat.measure
        ..numerator = beat.numerator
        ..denominator = beat.denominator;
      endBeatPtr.ref
        ..measure = endBeat.measure
        ..numerator = endBeat.numerator
        ..denominator = endBeat.denominator;
      return _moveRainNote(
            session,
            idPointer,
            beatPtr.ref,
            endBeatPtr.ref,
            x,
          ) !=
          0;
    } finally {
      calloc.free(endBeatPtr);
      calloc.free(beatPtr);
      calloc.free(idPointer);
    }
  }

  bool addSoundNote({
    required Pointer<MceSession> session,
    required String id,
    required CoreBeat beat,
    required String sound,
    required int volume,
    required int offsetMs,
  }) {
    final idPointer = id.toNativeUtf8().cast<Char>();
    final soundPtr = sound.toNativeUtf8().cast<Char>();
    final beatPtr = calloc<MceBeat>();
    try {
      beatPtr.ref
        ..measure = beat.measure
        ..numerator = beat.numerator
        ..denominator = beat.denominator;
      return _addSoundNote(
            session,
            idPointer,
            beatPtr.ref,
            soundPtr,
            volume,
            offsetMs,
          ) !=
          0;
    } finally {
      calloc.free(beatPtr);
      calloc.free(soundPtr);
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

CoreNoteSnapshot _toCoreNote(MceNoteSnapshot note) {
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
