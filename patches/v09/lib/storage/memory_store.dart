import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/models.dart';
import '../personality/personality_state.dart';

class MemoryStore {
  dynamic _db;

  Future<void> open() async {
    dynamic factory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      factory = mobile.databaseFactory;
    }

    final base = await factory.getDatabasesPath() as String;
    final path = p.join(base, 'dream_pulse_v03.db');
    _db = await factory.openDatabase(
      path,
      options: mobile.OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE knowledge(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              topic TEXT NOT NULL,
              rule TEXT NOT NULL,
              confidence REAL NOT NULL,
              tests INTEGER NOT NULL,
              successes INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              UNIQUE(topic, rule)
            )
          ''');
          await db.execute('''
            CREATE TABLE pulse_log(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              pulse INTEGER NOT NULL,
              phase TEXT NOT NULL,
              core_mass REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await _ensurePersonalityTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _ensurePersonalityTable(db);
          }
        },
      ),
    );
  }

  static Future<void> _ensurePersonalityTable(dynamic db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS personality_state(
        slot INTEGER PRIMARY KEY,
        mood TEXT NOT NULL,
        energy REAL NOT NULL,
        warmth REAL NOT NULL,
        sass REAL NOT NULL,
        playfulness REAL NOT NULL,
        tenderness REAL NOT NULL,
        patience REAL NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> purgeSimulatedKnowledge() async {
    final db = _db;
    if (db == null) return 0;
    return await db.delete(
      'knowledge',
      where: 'rule = ?',
      whereArgs: const ['validated-method'],
    ) as int;
  }

  Future<void> saveKnowledge(KnowledgeUnit unit) async {
    final db = _db;
    if (db == null) throw StateError('MemoryStore is not open');
    await db.insert(
      'knowledge',
      {
        'topic': unit.topic,
        'rule': unit.rule,
        'confidence': unit.confidence,
        'tests': unit.tests,
        'successes': unit.successes,
        'created_at': (unit.createdAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: mobile.ConflictAlgorithm.replace,
    );
  }

  Future<List<KnowledgeUnit>> loadKnowledge() async {
    final db = _db;
    if (db == null) throw StateError('MemoryStore is not open');
    final List<Map<String, Object?>> rows =
        await db.query('knowledge', orderBy: 'confidence DESC');
    return rows
        .map((row) => KnowledgeUnit(
              topic: row['topic'] as String,
              rule: row['rule'] as String,
              confidence: (row['confidence'] as num).toDouble(),
              tests: row['tests'] as int,
              successes: row['successes'] as int,
              createdAt: DateTime.tryParse(row['created_at'] as String),
            ))
        .toList();
  }

  Future<PersonalityState?> loadPersonalityState() async {
    final db = _db;
    if (db == null) throw StateError('MemoryStore is not open');
    final List<Map<String, Object?>> rows = await db.query(
      'personality_state',
      where: 'slot = ?',
      whereArgs: const [1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PersonalityState.fromDbMap(rows.first);
  }

  Future<void> savePersonalityState(PersonalityState state) async {
    final db = _db;
    if (db == null) throw StateError('MemoryStore is not open');
    await db.insert(
      'personality_state',
      state.toDbMap(),
      conflictAlgorithm: mobile.ConflictAlgorithm.replace,
    );
  }

  Future<void> logPulse(int pulse, String phase, double coreMass) async {
    final db = _db;
    if (db == null) return;
    await db.insert('pulse_log', {
      'pulse': pulse,
      'phase': phase,
      'core_mass': coreMass,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) await db.close();
    _db = null;
  }
}
