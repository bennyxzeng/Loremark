# Acceptance checks

Automated checks for the spec's device-level targets. They run a debug build
of the app on an Android emulator, driven from the host with `adb`. Normal
unit tests cover the pure parts of the harness (`test/acceptance/`); this page
is about the device run.

| Spec target | Check | Status |
|---|---|---|
| "Force-quit the app 20 times mid-chapter. The system should reopen within one page of the last position every time." | [Force-quit trials](#force-quit-trials) | automated |
| Reading must work offline | [Offline trial](#offline-trial) | automated |
| Privacy: no plaintext HTTP, no unexpected destination | [Privacy audit](#privacy-audit) | automated; the app makes no requests today |
| Privacy: no request contains a whole book or more than one chapter | not checkable from a capture | needs the LLM client, see [below](#what-the-privacy-audit-cannot-see-yet) |

Scalability (500,000-word book) and spoiler-safety audits are separate and
run without a device.

## What each check proves

### First run

Since PR #58 a fresh install opens on the "Connect an AI provider" screen
instead of the library, so every trial would wait for the book card and time
out. At the start of the session, before trial 0, the harness skips that
screen through the UI: it scrolls to "Skip for now", taps it, and confirms
"Skip for now" in the "Continue without AI?" dialog. It cannot seed this the
way it seeds the library, because the "seen" flag is in encrypted storage
(`flutter_secure_storage`) that `run-as` cannot write. Once is enough: the
flag survives `am force-stop`, `kill -9` and the seeder's file copies, and
nothing in a session clears the app's data. A build without the screen, or a
device that already skipped it, is unaffected: the harness sees the library
and carries on (the report notes when it did skip). The screen is found by
its text, not by position: "Connect an AI provider", "Skip for now" and
"Continue without AI?". Renaming any of them breaks the harness (issue #60,
CI-06).

### Force-quit trials

Each of the 20 trials (`--trials`):

1. Seeds a generated book and a random mid-chapter reading position into the
   app's private storage (`run-as`).
2. Launches the app. `LibraryScreen` reopens the last book by itself.
3. Taps **Next page** 1 to 8 times (`input tap` at the button's bounds from a
   `uiautomator dump`), waiting for the app to log each page.
4. Waits a random 0 to 300 ms, then kills the app: `am force-stop` on odd
   trials, `run-as ... kill -9` (SIGKILL) on even ones.
5. Reads the saved `reading_state/<id>.json`, relaunches, waits for the reader
   to settle, and compares.

"Within one page" is measured in Readium pages, not progression: the debug
build logs `LOREMARK_POSITION {"section":..,"progression":..,"currentPage":..,
"totalPages":..}` for every page shown (`positionLogLine` in
`lib/reader/readium_reader_service.dart`, compiled out of release builds). The
distance between the last page shown before the kill and the page after the
relaunch must be at most 1, counting turns across a chapter boundary
(`pageDistance` in `tool/acceptance/metrics.dart`). The saved file is checked
the same way. A trial 0 also taps the book in the library once, so the
"open from the library" path is covered too.

Proves: a SIGKILL or force-stop right after a page turn loses at most one
page, on this device size, font and book.

Does not prove: behaviour under real low-memory kills or a power cut, other
screen sizes or font settings, EPUBs with images, or iOS. The kill comes
after the page was logged, so a save that is slower than the 0 to 300 ms
window is only partly stressed.

### Offline trial

Airplane mode on (`cmd connectivity airplane-mode enable`, confirmed by the
setting and a failing ping), then: the book opens, three pages turn, a
force-stop and relaunch restore the position. Airplane mode is switched off
again in a `finally`, and also at the start of every run.

### Privacy audit

Two layers, because a capture alone cannot say which app sent a packet:

- **App UID counters (authoritative).** `dumpsys netstats detail` lists bytes
  per UID since boot. The harness reads the app's row before and after the
  whole session; the delta must be 0 bytes and 0 packets. An absent row means
  zero. This survives HTTPS, QUIC and ECH. Loopback is not counted, so
  Readium's in-process asset server does not show up. If the device prints no
  such table the check fails ("not measured") instead of passing.
- **Capture policy (`--pcap`).** With `emulator -tcpdump <file>`, the harness
  parses the capture in pure Dart (`tool/acceptance/pcap.dart`: Ethernet,
  IPv4/IPv6, TCP/UDP, DNS names, TLS SNI, HTTP) and checks the session window:
  - every DNS name, TLS server name and HTTP host is on the OS baseline or the
    allow-list (`--allow-host`, empty today). The baseline is a built-in list
    of what the emulator's Google services do on their own, plus whatever a
    control window recorded before the session with the app stopped
    (`--baseline-seconds`);
  - no plaintext HTTP (any port) except to baseline destinations;
  - no TLS or QUIC flow to a stranger without a readable name;
  - none of the marker phrases planted in each chapter appears in any packet;
  - nothing routable leaves the guest while airplane mode is on.

With PR #58 the app can contact api.openai.com or api.deepseek.com, but only
after the user saves a key. The harness never saves one, so the app must still
make no requests during a run.

Once a key is saved, theory checking (see [docs/theories.md](theories.md), part 2)
adds two expected request types to the same two hosts: a split request (the
theory text and its passage) and a check request (one finished section and the
open sub-theories). A debug recorder added later should expect both, and a
check request should never contain markers from the section in progress or any
later chapter. The harness still saves no key, so a run must still make none.

Proves: during the scripted session the app moved no bytes over the network,
and the capture shows no destination outside the baseline and allow-list.

Does not prove: anything about traffic the capture cannot read. QUIC and ECH
hide the server name, a TLS ClientHello split over several segments is
flagged rather than reassembled, and DNS over TLS is hidden (the harness turns
Private DNS off on emulators). The capture cannot tell the app's packets from
the OS's; that is what the UID counters are for.

#### What the privacy audit cannot see yet

The spec also says no request may contain a complete book or more than one
chapter of book text. Request bodies are TLS-encrypted, so a capture cannot
show that. The marker phrases are already planted for it. When the LLM client
exists, add a debug-only recorder that logs one `LOREMARK_REQUEST {host,
method, bytes, markers}` line per request (like `LOREMARK_POSITION`), and
make the harness assert on those lines and set `--allow-host` to the backend
and the AI service. The netstats delta then has to be greater than 0 only in
trials that make an AI call.

## Running it locally

Needs a debuggable build, so `flutter build apk --debug` (a release build
fails with `run-as: package not debuggable`). `--target-platform android-x64`
is much smaller than the default all-ABI APK; use `android-arm64` on an Apple
Silicon emulator.

### Windows (Git Bash)

```bash
export PATH="/c/Users/<you>/flutter/bin:$LOCALAPPDATA/Android/Sdk/platform-tools:$PATH"
flutter build apk --debug --target-platform android-x64

# Headless emulator with a capture. Two emulators of the same AVD cannot run
# at once, so stop your usual one first (or skip --pcap and use the running one).
"$LOCALAPPDATA/Android/Sdk/emulator/emulator" -avd loremark_api36 \
  -no-window -no-audio -no-snapshot -tcpdump "$TEMP/emulator.pcap" &
adb wait-for-device

dart run tool/acceptance/run.dart --pcap "$TEMP/emulator.pcap"
# add --serial emulator-5556 if several devices are attached
```

If you type `adb shell ls /data/...` yourself in Git Bash, set
`MSYS_NO_PATHCONV=1` first, or the path is rewritten to
`C:/Program Files/Git/data/...`. The harness sets it for its own `adb` calls.

### macOS

```bash
export PATH="$HOME/flutter/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
flutter build apk --debug --target-platform android-arm64   # android-x64 on Intel
"$HOME/Library/Android/sdk/emulator/emulator" -avd loremark_api36 \
  -no-window -no-audio -no-snapshot -tcpdump /tmp/emulator.pcap &
adb wait-for-device
dart run tool/acceptance/run.dart --pcap /tmp/emulator.pcap
```

`dart run tool/acceptance/run.dart --help` lists every option (trial count,
seed, report folder, allow-list, `--no-install`, `--skip-offline`).
A full run takes about 15 minutes; `--trials 3 --skip-offline` is a quick
smoke test. The same seed gives the same book and the same random choices.

The report lands in `build/acceptance/` as `report.json` and `report.md`, with
a copy of the capture. The exit code is 0 when everything passed, 1 when a
check failed, 2 when the harness could not run. A run with fewer than 20
trials is labelled INCOMPLETE.

On an emulator the harness also turns animations off (a running animation
makes `uiautomator dump` fail to reach an idle state) and Private DNS off,
and restores both afterwards. Pass `--prepare-device` to do the same on a
phone.

## CI

[`.github/workflows/acceptance.yml`](../.github/workflows/acceptance.yml)
builds the debug APK, starts an API 36 x86_64 google_apis emulator with
`-tcpdump` (`reactivecircus/android-emulator-runner`), runs the harness, appends
`report.md` to the job summary and uploads `build/acceptance` as the
`acceptance` artifact. It runs:

- manually (**Actions → Acceptance (device) → Run workflow**),
- every Monday 09:00 UTC,
- on pull requests that carry the `device-tests` label (add the label, or push
  to a labeled PR).

GitHub only starts `workflow_dispatch` and `schedule` runs for workflow files
on the default branch, so those two work once the file reaches `main`. The
label trigger works from a PR branch before that. It is separate from `ci.yml`
so the normal checks stay fast.

The workflow runs the harness with `--ci --capture-optional`. `--ci` makes the
run strict: at least 20 trials, the offline and privacy checks, and a capture
file, none of which may be skipped. `--capture-optional` changes one thing: a
capture that cannot be verified (the harness's DNS probe is not in it, or it
holds no packets) is reported as INCONCLUSIVE and no longer fails the job. It
does not weaken anything else: a failed force-quit trial, a failed offline
trial, any app traffic in the per-UID counters, or a capture that *was*
verified and shows a violation still fail the run. Without the flag, `--ci`
fails on an unverified capture, as it did before.

## Latest results

Local run, 2026-11-01, `loremark_api36`-style AVD (Android 16 / API 36,
x86_64, Windows 11 host), debug build, seed 403, a generated 12-chapter book:

| Check | Result |
|---|---|
| Force-quit, back within one page | **20 of 20** (10 `am force-stop`, 10 `kill -9`). 15 reopened on the exact page; 5 on the exact page the reader last saw while the saved file was one page behind, which the one-page rule allows |
| Open the book from the library | pass |
| Offline reading (airplane mode) | pass: opened and turned 3 pages with airplane mode on, then reopened in place after a force-stop |
| App network traffic | pass: the app's UID sent and received **0 bytes** over the whole session |
| Capture policy | **inconclusive** on this Windows host: the emulator's `-tcpdump` file did not contain the harness's DNS probe lookups, so it could not be shown to cover the session (see below) |

GitHub Actions (ubuntu-latest emulator, API 36), same seed: 20 of 20 reopened
within one page, 19 on the exact page. In trial 7 the app was killed while the
last page turn was still being saved and reopened one page early. Offline and
app traffic passed; the capture was inconclusive there too.

GitHub Actions again, 2026-11-03 (run 41584263390, 21 minutes, with
`--capture-optional`): force-quit **20 of 20**, open from the library pass,
offline pass, app traffic **0 bytes**, capture **inconclusive** (see below). The
job passed.

Each force-quit trial takes 20 to 30 seconds, so the full run is about 12
minutes.

### Why the capture is reported as inconclusive

The harness only trusts a capture after it finds two unique DNS lookups it
makes just before and just after the session. They also calibrate the
capture's clock: on Windows the emulator stamps packets with local time as if
it were UTC, an eight-hour offset here. On this host the probe lookups never
appeared in the capture (other OS lookups did), so the capture result is
INCONCLUSIVE: it neither passes nor fails the run, and the per-UID counters
above stay the gate.

**On CI it was inconclusive too, and used to fail the job.** In the GitHub run
that made PR #11 red, every real check passed (20 of 20 force-quits, offline,
open-from-library, 0 bytes of app traffic, and the report's own `pass` was
true). The job failed only because `--ci` treated the unverified capture as a
failure. That is why CI now passes `--capture-optional`.

**What that does and does not mean for privacy.** Today the app makes no
network requests, and the per-UID counters measure exactly that: 0 bytes sent
and received by the app during the whole session. That is the evidence for
"no unexpected traffic". The capture was meant to add two things the counters
cannot: which hosts, and whether a request carries a whole book or more than
one chapter. Neither matters until the app makes a request, so an unverified
capture loses nothing today. **Once the app makes any request, the counters
stop being enough: remove `--capture-optional` from the workflow and get the
capture to verify first.**

**Finding the cause.** The probe is `ping -c 1` on a unique name, run over adb,
and the harness expects the resulting DNS question in the emulator's capture.
The harness now always keeps the raw capture as `emulator.pcap` in the report
folder (it used to skip it exactly when the probe was missing), and its note
says what the capture held: the packet count, the link type and the distinct
DNS names it saw.

That answered the first question. In CI run 41584263390 the capture held 177
packets over 714.1 s (Ethernet, link type 1) and 3 distinct DNS questions:
`connectivitycheck.gstatic.com`, `www.google.com` and `mtalk.google.com`. So the
capture works and spans the whole session; it records the operating system's own
lookups. What never appears is the harness's probe. **The fault is in the probe,
not in the capture.**

Still unknown is why the probe does not reach the wire: whether the shell's
`ping` resolves the name in a way the emulator does not capture, or Android's
resolver stops the lookup before sending it. The next step is to replace the
`ping` probe with a lookup that is known to appear in the capture, check it on
both the Windows host and the CI emulator, and then remove `--capture-optional`
from the workflow. Until that is done the capture proves nothing, and the
per-UID counters are the privacy evidence.
