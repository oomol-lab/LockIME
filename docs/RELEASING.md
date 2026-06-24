# Releasing LockIME

Releases run on GitHub Actions (`blacksmith-6vcpu-macos-latest`). Distribution
is **Developer ID + notarized** (non-sandboxed), with auto-updates via
**Sparkle** over two channels. Git tags are the single source of truth for
versions, and the workflows create them — you never push a tag by hand.

## Versioning model

- **Local builds are always `0.0.0-development`** (`project.yml`'s
  `MARKETING_VERSION`). Real versions exist only in CI, which overrides
  `MARKETING_VERSION` at archive time with a value computed from git tags by
  `scripts/ci/compute_version.sh`.
- **Debug builds are a separate local app**: `LockIME Dev.app` with bundle
  identifier `com.oomol.LockIME.dev`. Release archives and published builds stay
  `LockIME.app` / `com.oomol.LockIME`, so local development has independent
  TCC permissions, defaults, and app-support storage.
- **Stable** versions are `X.Y.Z`; **beta** versions are
  `X.Y.Z-beta.N`, where `X.Y.Z` is the latest stable tag and `N` continues
  from the highest existing `-beta.*` tag for that base.
- Every published build creates the matching `vX.Y.Z[-beta.N]` git tag and a
  GitHub Release carrying a zip and a notarized `.dmg` **per architecture**
  (`LockIME-<version>-arm64.*` and `LockIME-<version>-x86_64.*`). Beta
  releases are marked **pre-release**, so they are never shown as "Latest".
- An explicit stable version must be **newer than the latest stable tag** —
  backfill releases are rejected by `compute_version.sh` (a newer-created
  release would steal "Latest", and the date-stamped build number would top
  the appcast).
- **Bootstrap:** the very first release must be a stable one with an explicit
  version (e.g. `0.1.0`) — scheduled nightlies skip (and `compute_version.sh
  beta` refuses) until a stable tag exists to serve as the beta base.

## Channels

Two channels, two triggers — both end in `build-publish.yml`, the shared
reusable workflow (build, test, notarize, staple, tag, release, appcast):

- **Stable** — manual. Run the **Release** workflow (Actions → Release →
  Run workflow). Give it an explicit version, or leave the field empty to
  auto-bump the latest stable tag (the `bump` choice picks the segment:
  `patch` by default, or `minor` / `major`).
- **Beta** — the **nightly build**. `nightly.yml` runs every day at
  **01:00 UTC** (and on manual dispatch), builds the tip of `main`, and
  publishes it as `X.Y.Z-beta.N` to the beta channel. Scheduled runs are
  skipped when no commits landed since the last tagged build (every build
  tags its commit, so this means "nothing new to ship") and while no stable
  tag exists yet; manual dispatches always build.

**Build numbers are unified.** `build-publish.yml` sets `CFBundleVersion` to a
date-based stamp `YYYYMMDDHHMM` at build time (overriding `project.yml`).
`CFBundleVersion` is Sparkle's sort key, so "newest build by wall-clock time
wins" — stable and beta are directly comparable, and a beta follower always
lands on whichever build is actually newest, regardless of channel.

A version with a pre-release suffix entered in the Release workflow
(`1.2.3-rc.1`) is honored as a manual beta escape hatch — it ships to the beta
channel as a pre-release — but the normal beta path is the nightly.

The app's Updates settings let users opt into beta; the updater's
`allowedChannels` adds `beta` accordingly. Beta items are tagged
`sparkle:channel=beta`; stable items carry no channel tag (Sparkle's default),
so stable users never see nightlies while beta users see both and pick the newest.

## Architectures & update feeds

We ship **one app per architecture — never a universal binary** (download
size; a post-build phase even thins the prebuilt fat Sparkle framework to the
built arch, see `scripts/thin-embedded-frameworks.sh`). Each architecture is
its own product line with its own Sparkle feed, and **cross-architecture
updates are unsupported by design**:

| Feed (gh-pages) | Architecture | Resolved by |
|---|---|---|
| `appcast.xml` | arm64 | `SUFeedURL` in Info.plist (the delegate returns `nil`) |
| `appcast-x86_64.xml` | x86_64 | `#if arch(x86_64)` in `UpdaterDelegate.feedURLString(for:)` |

The x86_64 feed choice is pinned **at compile time** in the binary itself, so
no build or CI misconfiguration can ever point an Intel app at the arm64 feed
(or vice versa).

**Backward-compatibility invariant:** `appcast.xml` is the URL baked into
every shipped arm64 build — including all releases that predate the x86_64
port, which were arm64-only — so it must keep serving **arm64-only entries
forever**. The workflow enforces this structurally: each arch has its own
`build/dist-<arch>/` scan root for `generate_appcast`, seeded from its own
gh-pages feed file, so a feed can only ever see its own architecture's
archive. Both channels (stable/beta) exist within each feed, exactly as
before.

Both apps of one release share the same version and date-stamped
`CFBundleVersion`; the two feeds never interact.

## One-time setup

### 1. Sparkle EdDSA keys

The **public** key is already committed in `Info.plist` (`SUPublicEDKey`). Export
the matching **private** key from the keychain (generated with Sparkle's
`generate_keys`) and store it as a CI secret:

```sh
# from the Sparkle artifact bin/ directory
./generate_keys -x eddsa_private.pem      # exports the private key
# paste the file contents into the SPARKLE_EDDSA_PRIVATE_KEY secret
```

> The public key in `Info.plist` and the private key in CI must be a matched
> pair. Regenerating one requires updating the other.

### 2. Developer ID certificate

Export the **Developer ID Application** certificate as a `.p12` and base64-encode it:

```sh
base64 -i DeveloperID.p12 | pbcopy   # → MACOS_CERTIFICATE
```

### 3. Notarization key

Create an App Store Connect API key (Developer ID notarization) and note the
key ID, issuer ID, and the `.p8` contents — they become `MACOS_NOTARIZATION_KEY`,
`MACOS_NOTARIZATION_KEY_ID`, and `MACOS_NOTARIZATION_ISSUER_ID`.

### 4. gh-pages branch

Create an empty `gh-pages` branch; the workflow publishes the feeds there —
`appcast.xml` (arm64, served at
`https://oomol-lab.github.io/LockIME/appcast.xml`, the `SUFeedURL`) and
`appcast-x86_64.xml` (x86_64, compiled into the Intel binary).

## Required GitHub secrets

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE` | base64 of the Developer ID `.p12` |
| `MACOS_CERTIFICATE_PWD` | password for the `.p12` |
| `APPLE_TEAM_ID` | `PWJ9VF7HHT` |
| `MACOS_NOTARIZATION_KEY` | contents of the App Store Connect `.p8` |
| `MACOS_NOTARIZATION_KEY_ID` | API key ID |
| `MACOS_NOTARIZATION_ISSUER_ID` | API issuer ID |
| `SPARKLE_EDDSA_PRIVATE_KEY` | exported Sparkle private key |
| `OOMOL_LAB_GITHUB_APP_CLIENT_ID` | Client ID of the org's GitHub App, used to mint the token that dispatches the Homebrew cask bump |
| `OOMOL_LAB_GITHUB_APP_PRIVATE_KEY` | private key (`.pem` contents) of that GitHub App |

## Cutting a release

1. Actions → **Release** → Run workflow. Optionally type the version
   (`1.2.3`); leave it empty to auto-bump the latest stable tag by the chosen
   segment (`patch` / `minor` / `major`). No file edit is ever needed —
   `project.yml` stays at `0.0.0-development`.
2. The workflow computes the version, builds, tests, then **for each
   architecture (arm64, x86_64)** archives (Developer ID, shared date-based
   build number), notarizes, staples, zips, runs `generate_appcast` on that
   arch's own dist dir (with `--channel beta` for pre-release versions), and
   builds and notarizes a `.dmg` from the stapled app. It then creates the
   `vX.Y.Z` tag on the built commit, publishes the GitHub Release with both
   zips **and** both dmgs, and updates `appcast.xml` + `appcast-x86_64.xml`
   on `gh-pages`.

The signing order is strict: **codesign → notarize → staple → (re)zip**. The
distribution zip is produced *after* stapling.

### Release notes

Sparkle shows the update window's release notes from the **appcast item**, not
from the GitHub Release body — the two are separate channels. Before
`generate_appcast` runs, the workflow generates the notes once
(`gh api …/releases/generate-notes` on the built commit) and stages the same
markdown into each arch's dist dir as
`build/dist-<arch>/LockIME-<version>-<arch>.md`. `generate_appcast` matches
that file to the zip by basename and embeds it inline as a CDATA
`<description sparkle:format="markdown">` (`--embed-release-notes` is required —
markdown notes are not auto-embedded the way HTML fragments are), so the notes
travel with the appcast and need no hosting. The update window renders that
markdown natively with its own parser — embedding **markdown, not a
pre-rendered HTML fragment**, which that view would show as raw tags. The same
file is reused verbatim as the GitHub Release `body`, so the Release page and the
update window can never disagree.

`generate-notes` lists **merged pull requests** under "What's Changed" —
commits pushed straight to the branch are invisible to it. The workflow
therefore always augments the generated body: every commit in
`git log <previous-tag>..HEAD` (the range is parsed from GitHub's own
"Full Changelog" compare link, so the two always cover the same diff) that no
merged PR introduced — asked per commit via the `/commits/{sha}/pulls` API, so
it stays correct even when a squash title drops its `(#N)` suffix — is appended
to the "What's Changed" section as a linked-hash bullet (the section is created
first for a PR-less release, whose generated body is just the "Full Changelog"
link). This is why the build checks out with `fetch-depth: 0` — the shallow
default has no tags or history to diff.

The `.dmg` (drag-to-`/Applications`, built by `scripts/make-dmg.sh`) is a
**manual-download convenience only** — Sparkle auto-updates still pull the zip,
because the appcast references the zip exclusively. The dmg is built into
`build/dmg/` (a directory `generate_appcast` never scans) *after* the appcast,
then signed, notarized, and stapled on its own. Run `make dmg` to build the
same image locally (unsigned/unnotarized; use `CONFIG=Release` for a
release-config bundle).

## Homebrew cask

LockIME is also installable via a custom tap
([`oomol-lab/homebrew-tap`](https://github.com/oomol-lab/homebrew-tap)):

```sh
brew install --cask oomol-lab/tap/lockime
```

The cask (`Casks/lockime.rb`) tracks the **stable channel only** and resolves
the per-architecture zip via `arch`/`sha256 arm:/intel:` — the same artifacts
Sparkle serves. It declares `auto_updates true` because the installed app
updates itself via Sparkle; `brew upgrade` therefore skips it unless run with
`--greedy`.

The bump is automated end to end: the last step of `build-publish.yml` sends
a `repository_dispatch` (event `lockime-release`, payload = version) to the
tap repo for every stable release — pre-releases never dispatch. The tap's `bump-lockime.yml` then downloads
both zips from the GitHub Release, recomputes their `sha256`, rewrites the
cask, and audits it (`brew style` + `brew audit --cask --online --strict`)
**before** pushing — its own push never triggers the tap's CI
(`GITHUB_TOKEN` pushes don't start workflows), so the audit guard lives in
the bump itself; the tap's CI covers manual pushes and PRs.

The dispatch authenticates as the org's **GitHub App** (the workflow's
`GITHUB_TOKEN` cannot reach other repos): `actions/create-github-app-token`
mints a 1-hour installation token from `OOMOL_LAB_GITHUB_APP_CLIENT_ID` +
`OOMOL_LAB_GITHUB_APP_PRIVATE_KEY`, scoped to `owner` + `repositories` =
just `homebrew-tap` (the App is installed on that repo only, with
Contents read/write). Manual fallback: run the tap's **Bump lockime**
workflow with the version.

## When a publish run fails

If a run fails **before** the "Tag & publish GitHub Release" step, nothing was
published — just re-run it (or dispatch again).

If it fails **after** the tag was created (e.g. the gh-pages step), prefer
**Re-run failed jobs**: the computed version is reused and the release step
updates the existing tag/release in place. A fresh dispatch with the *same
explicit version* also works as long as no new commits landed —
`compute_version.sh` allows an existing tag that points at the same commit and
re-publishes it. With auto-bump instead, the half-published tag would be
counted as the latest version and you would silently skip a number.

Do **not** re-run an old failed publish after a *newer* version has shipped:
the build number is stamped with the current time, so the re-run would sit on
top of the appcast and Sparkle would offer the older version as an "update".
Delete the stale tag/release and cut a new version instead.

## Testing the update flow locally

`make update-test-{none,download-fail,extract-fail,success}` exercises the full
in-app Sparkle pipeline (including install + relaunch) against a loopback feed
with a throwaway dev key — no production keys or `gh-pages` involved. See
`scripts/update-lab/README.md`.
