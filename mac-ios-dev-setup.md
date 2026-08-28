# Mac mini (M1) → iOS/watchOS Development Setup

Written for someone coming from Python / VS Code / Snowflake. Target: a SwiftUI iOS + watchOS app using AlarmKit and SwiftData.

---

## Part 1 — The email question (answer first)

**Use a separate email, but understand what it does and doesn't buy you.**

Create a new Apple Account with a dedicated address (e.g. a fresh Gmail, or better, `dev@yourdomain.com` if you ever plan to own a domain — that's portable in a way a Gmail address isn't).

**What a separate account gets you:**

- **Clean inbox separation.** A developer account generates a real volume of mail: agreement updates, review status, sales reports, certificate expiry warnings. You don't want that mixed with personal mail.
- **Transferability.** If you ever sell the app, bring on a co-founder, or hand off maintenance, you're transferring a purpose-built account — not your personal Apple Account with your photos, purchases, and iCloud data attached to it.
- **Future-proofing.** If you later form an LLC, your developer identity isn't tangled up with your personal Apple ecosystem.

**What it does NOT get you: anonymity.**

Apple verifies your identity for Individual enrollment, and your Apple Account's first/last name fields must contain your **legal name**. Using an alias or company name there will delay or fail approval. A separate email separates your *mail and ownership*, not your identity.

**The decision that actually matters more than email:**

Individual enrollment publishes **your legal name** as the seller on your App Store listing. Not a brand name — "Kevin Spang."

If you want a company name shown instead, that requires **Organization** enrollment, which needs a real legal entity (LLC or similar) and a D-U-N-S number.

⚠️ **You cannot convert an Individual account to an Organization account later.** You would have to enroll separately and transfer the apps across. It's doable but annoying.

**Recommendation:** Enroll as an Individual now. For a first app, your legal name on the listing is a non-issue, and forming an LLC before you know the app works is premature optimization. Just go in knowing that if this becomes a real business, there's a migration step.

**Practical note that removes most of the friction:** you do **not** need to sign into your Mac, iPhone, or Watch with the developer Apple Account. Xcode lets you add a developer account independently of your system Apple Account (Xcode → Settings → Accounts). So a separate account costs you nothing in daily use.

Avoid plus-addressing (`kjspang+dev@gmail.com`) — Apple's account system handles it inconsistently. Use a genuinely separate address.

---

## Part 2 — Your hardware

**M1 Mac mini: fully supported.** All Apple Silicon Macs run macOS 26 (Tahoe), and Xcode 26 runs natively.

Two things to check before you start:

**Storage.** The base M1 mini shipped with 256GB. Xcode is roughly 15–20GB, and each simulator runtime (iOS, watchOS) is several GB more. Budget **40–50GB** for a full setup. If you're near the limit, clear space first — Xcode failing mid-install on a full disk is a bad afternoon.

**RAM.** The M1 mini came in 8GB and 16GB. 8GB works, but running Xcode plus an iPhone simulator plus a Watch simulator simultaneously will push into swap and feel sluggish. Not a blocker — just expect it, and prefer testing on real hardware where you can.

To check both: **Apple menu → About This Mac** (RAM), and **System Settings → General → Storage**.

---

## Part 3 — Mac setup

### Step 1: Update macOS

**System Settings → General → Software Update.** Get to macOS 26.2 or later.

This matters: Xcode 26.4 requires macOS Tahoe 26.2 as a minimum. Older Xcode 26 releases ran on Sequoia 15.6+, but there's no reason to start behind.

### Step 2: Install Xcode

Mac App Store → search "Xcode" → Install. It's large and slow; start it and go do something else.

*(Alternative: download from developer.apple.com/download if you ever need a specific version. The App Store is fine for now.)*

### Step 3: Command line tools

Open Terminal:

```bash
xcode-select --install
```

Then confirm Xcode is the active toolchain:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

### Step 4: Install simulator runtimes ⚠️

**This is the gotcha that catches everyone on Xcode 26.** Simulator runtimes are no longer bundled with Xcode — they're separate downloads. A fresh Xcode install can show *no simulators at all*, which looks like a broken install but isn't.

**Xcode → Settings → Components** → download the **iOS** and **watchOS** simulator runtimes.

### Step 5: Accept the license and launch once

Open Xcode, accept the license agreement, and let it finish installing additional components on first launch.

### Step 6: Homebrew (optional, but you'll want it)

You're coming from a Python/CLI world; Homebrew is the closest thing to what you're used to.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the post-install instructions it prints — on Apple Silicon it installs to `/opt/homebrew` and you need to add it to your PATH.

### Step 7: Git

Git ships with the command line tools. Just configure it:

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
git config --global init.defaultBranch main
```

### Step 8: Keep VS Code

Don't uninstall it. You'll still use it for scripts, notes, config, and anything non-Swift. Some people also use it (or Cursor) for Swift editing and switch to Xcode to build — reasonable, though Xcode 26 has Claude integrated directly now, so the gap is smaller than it used to be.

---

## Part 4 — Apple Developer Program

### Do you need to pay $99 right now? No.

A **free** Apple Account lets you build and run apps on your own physical devices. The limitation is that provisioning profiles expire after **7 days**, so you re-deploy from Xcode weekly. For early development that's entirely workable.

**Enroll in the paid program when you need:**

- TestFlight distribution (letting anyone else test)
- App Store submission
- Provisioning that doesn't expire every 7 days
- Certain entitlements and capabilities

**Suggested sequencing:** start free, get something running on your own Watch, confirm the concept works. Enroll once you're confident you're actually shipping. No reason to start the annual clock early.

### Enrollment steps (when you're ready)

1. **Create the Apple Account** at [account.apple.com](https://account.apple.com) with your dedicated email.
   - ⚠️ Use your **legal name** in the first/last name fields. Aliases and company names cause delays or rejection.
2. **Turn on two-factor authentication.** Required — enrollment will not proceed without it.
3. **Enroll via the Apple Developer app** (iPhone/iPad, or Mac). Web enrollment exists, but the app path is smoother for individuals and Apple steers you there.
   - You need a device with Touch ID, Face ID, or a passcode enabled — or a Mac with Apple Silicon / T2 chip.
   - ⚠️ **Use the same device for the entire enrollment process.** Switching mid-flow causes failures.
4. **Select Individual / Sole Proprietor** (see Part 1 for the Individual vs. Organization tradeoff).
5. **Identity verification** — typically 24–48 hours for individuals.
6. **Pay the $99 USD annual fee** once verified and you've accepted the license agreement.

Note that it auto-renews annually. Set a calendar reminder if you want a decision point rather than a surprise charge.

---

## Part 5 — What's different coming from Python / VS Code

**Projects, not folders.** Xcode uses a project file that tracks membership explicitly. Dropping a `.swift` file into the directory doesn't add it to the build the way adding a `.py` file to a package would. Add files through Xcode.

**No dependency manager needed for v1.** Your app needs zero third-party packages — AlarmKit, SwiftData, SwiftUI, and WatchConnectivity are all first-party. If you ever need a dependency, it's Swift Package Manager, built into Xcode. There's no `requirements.txt` step to worry about.

**SwiftUI previews are your REPL.** The fast iteration loop is the preview canvas, not build-and-run. Coming from a notebook/REPL workflow, this is the closest analog and it's worth learning early.

**Signing and provisioning is the genuinely confusing part.** It's the one piece with no equivalent in your background. Turn on **"Automatically manage signing"** in your target settings and let Xcode handle it. Don't go down the manual certificate rabbit hole until something forces you to.

**Compiled and statically typed.** Coming from Python, expect the compiler to reject things Python would have let you find at runtime. This is a feature, but the error messages — especially in SwiftUI view bodies — can be genuinely misleading. When you get an incomprehensible type error in a view, the cause is usually a few lines away from where it's reported.

---

## ⚠️ Part 6 — The hardware requirement specific to your app

**You cannot test haptics in the Simulator.** There is no way to feel a `WKInterfaceDevice.play()` call on a simulated Watch.

For an app whose entire value proposition is wrist alerts that people can distinguish and won't miss, this means:

- **A physical Apple Watch is not optional** — it's the primary development instrument.
- **A physical iPhone is required too**, since the Watch must be paired to one.
- AlarmKit behavior you care about most — breaking through Silent mode and Sleep Focus — is also only meaningfully testable on real hardware.

If you have a Watch and iPhone already, you're set. If not, factor that into the plan before writing code, because the parts of this app you most need to validate are exactly the parts the Simulator can't show you.

---

## Setup checklist

- [ ] Check storage (need 40–50GB free) and RAM
- [ ] Update macOS to 26.2+
- [ ] Install Xcode from the Mac App Store
- [ ] `xcode-select --install`
- [ ] Download iOS + watchOS simulator runtimes (Xcode → Settings → Components)
- [ ] Launch Xcode, accept license, let components install
- [ ] Install Homebrew (optional)
- [ ] Configure git
- [ ] Create a dedicated Apple Account with a separate email + 2FA
- [ ] Add that account to Xcode (Settings → Accounts)
- [ ] Build a hello-world app to your physical iPhone with the free account
- [ ] Confirm you have an Apple Watch for haptic testing
- [ ] *(Later)* Enroll in the Apple Developer Program when you're ready to ship

---

## Sources

- [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
- [Xcode 26.1 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_1-release-notes)
- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Enrolling with the Apple Developer app](https://developer.apple.com/help/account/membership/enrolling-in-the-app/)
- [Apple Developer Program — Become a member](https://developer.apple.com/programs/enroll/)
