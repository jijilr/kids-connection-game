import 'dart:js_interop';
import 'dart:typed_data';

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _Anchor createElement(String tag);
}

extension type _Anchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

/// Hand [text] to the browser as a download called [name]. True if the browser took it.
bool saveTextFile(String name, String text) {
  try {
    _document.createElement('a')
      ..href = 'data:application/json;charset=utf-8,${Uri.encodeComponent(text)}'
      ..download = name
      ..click();
    return true;
  } catch (_) {
    return false;
  }
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external String _createObjectURL(_Blob blob);

/// Hand a picture or other bytes to the browser as a download called [name]. True if
/// the browser took it. A large picture goes as a blob, not as text in the address.
bool saveBytesFile(String name, List<int> bytes, String type) {
  try {
    final data = Uint8List.fromList(bytes).toJS;
    final blob = _Blob(<JSAny>[data].toJS, _BlobOptions(type: type));
    _document.createElement('a')
      ..href = _createObjectURL(blob)
      ..download = name
      ..click();
    return true;
  } catch (_) {
    return false;
  }
}
