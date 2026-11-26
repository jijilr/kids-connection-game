/// Non-web platforms: no built-in voice yet (recorded clips still play). What would
/// have been said counts as said at once.
void speakText(String text, {void Function()? onDone}) => onDone?.call();

void stopSpeaking() {}

void whenPageHidden(void Function() f) {}
