# Copilot instructions for Dayforge

## Product and architecture
- Dayforge is a Flutter/Dart daily log targeting Windows, Linux, and Android.
- `DailyLogPage` presents one date at a time; `DailyLog`/`DailyTask`/`DailySubtask` hold the data; `DailyLogStore` handles persistence separately from the widgets.
- Each date has notes for previous outstanding tasks, emails, and meetings, plus a checkbox task list. Notes are free-form text; tasks and their user-authored, indented subtasks are editable and checkboxable.
- Completing a task or subtask applies strikethrough and moves it to the bottom of its respective list. The previous-outstanding section is currently a note field; automatic carry-over between dates is not implemented.
- Edits autosave locally to a versioned JSON file and load at startup. Data lives in the platform app-data directory; cross-device sync is not implemented.
- Flutter renders its shared widget UI; do not assume controls are native operating-system widgets.

## Dependencies and licensing
- Do not add paid dependencies or MIT-licensed third-party libraries.
- Before adding a Dart/Flutter package or platform plugin, verify its license and commercial requirements, including transitive runtime dependencies. The app currently declares no additional runtime packages; the Flutter SDK supplies its own transitive dependencies, and tests use `flutter_test` from the SDK.
- The app uses Dart/Flutter standard libraries and a small Android platform channel for the app-private files directory. Check storage packages independently if replacing this implementation.

## Build, test, and analysis
- Fetch dependencies with `flutter pub get`.
- Run static analysis with `flutter analyze`.
- Run all tests with `flutter test`; run the UI/autosave test alone with `flutter test test/widget_test.dart`, or the storage tests with `flutter test test/daily_log_store_test.dart`.
- Run locally with `flutter run -d linux` (or the available target device). Build with `flutter build linux`, `flutter build windows`, or `flutter build apk`.
- Linux desktop builds require Flutter's Linux prerequisites, including CMake and GTK development files.
