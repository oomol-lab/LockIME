# Security Policy

## Supported versions

LockIME ships as a self-updating app: every install keeps itself current via
[Sparkle](https://sparkle-project.org). Security fixes land in the **latest
release only** — there are no back-ported patch branches. If you are running an
older build, update before reporting (the menu-bar app checks automatically, or
use **Check for Updates…**).

| Version            | Supported          |
| ------------------ | ------------------ |
| Latest release     | :white_check_mark: |
| Anything older     | :x:                |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.** Disclose
privately so a fix can ship before the details are public.

Two private channels, either is fine:

- **GitHub Security Advisories** — open a private report at
  <https://github.com/oomol-lab/LockIME/security/advisories/new>
  (preferred; keeps the discussion and fix linked to the repo).
- **Email** — <bh@bugs.cc>. Feel free to encrypt or request a key first if you
  want to send sensitive details.

When you report, please include as much as you can:

- The LockIME version (menu bar → **About**) and your macOS version and CPU
  (Apple silicon / Intel).
- A description of the issue and its impact.
- Steps to reproduce, a proof of concept, or a crash log if you have one.
- Any relevant configuration (per-app or per-URL rules, enhanced/browser mode).

## What to expect

- **Acknowledgement** within 3 business days.
- An initial assessment and severity triage within 7 business days.
- Progress updates as we investigate, and credit in the release notes once a
  fix ships — unless you ask to stay anonymous.

We follow coordinated disclosure: please give us a reasonable window to release
a fix before disclosing publicly.

## Scope and notes

LockIME is a non-sandboxed macOS menu-bar app. Some behavior is by design and
generally **out of scope** unless you can show it crosses a real trust boundary:

- **Accessibility / Input Monitoring permissions.** The app needs these to read
  and switch the active input source. It does not log keystroke *content*; if
  you find it capturing or transmitting typed text, that is in scope.
- **`lockime://` URL scheme.** The app accepts URL-scheme commands (see
  `docs/URL-Scheme-API/`). Any input it accepts is fair game — report anything
  that lets a crafted URL exceed the documented API or affect other apps.
- **Sparkle auto-update.** Updates are delivered over HTTPS and verified with an
  EdDSA signature. Reports that defeat update authenticity or integrity (feed
  tampering, signature bypass, downgrade attacks) are high priority.
- **Local configuration files** (exported `.lockime` backups, app preferences):
  issues that let untrusted input escalate when imported are in scope.

Thanks for helping keep LockIME and its users safe.
