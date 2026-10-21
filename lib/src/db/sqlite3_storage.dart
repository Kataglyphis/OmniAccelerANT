import 'package:anthology/Sqlite/sqlite3_healthcheck.dart';

/// The IndexedDB database in the visitor's browser that holds this app's SQLite files; renaming it orphans their data (AGENTS.md § 4).
const String omniIndexedDbName = 'kataglyphis_inference_engine';

/// The healthcheck's file inside [omniIndexedDbName]; a new path starts its count afresh.
const String omniSqliteDatabasePath = '/kataglyphis.db';

/// The About page's SQLite line: one row per run, kept across visits on the web.
Future<String> runOmniSqliteHealthcheck() => runSqliteHealthcheck(
  indexedDbName: omniIndexedDbName,
  webDatabasePath: omniSqliteDatabasePath,
);
