**Verdict: Phase 2 implemented as specified.** All four success criteria pass; two minor deviations, both acceptable.

## Success criteria

| Criterion (doc:150-151) | Result | Evidence |
|---|---|---|
| `ViewEvent` gains `email: Option<String>` | pass | `server/src/views/capture.rs:50-54` |
| `page` passes in-scope `identity` into `capture()` | pass | `server/src/render.rs:757` builds `viewer_email` from `Option<Extension<Identity>>` (`render.rs:736`), passed at `render.rs:759`; sole non-test call site (only other `capture(` hits are the unrelated `Overlay::capture`) |
| Identified read + gate on ⇒ `email == Some(addr)` | pass | gate stored `capture.rs:74,90`, applied `capture.rs:128-131`; test `capture/tests.rs:108-119`, ran green |
| Anonymous read ⇒ `None` | pass | test `capture/tests.rs:121-132` |
| Gate off ⇒ always `None` | pass | test `capture/tests.rs:134-146` (passes `Some("grace.hopper@…")` with `capture_viewers` default false) |
| Capture stays non-blocking | pass | `capture.rs:116-148`: one `str::to_string`, no `.await`, no lock; still `try_send` at `:140` |

Test evidence: `cargo test -p marquee-server views::capture` → 8 passed, 0 failed (incl. the three new ones). `cargo test --workspace` → all suites 0 failed (329 server + 155 + 126 + 121 + …). `cargo clippy --workspace --all-targets` → no warnings, no errors.

Compile-fixups in the diff are real and present: `views/collect/tests.rs:14` and `views/tests.rs:43` add `email: None`.

## Deviations

- **Signature takes `Option<&str>`, not `identity?`.** Doc's arch sketch says `capture(headers, identity?)` (doc:56). Impl takes `viewer_email: Option<&str>` (`capture.rs:116-122`) and projects the email at the call site (`render.rs:757`). **Acceptable**: narrower coupling, keeps `Identity` out of the views module, same observable behavior.
- **No non-empty check on the email.** Doc says populate only when "the read carried a validated email" (doc:95, :150). Impl forwards `id.email` whenever the extension exists, with no `is_empty` filter. `Identity.email` on the verified path is `claims.email.unwrap_or(claims.sub)` (`core/src/auth.rs:180`), so an empty-string `email` claim would be captured as `Some("")`; the dev-auth path does filter (`core/src/auth/identity.rs:110`). **Acceptable** for Phase 2 (Okta will not issue an empty email claim), but Phase 3/4 must not assume non-empty when folding into the rollup / sorting for `/meta`.

## Unverifiable

- The `page` → `capture` threading itself has no test; it is verified by reading `render.rs:757-759` only. Phase 2's stated criteria only demanded capture-level unit tests, so this is not a miss against the spec.
- `ViewEvent.email` currently has no non-test consumer (`grep email server/src/views/` hits only test fixtures) — expected, that is Phase 3.
