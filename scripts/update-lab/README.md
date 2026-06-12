# Update lab — local Sparkle update-flow testing

Exercise the full in-app update pipeline against a loopback feed, without
touching production keys, the appcast on `gh-pages`, or the build product.

```sh
make update-test-none           # "You're up to date." alert
make update-test-download-fail  # download dies mid-transfer → error in the update window
make update-test-extract-fail   # signed-but-corrupt archive → extraction error in the window
make update-test-success        # real update: download → verify → install → relaunch as 99.0.0
make update-test-stop           # tear down (server, app under test, lab copies)
```

Each scenario builds Debug, then:

1. Copies the app to `build/update-lab/run/LockIME Dev.app`, swaps `SUPublicEDKey`
   for a throwaway dev key (file-backed via CryptoKit — never the keychain),
   and re-signs ad-hoc. The DerivedData product is never mutated.
2. Shapes `appcast.xml` for the scenario and signs archives with Sparkle's own
   `sign_update` (from the SPM artifact), so verification is the real path.
3. Serves everything from `python3 server.py` on `localhost:8767`
   (`UPDATE_LAB_PORT` overrides). `/truncate/<file>` advertises the full
   `Content-Length` but resets the connection at ~35% — the download-failure
   case. `.zip` responses are throttled to ~4 MB/s so progress UI is visible.
4. Launches the copy with the Debug-only hooks (see `UpdaterDelegate` /
   `LockIMEUserDriver`):
   - `LOCKIME_UPDATE_FEED` — feed override via `feedURLString(for:)`
   - `LOCKIME_UPDATE_CHECK_ON_LAUNCH=1` — fires a user-style check after ~1s
   - `LOCKIME_UPDATE_AUTO_INSTALL=1` — auto-accepts install prompts
     (`UPDATE_LAB_AUTO=1 make update-test-success` runs hands-free end to end)

All hooks are `#if DEBUG`; release builds ignore the environment entirely, so
the script refuses an app that lacks them (e.g. a `CONFIG=Release` build —
that copy would silently poll the production feed with the dev key instead).

Notes:

- Scenarios kill any running Debug app (like `make run`), reset Sparkle's
  skipped-version defaults, and clear its download cache for determinism.
- The app under test uses the Debug app's `com.oomol.LockIME.dev` defaults
  domain, separate from the released `com.oomol.LockIME` app. The lab touches
  only Sparkle's skipped-version keys (`SUSkippedVersion`,
  `SUSkippedMajorVersion`, `SUSkippedMajorSubreleaseVersion`) and
  `SULastCheckTime`, and both scenario start *and* `update-test-stop` clear the
  skip keys for determinism.
- Expected error copy: download failure → "couldn't be downloaded";
  extraction failure lands in Sparkle's 3000s (signature/unarchive) bucket →
  "couldn't be verified" (see `UpdateFailure`).
- After a `success` run the relaunched 99.0.0 copy lives in
  `build/update-lab/run/` and checks the production feed on its normal
  schedule (with the dev public key, so it would refuse a real update —
  re-running any scenario or `make update-test-stop` cleans it up).
