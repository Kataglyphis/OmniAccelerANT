import 'package:flutter/material.dart';
import 'package:kataglyphis_inference_engine/l10n/app_localizations.dart';
import 'package:kataglyphis_inference_engine/src/db/sqlite3_healthcheck.dart';

/// Widget that displays SQLite3 database health status.
///
/// Performs a health check on app initialization and provides
/// a button to manually re-run the check.
class Sqlite3HealthcheckWidget extends StatefulWidget {
  const Sqlite3HealthcheckWidget({super.key});

  @override
  State<Sqlite3HealthcheckWidget> createState() =>
      _Sqlite3HealthcheckWidgetState();
}

class _Sqlite3HealthcheckWidgetState extends State<Sqlite3HealthcheckWidget> {
  Future<String>? _result;

  @override
  void initState() {
    super.initState();
    _result = runSqliteHealthcheck();
  }

  void _rerun() {
    setState(() {
      _result = runSqliteHealthcheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        TextButton(
          onPressed: _rerun,
          child: Text(localizations.rerunSqliteHealthcheck),
        ),
        FutureBuilder<String>(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return Text(
                '${localizations.sqliteError}: ${snapshot.error}\n\n'
                '${localizations.sqliteWebHint}',
                textAlign: TextAlign.center,
              );
            }
            return Text(
              'SQLite: ${snapshot.data}',
              textAlign: TextAlign.center,
            );
          },
        ),
      ],
    );
  }
}
