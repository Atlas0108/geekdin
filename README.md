# geekdin

Flutter app targeting Android, iOS, and Web with Firebase as backend (Auth, Storage, and Functions).

## Included

- Flutter project scaffolded for `android`, `ios`, and `web`.
- Firebase Flutter SDK packages:
  - `firebase_core`
  - `firebase_auth`
  - `firebase_storage`
  - `cloud_functions`
- Starter Cloud Function at `functions/index.js` named `helloWorld`.
- Starter app UI in `lib/main.dart` with actions for:
  - anonymous sign-in
  - sample file upload
  - callable function invocation

## Firebase setup (required)

1. Create or choose a Firebase project in the Firebase Console.
2. Configure Flutter platforms (creates `lib/firebase_options.dart` and native config wiring):

```bash
flutterfire configure --project <your-firebase-project-id> --platforms=android,ios,web
```

3. Update `lib/main.dart` to use generated options:

```dart
import 'firebase_options.dart';
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

4. Enable services in Firebase Console:
   - Authentication -> enable Anonymous provider
   - Storage -> create bucket and rules
   - Functions -> enabled by deploying function below

## Cloud Functions setup

Install dependencies and deploy:

```bash
cd functions
npm install
cd ..
firebase login
firebase use --add <your-firebase-project-id>
firebase deploy --only functions
```

## Run the app

```bash
flutter run -d chrome
flutter run -d ios
flutter run -d android
```
