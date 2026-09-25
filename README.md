# Dayforge

Dayforge is a Flutter daily log for Windows, Linux, and Android. It keeps a separate entry per date, with notes for previous outstanding tasks, emails, meetings, and a task list with subtasks.

Edits save automatically to a local JSON file. No cloud sync is implemented yet.

Use the date arrows or calendar button to switch days. Add notes in the first three sections, then add tasks in the task section. Check a task to strike it through and move it to the bottom; use the arrow action on a task to add an indented subtask. The save status appears in the top bar.

## Run

Install Flutter and the platform's required build tools, then from the repository root:

```sh
flutter pub get
flutter run -d linux
```

Linux desktop development requires CMake, Ninja, GTK development headers, and the other Flutter Linux desktop prerequisites. Android builds require the Android SDK and a supported JDK.

To build platform packages:

```sh
flutter build linux
flutter build windows
flutter build apk
```

Run analysis and tests:

```sh
flutter analyze
flutter test
flutter test test/widget_test.dart
```

Linux data is stored under `$XDG_DATA_HOME/dayforge` or `~/.local/share/dayforge`. Windows uses `%LOCALAPPDATA%\dayforge`, and Android uses the app's private files directory.

## Binaries

After a successful CI run for a change pushed to `main`, automation tags each untagged mainline commit with the next patch version and publishes generated release notes. Tagged preview builds are published on the [GitHub Releases](https://github.com/Reedboot/Dayforge/releases) page as Android APK, Linux x64, and a Windows setup EXE. Manually creating and pushing a `v*` tag also triggers a build.

The preview APK is signed with a temporary CI debug key. It is for testing only; later preview APKs may require uninstalling the previous build. A stable private signing key must be configured before distributing APKs that should update existing installs.

The Windows download is a per-user installer. Run the setup EXE to install Dayforge under `%LOCALAPPDATA%\Programs\Dayforge` and create a Start Menu shortcut.
