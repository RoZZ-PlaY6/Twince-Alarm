# Twince Alarm

Standalone Flutter alarm app for Android. The application ID is `com.twince.alarm`. This is a separate app from Twince.

The Android alarm engine stays in this app. Flutter talks to it on the method channel `com.twince.alarm/alarms` (`upsertAlarm` and the other alarm methods). A debug APK from the workflow below is a test build. Installing it does not by itself prove that exact alarms or the lock-screen alarm screen work on a phone.

## Debug APK from GitHub Actions

`.github/workflows/android-debug-apk.yml` builds one debug APK with `flutter build apk --debug` on `ubuntu-latest`. The APK is signed with Android’s automatic debug keystore. There is no release keystore, GitHub secret, or Play Store signing.

The workflow pins Flutter 3.47.8 stable (Dart 3.13.7), the SDK this project was created with, and Java 17, which matches the Android Gradle Plugin 9.1.0 project.

### Default branch placeholder

This folder is not a Git repository, so the default branch could not be read from local Git metadata. The workflow triggers pushes and pull requests for a branch named `REPLACE_WITH_DEFAULT_BRANCH`. Before you rely on those automatic runs, replace that name in `.github/workflows/android-debug-apk.yml` with the repository’s real default branch. Manual runs do not depend on that name.

### Review and push with GitHub Desktop

1. Open this folder in GitHub Desktop.
2. Review the changed files yourself. Do not commit generated output or machine-local files: `build/`, `android/local.properties`, `android/.gradle`, `key.properties`, `*.keystore`, `*.jks`, or any APK. The root `.gitignore` already ignores `/build/`, which is where `flutter build apk` writes the APK.
3. Do commit the Gradle wrapper if Git shows it as a new file: `android/gradlew`, `android/gradlew.bat`, and `android/gradle/wrapper/gradle-wrapper.jar`. The Android `.gitignore` used to ignore those files; they need to be in the repository for the Linux build.
4. Commit and push only when you choose to. These local edits have not been committed or pushed.

### Run the workflow

1. After the workflow file is on the repository’s default branch, open the repository on GitHub and go to the **Actions** tab.
2. Select **Android debug APK** in the workflow list.
3. The workflow also starts on a push or pull request that targets the branch named in the file. To start it yourself, click **Run workflow**, choose the branch that contains the workflow, and confirm.

A green check on that run is the confirmation that GitHub built the APK. A local build on another machine does not mean the Actions run passed.

### Download and install on the Galaxy S25

1. Open the completed workflow run.
2. Download the artifact named `Twince-Alarm-debug-<short commit sha>`. GitHub saves it as a ZIP and keeps it for 14 days. The upload step fails if `build/app/outputs/flutter-apk/app-debug.apk` is missing.
3. Extract the ZIP. Inside is `app-debug.apk`.
4. Copy that APK to the phone if you downloaded it on a computer.
5. Open the APK. If Android says the install is blocked, allow installation from the app you used to open the file (for example Chrome, Files, or My Files): Settings, Apps, Special app access, Install unknown apps, then open the APK again.
6. Install it. The launcher name is Twince Alarm and the application ID is `com.twince.alarm`.

### Permissions and special access

On first launch the app requests notification permission. If a banner remains on the alarm list, use its button:

- **Notifications** — the ringing alarm is a high-priority notification. Without this, the alarm screen may not appear.
- **Alarms & reminders** — exact alarms. If this stays off, alarms are kept but not scheduled.
- **Full-screen notifications** — lets the alarm activity show over the lock screen. Android 14 and later, including Android 16, can keep this off until you allow it.

Those three are the accesses this app actually checks. Granting them on the phone, then trying a real alarm, is still required. A successful APK build does not show that the lock-screen alarm fired.

### Debug signing

This is a debug test build, not a production release. GitHub Actions creates its own debug certificate the first time it builds. A debug APK built on your PC can be signed with a different debug certificate. If Android rejects an update because the package signatures do not match, uninstall Twince Alarm and install the new APK. Uninstalling removes the app’s local alarms and other data.

## Flutter resources

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
- [Flutter documentation](https://docs.flutter.dev/)
