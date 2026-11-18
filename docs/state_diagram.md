# Science Signal state machine

Names match `Phase` in `lib/state/quiz_controller.dart`.

```mermaid
stateDiagram-v2
    [*] --> signedOut
    signedOut --> authError: signIn() throws FirebaseAuthException
    authError --> signedOut: user edits form
    signedOut --> loading: authStateChanges(user != null)
    authError --> loading: authStateChanges(user != null)

    loading --> playing: TriviaParser.parse() OK / roundId = attempts.doc().id
    loading --> requestError: timeout, HTTP != 200, response_code != 0, count != 5, bad encoding
    requestError --> loading: Try again [cooldown 5 s elapsed]

    playing --> playing: select() [question not answered] / next() [answered && !isLast]
    playing --> readyToSubmit: next() [answered && isLast]
    readyToSubmit --> loading: replay()

    readyToSubmit --> submitting: submit() / freeze payload
    submitting --> verifying: transaction acked (created | reusedExisting)
    submitting --> saveUnknown: 10 s timeout, unavailable, resource-exhausted, other
    submitting --> permissionDenied: permission-denied, unauthenticated
    submitting --> collision: same ID, different correctCount

    verifying --> cloudVerified: server read passes every check
    verifying --> verificationUnavailable: read denied / timeout / unavailable / mismatch

    saveUnknown --> submitting: retryCloud() [tries < 5 && no write in flight] / server read of same ID first
    permissionDenied --> submitting: retryCloud() [tries < 5]
    verificationUnavailable --> verifying: retryCloud() [tries < 5] / commitAcknowledged stays true

    cloudVerified --> loading: replay()
    permissionDenied --> loading: replay()
    collision --> loading: replay()

    note right of saveUnknown
      replay and sign-out are locked in
      submitting, verifying, saveUnknown,
      verificationUnavailable
    end note
```

Any transition into `signedOut` (or a different user's `loading`) bumps `_generation`. A cloud call that comes back under an old generation, UID or round ID is ignored (`stale()` in `_runCloud`).
