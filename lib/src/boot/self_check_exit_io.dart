import 'dart:io';

Never finishSelfCheck(String message, int code) {
  (code == 0 ? stdout : stderr).writeln(message);
  exit(code);
}
