import 'package:flutter/material.dart';

import 'package:kataglyphis_inference_engine/src/db/sqlite3_healthcheck.dart';

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
    return Column(
      children: [
        TextButton(
          onPressed: _rerun,
          child: const Text('SQLite Healthcheck erneut ausführen'),
        ),
        FutureBuilder<String>(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return Text(
                'SQLite Error: ${snapshot.error}\n\nHinweis: Für Web muss eine sqlite3.wasm unter /web/sqlite3.wasm liegen.',
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
