import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The bytes of a fetch [body] as they arrive; a listener that leaves ends the read at once, also during a silence.
Stream<List<int>> fetchBodyChunks(web.ReadableStream? body) {
  if (body == null) return const Stream<List<int>>.empty();
  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  final chunks = StreamController<List<int>>();
  chunks.onListen = () => unawaited(_pump(reader, chunks));
  // An aborted body refuses the cancel, which then has nothing left to end.
  chunks.onCancel = () => reader.cancel().toDart.ignore();
  return chunks.stream;
}

Future<void> _pump(
  web.ReadableStreamDefaultReader reader,
  StreamController<List<int>> chunks,
) async {
  try {
    while (true) {
      final read = await reader.read().toDart;
      if (read.done) break;
      chunks.add((read.value! as JSUint8Array).toDart);
    }
  } on Object catch (failure) {
    chunks.addError(failure);
  }
  await chunks.close();
}
