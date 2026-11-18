# ICA16_B — Evidence document (draft)

Anything in **[brackets]** has to come from your own runs: screenshots, timestamps, round-ID suffixes, the commit hash. Don't submit it until those are filled in, since the rubric grades your actual evidence.

**Device/platform:** [e.g. Pixel 7 emulator, Android 15] · **Build:** [release APK / debug] · **Commit:** [git rev-parse --short HEAD] · **Firebase project:** [project ID]

---

## 1. Build checkpoints

| # | Checkpoint | Evidence |
|---|---|---|
| 1 | Firebase connected, signed in as user A | [screenshot of app + Auth console showing user A, password hidden] |
| 2 | OpenTDB decoded and validated | [screenshot of question 1 + `flutter test` output] |
| 3 | Quiz round + review working | [screenshot of review screen with 5 entries] |
| 4 | Cloud verified + console record | [screenshot of app "Cloud verified" next to the Firestore console doc] |

**Failed-first correction:** [Describe one real thing that broke and how you fixed it. Something you actually ran into, like the first build failing before `flutterfire configure`, or a rule rejecting a write.]

**AI disclosure:** [State which AI tool you used, for what parts, and on what date, as the course requires.]

---

## 2. State diagram

See `docs/state_diagram.md`. [Paste a rendered image of the Mermaid diagram here. mermaid.live will export a PNG.]

---

## 3. Test records (T01–T12)

Round IDs are shown as the last 4 characters only. No passwords or tokens anywhere.

| ID | Precondition | Action | Expected | Actual | Pass/Fail | Evidence | Timestamp | Round |
|---|---|---|---|---|---|---|---|---|
| T01 | Signed out | Sign in with a wrong password, then the right one | Visible "Email or password is incorrect.", then the quiz loads as user A | [ ] | [ ] | [fig] | [ ] | – |
| T02 | Signed in, online | Start a round | 5 medium Science & Nature T/F questions, readable text (no `%20`) | [ ] | [ ] | [fig] | [ ] | [ ] |
| T03 | Dev tools: Bad % / Code≠0 / 4 results (one at a time) | Start a round each time | Each one blocks play with a readable error; the retry button counts down from 5 s | [ ] | [ ] | [fig ×3] | [ ] | – |
| T04 | Mid-round | Pick a correct answer, a wrong one, then tap the other button again | Buttons lock after one tap, green ✓ / red ✗ with text, score only changes once | [ ] | [ ] | [fig] | [ ] | [ ] |
| T05 | Round finished | Check the review, then Play a new round | 5 review rows, correct total; new round ID, Q1, score 0 | [ ] | [ ] | [fig] | [ ] | [old]/[new] |
| T06 | Ready to submit | Double-tap Submit | Exactly one document in the console with a server timestamp, and "Cloud verified" with the same values | [ ] | [ ] | [fig: app + console] | [ ] | [ ] |
| T07 | T06 done | Kill the app, reopen, sign in as user A, look up the same ID in Saved rounds | Same score and timestamp from the server, no replay needed | [ ] | [ ] | [fig] | [ ] | [ ] |
| T08 | Ready to submit | Airplane mode → Submit → reconnect → Retry | No success while offline (saveUnknown, unavailable or timeout). After retry: reconciles the same ID, one document | [ ] | [ ] | [fig ×2 + trace] | [ ] | [ ] |
| T09 | Dev: Deny next verification ON | Submit | "Write acknowledged; verification unavailable." Console already shows the doc. Retry → Cloud verified, same ID, still one doc | [ ] | [ ] | [fig ×3 + trace] | [ ] | [ ] |
| T10 | Signed in as user B, user A's UID pasted | Read their path / Write their path | Both `permission-denied` | [ ] | [ ] | [fig of probe log] | [ ] | – |
| T11 | User A with an existing round ID | Score 6 / Extra field / Update existing / Re-read original | First three `permission-denied`; re-read shows the original values unchanged | [ ] | [ ] | [fig] | [ ] | [ ] |
| T12 | Dev: Unavail., then Quota | Submit, then Retry each time | Different chips (`error: unavailable` vs `error: resourceExhausted`), retry counter caps at 5, no fake success, `[INJECTED]` shown | [ ] | [ ] | [fig ×2] | [ ] | [ ] |

---

## 4. Critical thinking

### Q1. Decode the evidence

[Replace the example pair with one from your own T02 run.] On one of my runs, OpenTDB sent `Polaris%20is%20the%20brightest%20star%20in%20the%20northern%20hemisphere%20night%20sky.` and the app showed "Polaris is the brightest star in the northern hemisphere night sky." The category comes in as `Science%20%26%20Nature`, and it has to decode to exactly "Science & Nature" or the round gets rejected (`question.dart`, `_parseOne`).

The URL asks for `encode=url3986`, which is RFC 3986 percent encoding. Every reserved byte becomes `%` plus two hex digits, and multi-byte UTF-8 characters become several of those in a row. `Uri.decodeComponent` (question.dart:102) is the exact inverse of that. An HTML unescaper only knows entities like `&amp;` or `&quot;`. It would leave `%20` and `%26` sitting there, so the question would look broken, and worse, the category check would fail, or the answer comparison would compare `True` against something that never matches. Malformed input like `%E0%A4%A` makes `decodeComponent` throw, and I catch that and turn it into an invalid-data error (T03). An HTML unescaper would just pass the garbage through silently.

### Q2. Separate outcomes

In T09 the trace shows [paste your lines, e.g. `Commit acknowledged: created …a1b2` then `verificationUnavailable: [permissionDenied] Write acknowledged; verification unavailable…`]. Those two outcomes live in different variables. `_commitAcknowledged` is set to true (quiz_controller.dart:301) only after the transaction future resolves, which means Firestore accepted the write. The verification result is separate. It's either `_verified` being filled in, or `_errorKind` plus the `verificationUnavailable` phase.

Once `_commitAcknowledged` is true, `_runCloud` skips the write step entirely, so retrying from `verificationUnavailable` can only re-read the same reference. It can't write a second document or pick a new ID. Each UI message has a specific piece of evidence behind it. "Write acknowledged" requires a resolved transaction. "Cloud verified" requires a server-only snapshot that exists, has exactly six fields with the right values, a real `Timestamp`, `isFromCache == false` and `hasPendingWrites == false` (attempt.dart, `fromServerSnapshot`). "Nothing was saved" is only shown for a `permission-denied` on the write itself, because that's the only case where the server told us no.

### Q3. Identity and collision

The round ID is the identity of one completed round. If a retry reuses the ID with the same five fixed fields, the transaction reads the existing doc, `payload.matches()` returns true, and the result is `reusedExisting`. Nothing is written, and the UI notes "existing record reused, no duplicate." That's what makes the retry safe.

If the same ID shows up with a different score, that isn't a retry. Either something is buggy or someone's tampering. The transaction throws `AttemptCollision` (attempt_repository.dart:99) and the app goes to `collision` without overwriting. The rules back this up anyway, since `allow update: if false`.

A genuinely new round is different. Replay calls `startRound()`, which generates a fresh `attempts.doc().id`, clears the answers and the frozen payload, and resets `_commitAcknowledged`. That new ID gets its own create. So "same ID, different data" means conflict, and "new ID" means a new, independent attempt. [Optional: add a screenshot if you forced a collision during testing.]

### Q4. Access is not truth

In T10 I signed in as user B, pasted user A's UID into the dev panel, and tried both a server read and a write of a valid payload under `users/{A}/attempts`. Both came back `permission-denied` [paste probe log lines + timestamps]. The rule `request.auth.uid == uid` doesn't match B's token, and nothing else in the rules file grants access.

That only proves *who* can write, not that the score is *honest*. User A owns their path, so A could skip the quiz and call `set()` with `correctCount: 5` and a server timestamp. That passes `validAttempt()` because 5 is in range and the field set is right. The rules can't know which questions were asked or what A answered.

A trusted fix moves scoring to the server. A Cloud Function (or Cloud Run endpoint) would fetch and keep the questions, hand the client only question IDs plus a signed round token, take the answers, score them itself, and write the attempt with the Admin SDK. Client writes to `attempts` would then be denied completely. Replay protection would come from marking the round token as used.

### Q5. Critique the AI

[If you ran your own prompt, put the prompt, tool, date, and a short excerpt here. Otherwise use the instructor candidate below.]

The candidate says to make the database public, create a new document ID, save again, show success from the cache, and put an admin key in Flutter. Here's what's wrong with each part:

- **Authorization:** public rules let anyone read or overwrite every user's scores. T10 would flip from denied to allowed.
- **Duplication:** the write already succeeded, so a new ID creates a second attempt for the same round. My T09 run shows one document after the read failed, which proves the first save was real.
- **Credential:** an admin key in an APK can be pulled out with any unzip tool and gives full project access, ignoring the rules.
- **Confirmation:** a cached read isn't server proof. It can show data that never reached the server.

Tested claim 1: "the read failure means the write might be lost." False. The console showed the doc right after the injected denial. Tested claim 2: "a new ID avoids the error." It does make the error go away, but it creates a duplicate.

My revision keeps the owner-only rules and the same ID, does a bounded user-triggered server-only re-read, and says "Write acknowledged; verification unavailable" until that re-read passes.

### Q6. Defend your UX

[Insert screenshots of the two states side by side.] "Save failed" only appears when the server actually rejected the write (`permissionDenied`). It uses a red border and a block icon, and the message says "Nothing was saved." "Verification unavailable" uses an amber border and a cloud-off icon. Its message says the score *was* accepted, won't be deleted, and won't be saved again, and the button says "Retry same round (n/5)." I picked amber because the situation isn't a failure, just unconfirmed, and red would push people to replay and create a duplicate. The error chip (`error: permissionDenied`, `error: unavailable`, and so on) keeps the different causes visibly distinct for T12.

Failed-first test: [Describe a real one. For example, the first time you ran T09, did replay stay unlocked or did the message say "failed"? Describe what you saw, what you changed, and the re-run.] The current behavior locks replay and sign-out in every unresolved phase (`unresolved`, quiz_controller.dart:116), so you can't leave the round until it's actually resolved.

---

## 5. Console + server-read proof

[Screenshot: Firestore console → users → (uid redacted) → attempts → (ID redacted) showing the six fields.]
[Screenshot: app "Cloud verified" card and Saved rounds lookup for the same ID.]
