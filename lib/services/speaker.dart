// Speaks short text aloud. On the web this uses the browser's built-in voice
// (Web Speech API); on other platforms it is a silent no-op for now.
export 'speaker_stub.dart' if (dart.library.js_interop) 'speaker_web.dart';
