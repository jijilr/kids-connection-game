/// Non-web platforms: no file is saved. Returns false, and the screen offers Copy.
bool saveTextFile(String name, String text) => false;

/// Hand a picture or other bytes to the device as a file called [name]. Not available
/// off the web yet.
bool saveBytesFile(String name, List<int> bytes, String type) => false;
