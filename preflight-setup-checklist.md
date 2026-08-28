# Pre-Flight Setup Checklist
### Mac mini (M1) → iOS + watchOS development, AlarmKit app

Ordered so the things with **external wait times** start first. Three items block on Apple, not on you — kick all three off on Day 1, then do the local work while they process.

---

## ⚠️ Read this before you start: two findings that shape the plan

**1. AlarmKit requires a managed entitlement from Apple.**

`com.apple.developer.alarmkit` is not a checkbox you enable — it's a *managed capability* that Apple must assign to your account after reviewing your use case. Without it, AlarmKit throws authorization errors on physical devices even when the user has granted permission.

This is why paying the $99 now is the right call: **you cannot request entitlements without a paid membership.** Your instinct was correct.

There is one complication. Developers have reported the AlarmKit capability not appearing in the Developer Portal for request, which blocked on-device testing while still working in the Simulator. That may be resolved by now — but treat it as **the single highest-risk unknown in your whole plan**, and find out on Day 1 rather than Week 3. Everything else on this list is routine; this one is not.

**2. AlarmKit is iOS-first, not native watchOS.**

Alarms are scheduled by your **iPhone** app, and the presentation is *forwarded* to the paired Watch. There is no native watchOS alarm scheduling API.

This simplifies v1 meaningfully — your primary target is an iPhone app, and the Watch piece is thinner than you were probably picturing. But it raises an open question worth answering early: **what actions the forwarded alarm presentation supports on the Watch.** Your whole completion-relative model depends on "Done" being distinct from "Dismiss" and tappable from the wrist. If the forwarded presentation only offers stop and snooze, that's a design constraint you want to discover now. See "Day 1 spikes" at the end.

---

## Phase 0 — Pre-flight checks (15 minutes)

Do these before downloading anything.

- [ ] **Storage.** System Settings → General → Storage. You need **40–50GB free**. Xcode is ~15–20GB, simulator runtimes several GB each, plus build artifacts. Clear space now — Xcode failing partway through on a full disk is a genuinely bad afternoon.
- [ ] **RAM.** Apple menu → About This Mac. 8GB works but will swap with Xcode plus simulators running; 16GB is comfortable. Not a blocker either way.
- [ ] **Current macOS version.** Same screen. Note what you're on.
- [ ] **Confirm iPhone and Watch are paired and both updated** to iOS 26 / watchOS 26 or later. AlarmKit doesn't exist below 26.

---

## Phase 1 — Start the long poles (Day 1, all in parallel)

### 1A. Apple Account prep (do this first — everything depends on it)

- [ ] Sign in at [account.apple.com](https://account.apple.com) with `kjspang@gmail.com`
- [ ] ⚠️ **Verify your first/last name fields contain your legal name.** Not a nickname, not a brand. Apple verifies identity against this, and a mismatch delays or fails enrollment.
- [ ] ⚠️ **Turn on two-factor authentication.** Enrollment will not proceed without it.
- [ ] Confirm you have a trusted device receiving 2FA codes

### 1B. Developer Program enrollment — $99 (starts a 24–48h clock)

- [ ] Install the **Apple Developer** app on your iPhone (free, App Store)
- [ ] Open it → Account tab → Enroll
- [ ] Select **Individual / Sole Proprietor**
- [ ] ⚠️ **Use the same device for the entire enrollment flow.** Switching between iPhone and Mac mid-process causes failures.
- [ ] Complete identity verification (needs Face ID / Touch ID / passcode enabled)
- [ ] Accept the Program License Agreement
- [ ] Pay $99 USD

Verification typically takes **24–48 hours** for individuals. Note that it auto-renews annually — set a calendar reminder if you'd rather have a decision point than a surprise charge.

### 1C. Update macOS (long, needs a restart)

- [ ] System Settings → General → Software Update
- [ ] Update to **macOS 26.2 (Tahoe) or later**

Xcode 26.4 requires macOS 26.2 as a minimum. Earlier Xcode 26 builds ran on Sequoia 15.6+, but there's no reason to start behind.

### 1D. Download Xcode (very long)

- [ ] Mac App Store → search "Xcode" → Install
- [ ] Start it and walk away — this is a multi-hour download on most connections

---

## Phase 2 — Request the AlarmKit entitlement (the moment enrollment clears)

**Do not defer this.** It's the item most likely to block you, and it may involve an Apple review turnaround.

- [ ] Sign in to [developer.apple.com/account](https://developer.apple.com/account)
- [ ] Go to **Certificates, Identifiers & Profiles → Identifiers** and create your App ID (e.g. `com.yourname.alerts`)
- [ ] Look for an **AlarmKit** capability in the App ID's capability list
- [ ] If present: enable it and request access, describing your use case (medication reminders and time-critical care schedules — this is a legitimate, alarm-shaped use case and should read well to a reviewer)
- [ ] If **not** present: check [Capability Requests](https://developer.apple.com/help/account/capabilities/capability-requests) and submit through that path. If neither route offers it, file a Developer Technical Support ticket and ask directly. Don't just wait and assume.

**Fallback if the entitlement isn't obtainable:** AlarmKit reportedly works in the Simulator with only `NSAlarmKitUsageDescription` in Info.plist. You can build and iterate on the whole app against the Simulator while the entitlement is pending — you just can't validate real-device Focus-piercing behavior, which is your core differentiator. Plan around that, don't be surprised by it.

---

## Phase 3 — Configure Xcode (after install completes)

- [ ] Launch Xcode once, accept the license, let it install additional components
- [ ] Install command line tools:
  ```bash
  xcode-select --install
  ```
- [ ] Point the toolchain at Xcode and verify:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  xcodebuild -version
  ```
- [ ] ⚠️ **Download simulator runtimes.** Xcode → Settings → **Components** → download **iOS** and **watchOS** runtimes.

  This is the gotcha that catches everyone on Xcode 26 — runtimes are no longer bundled. A fresh install can show *zero* simulators and look completely broken. It isn't.

- [ ] **Add your Apple Account:** Xcode → Settings → **Accounts** → `+` → Apple ID → sign in with `kjspang@gmail.com`
- [ ] Confirm your team appears (it will show as "Personal Team" until paid enrollment completes, then your name)

---

## Phase 4 — Device setup

### iPhone

- [ ] Connect to the Mac by cable for first setup
- [ ] Tap **Trust This Computer** when prompted, enter passcode
- [ ] Enable Developer Mode: **Settings → Privacy & Security → Developer Mode** → on → restart when prompted

  ⚠️ **Developer Mode only appears in Settings after Xcode has tried to talk to the device at least once.** If you don't see it, connect the phone and attempt a build first, then look again.

- [ ] In Xcode: **Window → Devices and Simulators** → select your iPhone → check **"Connect via network"** so you can deploy wirelessly afterward

### Apple Watch (Series 11)

- [ ] Enable Developer Mode on the Watch: **Settings → Privacy & Security → Developer Mode** → on → restart
- [ ] Confirm the Watch appears in Xcode's Devices and Simulators list

  Watch deployment happens over the paired iPhone and is **notoriously slow on first install** — several minutes is normal, not a failure. Keep the Watch on its charger and near the Mac during builds.

---

## Phase 5 — Supporting tools

- [ ] **Homebrew** (closest thing to the CLI workflow you're used to):
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
  Follow the post-install PATH instructions it prints — on Apple Silicon it installs to `/opt/homebrew`.

- [ ] **Git config:**
  ```bash
  git config --global user.name "Kevin Spang"
  git config --global user.email "kjspang@gmail.com"
  git config --global init.defaultBranch main
  ```

- [ ] **SSH key for GitHub:**
  ```bash
  ssh-keygen -t ed25519 -C "kjspang@gmail.com"
  cat ~/.ssh/id_ed25519.pub
  ```
  Add the printed key at github.com → Settings → SSH and GPG keys.

- [ ] **Create a private GitHub repo** for the project now, before there's anything in it. Commit from the first day.

- [ ] **SF Symbols app** — free from [developer.apple.com/sf-symbols](https://developer.apple.com/sf-symbols/). Apple's icon library; you'll use it constantly for UI.

- [ ] **Keep VS Code.** Still your tool for scripts, notes, and anything non-Swift.

### On your iPhone

- [ ] **TestFlight** (free, App Store) — you'll need it later for beta distribution
- [ ] **Huckleberry** and **Pump Log** — for the competitive validation test (see below)

---

## Phase 6 — Smoke test (prove it all works before writing real code)

Don't consider setup finished until all five pass.

- [ ] **New project builds.** Xcode → Create New Project → iOS App → SwiftUI. Build and run in the Simulator.
- [ ] **Deploys to real iPhone.** Same project, target your physical iPhone. This is where signing problems surface — turn on **"Automatically manage signing"** in the target's Signing & Capabilities tab and let Xcode sort it out.
- [ ] **Watch target builds.** Add a watchOS target to the project and deploy it to the Series 11.
- [ ] **⚠️ Haptic fires on the real Watch.** Put a button in the Watch app that calls:
  ```swift
  WKInterfaceDevice.current().play(.notification)
  ```
  Feel it on your wrist. **This is the single most important verification on the list** — it proves the toolchain, device pairing, and deployment path all work end to end for the thing your app actually does.
- [ ] **SwiftUI preview canvas renders.** Confirm previews work — that's your fast iteration loop, and a broken preview setup will slow you down badly.

---

## Day 1 spikes (small experiments, big answers)

Once the smoke test passes, these three answer your riskiest unknowns before you commit to a design:

1. **Can you get the AlarmKit entitlement?** Covered in Phase 2. Highest risk on the board.
2. **What actions does a forwarded alarm support on the Watch?** Schedule a trivial AlarmKit alarm, let it fire, and look at what the Watch presentation actually offers. Your Done-vs-Dismiss model depends on the answer.
3. **How many haptics are actually distinguishable?** Throwaway Watch app, one button per `WKHapticType`, wear it two days. My guess is three or four before they blur — and that number caps how many alert categories are worth building.

**And the zero-code one, tonight:** set a reminder in Huckleberry or Pump Log, turn on Sleep Focus, go to sleep. If it doesn't break through, your core wedge is confirmed for free.

---

## Realistic timeline

| Day | What happens |
|---|---|
| **Day 1** | Phase 0 checks, kick off enrollment, start macOS update and Xcode download. Mostly waiting. |
| **Day 2–3** | Enrollment clears. Request AlarmKit entitlement immediately. Configure Xcode, set up devices, install supporting tools. |
| **Day 3–4** | Smoke test. Run the three spikes. |
| **Day 4+** | Entitlement may still be pending — build against the Simulator meanwhile. |

---

## Sources

- [AlarmKit documentation](https://developer.apple.com/documentation/AlarmKit)
- [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit)
- [Wake up to the AlarmKit API — WWDC25](https://developer.apple.com/videos/play/wwdc2025/230/)
- [AlarmKit entitlement discussion — Apple Developer Forums](https://developer.apple.com/forums/thread/797950)
- [Capability requests](https://developer.apple.com/help/account/capabilities/capability-requests)
- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Enrolling with the Apple Developer app](https://developer.apple.com/help/account/membership/enrolling-in-the-app/)
- [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
