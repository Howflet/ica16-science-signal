# Science Signal (ICA 16, Class B)

A five-question Science & Nature true/false quiz in Flutter. Questions come from OpenTDB, the score is committed once to Cloud Firestore under the signed-in user, and then it's read back straight from the server before the app says **Cloud verified**.

## What's where

| Path | What it does |
|---|---|
| `lib/models/question.dart` | Validates and URL-decodes the OpenTDB response (status, response_code, exactly 5, category/difficulty/type, True/False answer set) |
| `lib/models/quiz_round.dart` | One round: saved selections, one answer per question, score derived from selections |
| `lib/models/attempt.dart` | The six-field Class B schema and the field-by-field server verification checks |
| `lib/services/trivia_api.dart` | The exact Class B URL, 10 s timeout, 5 s minimum gap between requests, no automatic retry |
| `lib/services/attempt_repository.dart` | Create-once transaction, saveUnknown reconciliation, server-only verification read |
| `lib/state/quiz_controller.dart` | The state machine, the 10 s UI timeout, bounded user-triggered retries, stale-callback guard |
| `lib/screens/` | Sign-in, quiz, review + cloud status, saved rounds (server), developer tools |
| `lib/dev/dev_faults.dart` | One-shot, labelled fault injection (debug builds only) |
| `firestore.rules` | The required owner-only rules, deployed as-is |
| `test/quiz_logic_test.dart` | Unit tests for decoding, validation and scoring |

## Setup

You need Flutter, an Android device or emulator, Node (for the Firebase CLI), and a Firebase project you control. Use a **separate** project from Class A.

### 1. Firebase project (console)

1. Create a project at https://console.firebase.google.com.
2. **Firestore Database → Create database** → Standard edition, Native mode, **production mode**.
3. **Authentication → Sign-in method** → enable **Email/Password**.
4. **Authentication → Users → Add user** twice: test user A and test user B. Keep the passwords out of the repo and out of screenshots.

### 2. Connect the app

```bash
npm install -g firebase-tools
```

```bash
firebase login
```

```bash
dart pub global activate flutterfire_cli
```

```bash
flutterfire configure
```

Pick your project and select **android** only. The Android package name is `edu.gsu.mad.science_signal`. This replaces the placeholder `lib/firebase_options.dart` and adds `android/app/google-services.json`.

### 3. Deploy the rules

```bash
firebase use --add
```

```bash
firebase deploy --only firestore:rules
```

Check the **Rules** tab in the console afterwards and confirm it matches `firestore.rules`.

### 4. Run it

```bash
flutter pub get
```

```bash
flutter run
```

Debug builds show a bug icon in the app bar for the developer tools. A release build hides them unless you pass `--dart-define=DEV_TOOLS=true`.

### 5. Release APK

```bash
flutter build apk --release
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. Rename it to `ICA16_B_YourName.apk` for submission.

## Reproducing the restart retrieval (T07)

1. Sign in as test user A, play a round, submit, and wait for **Cloud verified**.
2. Tap the cloud icon (Saved rounds) and copy the round ID.
3. Fully close the app (swipe it away) and open it again while online.
4. Sign in as the same user, open Saved rounds, paste the ID and tap the download icon. The app does a server-only read and shows the same score and timestamp. The list below it is also loaded from the server.

Test account credentials for grading are shared only through the course's private channel, never in this repo.

## How the cloud part works

- **Path:** `users/{currentUser.uid}/attempts/{roundId}`. The UID always comes from Firebase Auth, never from a text field.
- **Round ID:** `attempts.doc().id` when the round starts. It's only generated locally; nothing is written until submit. Every retry reuses it. Replay makes a new one, but replay (and sign-out) is locked while a result is unresolved.
- **Commit:** a transaction reads the document first. Missing means create it. Present with the same five fixed fields means reuse it. Present with different fields means a collision, and nothing gets overwritten. The callback does nothing but read and set.
- **Verify:** `get(GetOptions(source: Source.server))` on the same reference. It has to exist, have exactly the six fields with the right values, a resolved `Timestamp`, and no cache or pending writes. Only then does the UI say **Cloud verified**.
- **Write OK, read failed:** the app shows *"Write acknowledged; verification unavailable."* It doesn't delete anything, doesn't make a new ID, and the retry only re-reads.
- **Timeout:** the UI gives up after 10 s, but the real write keeps going. The app goes to `saveUnknown`, blocks overlapping writes until the first one settles, and the next retry does a server read of the same ID *before* it tries to write.
- **Identity change:** each cloud call remembers its UID, round ID and a generation counter. If any of them changed by the time it finishes, the result is thrown away.

## Developer tools (debug only)

Every injected failure is one-shot and labelled `[INJECTED]`. None of them touch the deployed rules.

- **Question faults (T03):** bad percent encoding, `response_code` 1, four results.
- **Commit faults (T12):** `unavailable`, `resource-exhausted`, or a slow 13 s commit to watch the 10 s timeout and the late acknowledgement.
- **Deny next verification (T09):** the commit is real; only the first read after it fails.
- **Cross-user probe (T10):** read and write another user's path. Both should come back `permission-denied`.
- **Invalid payload probes (T11):** score 6, an extra field, an update to an existing round, then re-read the original to show it didn't change.
- **State trace:** every transition with a timestamp. IDs are cut down to their last four characters. Copy it into your evidence.
