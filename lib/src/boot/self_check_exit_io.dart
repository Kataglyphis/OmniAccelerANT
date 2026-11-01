import 'dart:io';
import 'dart:typed_data';

Never finishSelfCheck(String message, int code) {
  (code == 0 ? stdout : stderr).writeln(message);
  exit(code);
}

/// The bytes of a file named on the command line.
Future<Uint8List> readSelfCheckFile(String path) => File(path).readAsBytes();
