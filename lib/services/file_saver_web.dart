import 'dart:js_interop';

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
