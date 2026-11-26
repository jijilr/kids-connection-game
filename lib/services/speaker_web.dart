import 'dart:js_interop';

@JS('speechSynthesis')
external _SpeechSynthesis? get _synth;

extension type _SpeechSynthesis._(JSObject _) implements JSObject {
  external void speak(_Utterance utterance);
  external void cancel();
}

@JS('SpeechSynthesisUtterance')
extension type _Utterance._(JSObject _) implements JSObject {
  external factory _Utterance(String text);
  external set rate(double value);
  external set onend(JSFunction? f);
  external set onerror(JSFunction? f);
}

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external String get visibilityState;
  external void addEventListener(String type, JSFunction listener);
}

// Held so the browser cannot throw the utterance away before it has said "done".
_Utterance? _current;

/// Say [text] with the browser's voice, cutting off anything still being spoken.
/// [onDone] is called once when it has been said, or could not be.
void speakText(String text, {void Function()? onDone}) {
  var called = false;
  void done() {
    if (called) return;
    called = true;
    onDone?.call();
  }

  try {
    final synth = _synth;
    if (synth == null) {
      done();
      return;
    }
    synth.cancel();
    final u = _Utterance(text)..rate = 0.9;
    u.onend = ((JSAny? _) => done()).toJS;
    u.onerror = ((JSAny? _) => done()).toJS;
    _current = u;
    synth.speak(u);
  } catch (_) {
    // Speech is a nice-to-have; never let it break the game.
    done();
  }
}

/// Stop the browser's voice at once.
void stopSpeaking() {
  try {
    _synth?.cancel();
  } catch (_) {}
  if (_current != null) _current = null;
}

/// Call [f] whenever the page is hidden: another tab, the phone locked, the app put away.
void whenPageHidden(void Function() f) {
  try {
    _document.addEventListener(
        'visibilitychange',
        ((JSAny? _) {
          if (_document.visibilityState == 'hidden') f();
        }).toJS);
  } catch (_) {}
}
