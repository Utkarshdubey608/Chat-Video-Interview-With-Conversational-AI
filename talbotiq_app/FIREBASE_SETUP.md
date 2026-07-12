# Firebase setup — TalbotIQ auth & interview assignment

The app now has login (email/password) with **Recruiter** and **Candidate** roles,
and stores recruiter-created interviews (assigned to a candidate email) in
Firestore. The code is written against the Firebase SDK, but it needs a real
Firebase project to run. Do the steps below once.

## 1. Create the project & enable services
1. Go to the [Firebase console](https://console.firebase.google.com/) → **Add project**.
2. **Build → Authentication → Get started → Sign-in method →** enable **Email/Password**.
3. **Build → Firestore Database → Create database** (start in production mode).

## 2. Generate the Flutter config
From the `talbotiq_app/` project directory:
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```
Select your project and the platforms you target. This **overwrites**
`lib/firebase_options.dart` (currently a placeholder that throws) and adds:
- `android/app/google-services.json` (+ the google-services Gradle plugin)
- `ios/Runner/GoogleService-Info.plist`
- web config as needed

Then:
```bash
flutter pub get
flutter run
```

## 3. Deploy the security rules
The repo includes `firestore.rules` (candidates can only read/update interviews
assigned to their email; recruiters manage only their own). Deploy them:
```bash
firebase deploy --only firestore:rules
```
(or paste the file's contents into the console → Firestore → Rules).

## 4. First run
1. **Sign up as a Recruiter.** Open **Settings → API Credentials**, enter the
   Tavus / Gemini / (Deepgram / Hume) keys, then tap the **cloud-upload** icon in
   the recruiter app bar to **sync keys to cloud** (so candidate devices can use
   them — see note below).
2. Tap **Create interview**: choose Video or Chat, set the prompt, questions,
   avatar (video), duration, and the **candidate's email**. Save.
3. **Sign up as a Candidate** using that same email. The assigned interview
   appears under Video or Chat; tap **Launch**.

## Firestore data model
- `users/{uid}` — `{ email, emailLower, role, name?, createdAt }`
- `interviews/{id}` — `{ recruiterId, recruiterEmail, candidateEmail,
  candidateEmailLower, candidateName?, type: video|chat, title, prompt,
  questions[], avatar{replicaId, personaId}, durationMinutes, status, result?,
  createdAt, updatedAt }`
- `recruiter_keys/{recruiterId}` — each recruiter's API keys (only that
  recruiter can write; see notes).

## Notes / caveats
- **API keys are per-recruiter (per-org).** Each recruiter stores their keys in
  `recruiter_keys/{their uid}` (via the cloud-sync button). A candidate's own
  keys (for Practice) live only on their device and are shown in *their*
  Settings; **org keys are never pulled into the candidate's AppStore/Settings**.
  At the moment a candidate launches an assigned interview, the app fetches that
  interview's recruiter keys and applies them to the in-memory services only —
  so different orgs' interviews use different keys and never cross-consume.
- **Not cryptographic secrecy.** Because interviews are created on the
  candidate's device, the key is necessarily in memory at launch and the rules
  allow signed-in reads of `recruiter_keys`, so a technically-skilled candidate
  could still read it. This hides keys from the app UI. For true secrecy, move
  the Tavus/Gemini calls into a Cloud Function proxy that returns only the video
  URL.
- **Candidate email matching is case-insensitive** (`candidateEmailLower`). The
  candidate must sign in with the exact email the recruiter assigned.
- Consider enabling **email verification** and requiring it in the rules if you
  need stronger assurance that a candidate owns the assigned address.
