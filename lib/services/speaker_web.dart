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
}

/// Say [text] with the browser's voice, cutting off anything still being spoken.
void speakText(String text) {
  try {
    final synth = _synth;
    if (synth == null) return;
    synth.cancel();
    synth.speak(_Utterance(text)..rate = 0.9);
  } catch (_) {
    // Speech is a nice-to-have; never let it break the game.
  }
}
