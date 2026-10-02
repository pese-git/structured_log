/// Without `dart:io` — on the web — `stderr` throws on every write, so
/// internal failures go through `print`, which lands in the browser console.
void platformReport(String message) => print(message);
