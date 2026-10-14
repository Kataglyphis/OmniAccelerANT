import 'dart:convert';

/// [body] as a JSON object, or `null` for no body, malformed JSON or any other JSON value.
Map<String, dynamic>? decodeJsonObject(String? body) {
  if (body == null) {
    return null;
  }
  try {
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}

/// What [fetch] returns, or `null` when it throws: an ObservANT camera that cannot be reached answers nothing.
Future<String?> fetchOrNull(Future<String?> Function() fetch) async {
  try {
    return await fetch();
  } on Object {
    return null;
  }
}
