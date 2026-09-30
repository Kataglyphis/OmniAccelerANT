import 'package:flutter/material.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/src/db/sqlite3_healthcheck.dart';

/// SQLite3 health status, checked on init and re-runnable by button.
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
