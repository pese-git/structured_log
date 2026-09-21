import 'dart:async';

import 'package:drift/drift.dart';

import '../storage/database.dart';

/// What a live subscription needs to know about a project to decide whether an
/// entry of it may be shown: which group it belongs to and whether it is
/// blocked. Nothing else about a project is cached.
class ProjectStanding {
  final int groupId;
  final bool isBlocked;

  const ProjectStanding({required this.groupId, required this.isBlocked});
}

/// Remembers [ProjectStanding]s so that delivering a log entry to a
/// subscription does not cost a database read (`log-server-live-stream`).
///
/// A subscription re-checks every entry against the project's *current* state
/// — a project can be blocked, or a group can gain one, while the connection is
/// open — and did so with one query per entry per subscriber. Measured, that
/// query was about 70 % of the cost of a delivery, and a group-scoped
/// subscription paid it for every entry of every project on the server, its own
/// group or not. One shared directory turns it into one read per project.
///
/// **When it forgets.** Any write to the `projects` table clears everything
/// (`tableUpdates`), including one made inside a transaction, which drift
/// reports when the transaction commits. Tying this to the table rather than to
/// the routes that happen to write it means a new way of changing a project
/// cannot be one that leaves subscribers with a stale answer. Writes to
/// `projects` are administrative — a project created, blocked, or given a
/// quota — so clearing all of it costs a handful of re-reads, not a hot path.
///
/// Two races are closed on purpose:
///
/// - **A read that started before a change must not outlive it.** A lookup that
///   began, then saw the table change before it finished, has read something
///   that may be out of date; it answers its caller but is not stored
///   ([_generation]).
/// - **Many callers asking at once share one read.** A batch of a thousand
///   entries reaches every subscriber in the same turn, before the first
///   lookup can finish; without sharing, the cache would be empty for all of
///   them and nothing would have been saved ([_inflight]).
///
/// A project that does not exist is not remembered: it cannot be told apart
/// from one not created *yet*, and the question is rare.
class ProjectDirectory {
  final StructuredLogDatabase _db;

  /// Upper bound on projects held. Reaching it drops everything and starts
  /// again — crude, and enough: a server with that many *live* projects is
  /// re-reading a few thousand rows, once.
  final int maxEntries;

  final Map<int, ProjectStanding> _cache = {};
  final Map<int, ({int generation, Future<ProjectStanding?> lookup})>
      _inflight = {};
  int _generation = 0;
  late final StreamSubscription<Set<TableUpdate>> _watch;

  /// Queries issued so far. For tests and diagnostics: how well the cache is
  /// doing is exactly the ratio of this to the questions asked.
  int databaseReads = 0;

  ProjectDirectory(this._db, {this.maxEntries = 10000}) {
    _watch = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.projects))
        .listen((_) => invalidate());
  }

  /// The remembered answer, or `null` if there is none *right now*. Never
  /// waits, which is what lets a delivery that hits the cache stay
  /// synchronous.
  ProjectStanding? peek(int projectId) => _cache[projectId];

  /// The standing of [projectId], read from the database unless it is already
  /// known; `null` if no such project exists.
  Future<ProjectStanding?> standing(int projectId) {
    final known = _cache[projectId];
    if (known != null) return Future.value(known);

    final pending = _inflight[projectId];
    if (pending != null) return pending.lookup;

    final generation = _generation;
    final lookup = _read(projectId, generation);
    _inflight[projectId] = (generation: generation, lookup: lookup);
    return lookup;
  }

  Future<ProjectStanding?> _read(int projectId, int generation) async {
    databaseReads++;
    try {
      final row = await (_db.select(_db.projects)
            ..where((t) => t.id.equals(projectId)))
          .getSingleOrNull();
      if (row == null) return null;

      final standing = ProjectStanding(
        groupId: row.groupId,
        isBlocked: row.isBlocked,
      );
      // Only if the table did not change while this was being read.
      if (generation == _generation) {
        if (_cache.length >= maxEntries) _cache.clear();
        _cache[projectId] = standing;
      }
      return standing;
    } finally {
      final pending = _inflight[projectId];
      if (pending != null && pending.generation == generation) {
        _inflight.remove(projectId);
      }
    }
  }

  /// Forgets everything. Called by the table watch; public so a caller that
  /// changed projects by some route the watch cannot see can say so.
  void invalidate() {
    _generation++;
    _cache.clear();
    // A caller arriving after a change must not be handed a read that began
    // before it.
    _inflight.clear();
  }

  Future<void> close() => _watch.cancel();
}
