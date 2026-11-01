import 'dart:typed_data';

Never finishSelfCheck(String message, int code) =>
    throw UnsupportedError('The ONNX self-check requires a desktop platform.');

Future<Uint8List> readSelfCheckFile(String path) =>
    throw UnsupportedError('The detect check requires a desktop platform.');
