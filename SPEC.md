# Alerts — v1 Project Specification

> **How to use this file:** drop it in your repo root as `SPEC.md`. If you want Claude Code to pick it up automatically as standing project context, copy the Constraints and Data Model sections into a `CLAUDE.md` at the repo root — Claude Code reads that file on every session without being asked.

---

## 1. Project identity

| | |
|---|---|
| **Bundle ID** | `com.kjspang.alerts` |
| **Team ID** | `9ZWWS632X4` |
| **Platforms** | iOS (primary), watchOS (companion). **No visionOS, no macOS.** |
| **Minimum OS** | iOS 26 / watchOS 26 (AlarmKit does not exist below 26) |
| **UI** | SwiftUI |
| **Persistence** | SwiftData, local only |
| **Backend** | None |
| **Dependencies** | None. Everything needed is first-party. |

---

## 2. What the app is

A reminder app whose alerts are **alarm-grade** rather than notification-grade, supporting two scheduling models in one place:

- **Fixed** — "8:00am every day." Medication, feeding the dog, anything anchored to the clock.
- **Completion-relative** — "3 hours after I last did it." Feeding, pumping, PT exercises, eye drops, anything anchored to the last actual occurrence.

The differentiator is not a custom haptic vocabulary (see Constraints — that isn't possible). It is:

1. **Alarm-grade delivery.** Alerts break through Silent mode and Focus, including Sleep Focus. Ordinary reminder apps use notifications, which are suppressed exactly when they matter most.
2. **Completion-relative recurrence at intraday granularity.** Clock does fixed alarms and countdown timers. Reminders does fixed. Task managers do repeat-from-completion at *day* granularity, delivered as notifications. Nothing does hour-scale, completion-anchored, alarm-grade.

---

## 3. Platform constraints — read before designing anything

These were established through research and are **not** negotiable. Do not design around capabilities that don't exist.

### 3.1 Custom haptic patterns cannot fire in the background

`WKInterfaceDevice.play()` has no effect when the app is inactive or backgrounded.

**Consequence:** there is no way to author a "haptic language" where distinct buzz patterns identify distinct reminders while the app is closed. Arbitrary haptic sequences work only in the foreground.

**Correction to earlier drafts:** the workout session is *not* the only exemption. `WKExtendedRuntimeSession` with the smart-alarm type also runs in the background, and its `notifyUser(hapticType:repeatHandler:)` lets the repeat handler change the haptic type on each repetition — a genuine app-authored haptic sequence while backgrounded. It is nonetheless **not a viable foundation for this app**:

- Only **one session may be scheduled at a time**, so multiple pending reminders cannot each hold one.
- `startAtDate:` **must be called while the watchOS app is foreground-active**, so a completion-relative reminder cannot re-arm itself after Done without the user opening the Watch app.
- Sessions cannot be scheduled more than **36 hours** in advance (`scheduledTooFarInAdvance`).
- The user must make the app the **default responder** for the session type (`AutoLaunchAuthorizationStatus`).

**On sound-paired haptics — tested, and the answer is no.** Earlier drafts claimed differentiation "comes from AlarmKit's sound-paired system alerts." Tested on device with two custom sounds built to differ in rhythm (one sustained tone vs. three fast pips):

| | iPhone | Apple Watch |
|---|---|---|
| Custom `AlertSound.named(_:)` | ✅ plays, clearly distinguishable | ❌ substitutes the standard alarm ping |

**Custom AlarmKit sounds are an iPhone-only channel.** The forwarded Watch presentation ignores them. Apple's "each sound has a synchronized haptic pattern" line refers to the built-in sounds a user chooses in Settings, not to sound files a third-party app ships.

⚠️ *On the haptics feeling "somewhat different" in that test:* discount it. The Watch played the **same** ping for both sounds, so there was no mechanism to produce a haptic difference, and the tester knew which sound was scheduled — the test was not blind. Any real difference must be demonstrated blind (`HapticLab Watch App` exists for exactly this) before a design depends on it.

**Planning consequence:** assume the number of distinct *alerting* identities a shipped build can deliver is very small — plausibly one — until proven otherwise. This does not threaten the product thesis, because per §2 the differentiator is alarm-grade delivery and completion-relative recurrence, **not** a haptic vocabulary.

### 3.2 AlarmKit is iOS-first, not native watchOS

Alarms are scheduled by the **iPhone** app. The presentation is *forwarded* to the paired Watch. There is no watchOS alarm scheduling API.

**Consequence:** the iPhone app is the primary target. The Watch target is thin.

### 3.3 There is a system-enforced alarm ceiling

AlarmKit publishes no fixed maximum, but the system imposes a resource-dependent limit and returns `maximumLimitReached` when exceeded.

**Consequence:** the rolling-window scheduler in §6 is mandatory architecture, not an optimization. Do not attempt to materialize every future occurrence.

### 3.4 Notifications are not a fallback

If an alert degrades to `UNNotification`, it loses Focus-piercing delivery — which is the entire product thesis. Notifications may be used for genuinely ambient nudges, but never as a silent fallback for a missed alarm.

### 3.5 ✅ Resolved: there is no AlarmKit entitlement

Earlier drafts of this spec claimed `com.apple.developer.alarmkit` was a managed entitlement requiring Apple approval, citing a Developer Forums thread about it not appearing in the Developer Portal. **That entitlement does not exist.** The forum thread in question ([developer.apple.com/forums/thread/797950](https://developer.apple.com/forums/thread/797950)) concluded that the entitlement was an LLM hallucination — the reporting developer had added a fabricated `com.apple.developer.alarmkit` key to their entitlements file, and the build succeeded immediately once it was removed. An Apple engineer confirmed the pattern on the thread.

Apple's own AlarmKit sample documentation ([Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit)) confirms the real, complete setup requirement:

1. Add the `NSAlarmKitUsageDescription` key to Info.plist with a descriptive string (shown in the system authorization prompt).
2. Call `AlarmManager.requestAuthorization()` at runtime, or let AlarmKit auto-prompt on first alarm creation.

No Developer Portal capability, no capability request, no Apple review, no waiting period. This works on a normal signed build to a physical device with a free or paid account alike.

### 3.6 ✅ Resolved: forwarded alarm actions on the Watch

Verified empirically on an iPhone 14 Pro + Apple Watch Series 11 (iOS/watchOS 26) with the spike in `AlarmKitSpike.swift`. **The Done-vs-Dismiss model in §5 is viable.**

Findings:

1. **The custom secondary button does forward to the Watch.** The alert presented on the wrist showed two stacked buttons — a custom **Done** and the system **Stop**. A one-tap Done from the Watch is achievable, so §7's most important interaction is not blocked.
2. **The alarm fires on both the iPhone and the Watch simultaneously**, not on one or the other.
3. ⚠️ **`secondaryButtonBehavior: .custom` does not stop the alarm.** The system hands control to your intent and does nothing else. In the first spike run, tapping Done on the Watch silenced only the Watch — **the iPhone kept alarming** — because the intent didn't stop it. The custom intent must call `AlarmManager.shared.stop(id:)` itself.
4. **The system Stop button does stop the alarm on both devices** automatically; its `stopIntent` is a notification hook, not the thing performing the stop.

**Consequence for §5:** the completion path must always stop the alarm explicitly inside the Done intent. Forgetting this produces the worst possible failure — a "resolved" reminder that keeps screaming on the phone in another room.

### 3.7 Build requirement: Info.plist keys must be in a real Info.plist

`NSAlarmKitUsageDescription` is mandatory — without it AlarmKit refuses to schedule anything, failing with `Error Domain=com.apple.AlarmKit.Alarm Code=1`.

⚠️ Setting it via Xcode's `INFOPLIST_KEY_NSAlarmKitUsageDescription` build setting **silently does nothing.** That shortcut only maps an allowlist of recognized keys, and this one isn't on it, so it never reaches the built plist and there is no warning. The project uses a real `Info.plist` at the repo root via `INFOPLIST_FILE`; verify keys landed with `plutil -p "<built>.app/Info.plist"` rather than trusting build settings.

`NSSupportsLiveActivities` is also set, since `AlarmAttributes` conforms to `ActivityKit.ActivityAttributes` and the alarm presentation is backed by a Live Activity.

---

### 3.8 Delivery routing and a known AlarmKit non-fire

**Watch vs. iPhone routing is the system's call, not ours.** If the iPhone is unlocked and in use, the alert presents there and the Watch is skipped; if the iPhone is locked or asleep and the Watch is unlocked and on the wrist, the Watch gets it. There is no setting to force both, and none is needed — the target scenario (phone on the nightstand, 3am) is the locked case where the Watch wins.

*Testing note:* lock the phone before a test alarm fires, or you will only ever see the iPhone presentation.

⚠️ **Known bug: alarms may silently fail to present when an app is foregrounded in landscape.** Reported against the stock Reminders app and Apple's own AlarmKit sample; the Clock app is unaffected. The reported workaround is to give every alarm a **1-second `preAlert`**. For this app a silent non-fire is the worst failure mode that exists, so treat this as a reliability requirement, verify it on device, and add a regression test around it rather than trusting the workaround indefinitely.

---

## 4. Data model

The central design decision: **separate the rule from the instance.** A `Reminder` is a rule. A `ScheduledOccurrence` is a materialized future firing mapped to an AlarmKit alarm. This split is what makes rolling-window scheduling and reconciliation tractable.

```swift
@Model
final class Reminder {
    var id: UUID
    var title: String
    var note: String?                 // v2 payload: "two blue pills"
    var categoryID: UUID              // → AlertCategory
    var schedule: ScheduleType
    var isEnabled: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var completions: [CompletionEvent]
}

enum ScheduleType: Codable {
    /// Anchored to the clock. Deferral does NOT move future occurrences.
    case fixed(times: [DateComponents], weekdays: Set<Int>)

    /// Anchored to last completion. Deferral DOES move the anchor.
    /// `anchorReset` optionally re-baselines daily to prevent unbounded drift.
    case relativeToCompletion(interval: TimeInterval, anchorReset: DateComponents?)

    /// Single firing, then done.
    case oneOff(date: Date)
}

@Model
final class AlertCategory {
    var id: UUID
    var name: String                  // "Medication", "Feeding", "Pets"
    var soundID: String               // Auto-assigned, never user-chosen (§7.1)
    var symbolName: String            // SF Symbol
    var colorHex: String
}

@Model
final class CompletionEvent {
    var id: UUID
    var reminderID: UUID
    var scheduledFor: Date            // when it was supposed to fire
    var resolvedAt: Date              // when the user acted
    var action: CompletionAction
    var payload: Data?                // v2: ounces, dose taken. nil in v1.
}

enum CompletionAction: String, Codable {
    case done, skipped, deferred, dismissed
}

@Model
final class ScheduledOccurrence {
    var id: UUID
    var reminderID: UUID
    var fireAt: Date
    var alarmKitID: UUID?             // nil until successfully scheduled
    var state: OccurrenceState
}

enum OccurrenceState: String, Codable {
    case pending, scheduled, fired, resolved, orphaned
}
```

**Note the `payload: Data?` field.** v1 always writes `nil`. It exists now so that adding "4 oz" or "2 tablets" in v2 doesn't require touching the completion path everywhere.

### 4.1 ⚠️ SwiftData cannot store `ScheduleType` directly

`ScheduleType` is an enum with associated values carrying collections (`[DateComponents]`, `Set<Int>`). Declaring it as a stored `@Model` property **compiles and installs cleanly, then traps inside `ModelContainer` on the first SwiftUI view update.** Verified by bisection: direct property crashes, JSON-encoded `Data` with a computed accessor does not.

`Reminder` therefore stores `scheduleData: Data` and exposes `schedule` as a computed property. Nothing queries on schedule contents, so losing predicate support costs nothing.

The `#Index` macro was also dropped — it was speculative and nothing measured needed it.

**The trap to remember:** an invalid SwiftData schema is not a build error. It builds, signs, installs, and launches, then dies inside the first view update — and it takes the *unit test host* down with it, so unit tests report "crashed before establishing connection" rather than a useful failure. `LaunchSmokeTests` exists to catch exactly this, and any new `@Model` property type should be verified by running it rather than by a successful build.

*Debugging note:* `xcrun simctl launch` returns a PID as soon as the process spawns, so a returned PID does **not** mean the app survived. Sleep, then check `launchctl list`.

---

## 5. Scheduling and deferral logic

This is the core of the app. Get it right.

### 5.1 Next-fire calculation

| Schedule | Next fire computed as |
|---|---|
| `fixed` | Next matching time/weekday from now |
| `relativeToCompletion` | `lastCompletion + interval` (falls back to `createdAt` if never completed) |
| `oneOff` | The specified date; no successor |

### 5.2 Action semantics — the critical table

| User action | Fixed | Completion-relative |
|---|---|---|
| **Done** | Log `.done`. Next = next clock slot. | Log `.done`. **Next = now + interval.** Anchor moves. |
| **Defer / Snooze** | Re-fire in N minutes. Future occurrences unchanged. | Re-fire in N minutes. **Anchor does not move until Done.** |
| **Skip** | Log `.skipped`. Next = next clock slot. | Log `.skipped`. Next = now + interval (treat as anchor). |
| **Dismiss** | Log `.dismissed`. Next = next clock slot. | ⚠️ **Ambiguous — needs a product decision.** |

**On the ambiguity:** if a user dismisses a relative alarm without marking it done, did the activity happen? Recommended v1 behavior — treat dismissal as *not done*, leave the anchor untouched, and re-fire after a short grace period. Do not silently advance the schedule, because that quietly breaks the user's cadence with no signal.

### 5.3 Drift control

Relative schedules drift forward across the day by design — that is correct for feeding. But some alerts need a daily re-baseline or they walk off the schedule entirely over a week.

`anchorReset` on `relativeToCompletion` handles this: if set, the anchor resets to that time-of-day each day regardless of the last completion.

### 5.4 Done vs. Dismiss must be distinct affordances

For a fixed alarm, nobody cares which one the user hit. For a relative alarm, **the entire next fire time depends on the answer.** The alarm's presentation cannot offer only "stop."

✅ **Verified achievable — see §3.6.** The Watch presents a custom **Done** button alongside the system **Stop**, so the two actions are distinguishable from the wrist.

Implementation requirements that follow from the spike:

- **Done** is the custom secondary button (`secondaryButtonBehavior: .custom`) backed by a `LiveActivityIntent`. That intent **must call `AlarmManager.shared.stop(id:)` itself** — the system will not, and the iPhone keeps alarming if it's omitted. Log `.done` and re-anchor in the same intent.
- **Stop** is the system-provided button. It stops the alarm on both devices on its own; its `stopIntent` is where `.dismissed` gets logged and the §5.2 dismissal policy applies.
- The custom-labeled `stopButton` API is deprecated — the system owns that button's appearance. The secondary button is the only label you control, so **"Done" must be the secondary.**

---

## 6. The rolling-window scheduler

Mandatory, per §3.3.

**Rules:**

1. Materialize `ScheduledOccurrence` rows only for the **next 24–36 hours**.
2. Register each with AlarmKit and store the returned `alarmKitID`.
3. Top up the window as alarms fire and resolve.
4. On `maximumLimitReached`, shrink the window and retry rather than failing outward. Surface a warning if the user's configuration genuinely can't fit.
5. Treat the schedule as something you **rebuild**, not mutate. Reconciliation should be idempotent.

### 6.1 Only one relative occurrence is knowable

A `fixed` schedule is clock-anchored, so every firing inside the window can be materialized now. A `relativeToCompletion` schedule **can only ever materialize its next single occurrence**: the one after it depends on when the user actually completes this one, which hasn't happened. Materializing a second would be inventing a completion time and would fire an alarm at a moment the user never earned.

This is load-bearing for capacity too — relative reminders cost exactly one alarm each, no matter how short their interval.

### 6.2 ⚠️ The 1-second `preAlert` workaround is not implemented

§3.8 records a reported bug where alarms silently fail to present while an app is foregrounded in landscape, with a 1-second `preAlert` as the workaround. That is **not** implemented, deliberately: `preAlert` requires `Alarm.CountdownDuration`, which puts the alarm into a countdown presentation, and Apple's documentation states an app supporting countdown **must** ship a widget extension or "the system may unexpectedly dismiss alarms and fail to alert."

Trading a landscape-only non-fire for a possible all-orientations non-fire is a bad trade on unverified ground. The current code uses the `.alarm()` configuration verified working on device in the §3.6 spike. **Revisit once a widget extension exists**, and verify both paths on hardware before adopting it.

**Reconcile on:**

- App foreground (always — you cannot trust background execution)
- Any reminder create / update / delete
- Any completion event
- Any alarm firing

**Reconciliation algorithm:**

```
1. Compute the desired set of occurrences for [now, now + window]
2. Diff against ScheduledOccurrence rows currently marked .scheduled
3. Cancel AlarmKit alarms present in stored state but absent from desired
4. Schedule AlarmKit alarms present in desired but absent from stored
5. Mark any occurrence whose alarmKitID no longer resolves as .orphaned
```

---

## 7. UX requirements

**The design constraint: one thumb, 3am, holding a baby.** Every interaction must survive that test. If it needs two hands or visual precision, it's wrong.

- **Done must be reachable from the Watch in one tap.** This is the single most important interaction in the app.
- **Never require the phone** to resolve an alert.
- **No keyboard at alert time.** When v2 payload capture arrives, use preset chips (2 / 3 / 4 / 5 oz) with a rare manual fallback.
### 7.1 Alert identity is assigned, never chosen

**Design for one reliably distinct alerting identity.** Earlier drafts assumed 3–4 and told the user to pick from them. Both halves of that are now wrong (§3.1): there is no supported way for a third-party app to play an app-authored haptic sequence on a Focus-piercing alert, so the number of *feelable* identities a shipped build can deliver may be exactly one.

Rules that follow:

- **A custom sound picker is defensible — but it is an iPhone-only feature.** Testing (§3.1) confirms custom sounds play on the iPhone and are ignored by the Watch. If a picker ships, it must be described honestly as an iPhone alert sound. Never imply it changes anything on the wrist.
- **Never put a haptic picker in the UI.** Not at reminder creation, not in category settings, not anywhere. There is no supported way to honour it.
- **Auto-assign** an identity to each category from a fixed internal table when the category is created. If richer differentiation later proves deliverable, categories pick it up with no data migration and no user action.
- **Category distinction is carried visually**, on the alert itself: title, SF Symbol, tint colour. Those are reliable today and cost nothing.
- **Do not market or imply a haptic vocabulary.** A user told they can identify reminders by feel will notice quickly that they can't. This is the failure mode most likely to produce bad reviews, and it is entirely self-inflicted.

**The asymmetry that matters:** sound differentiation lands on the iPhone, but §7 says Done must be reachable from the Watch and the phone must never be required. So the device that can carry alert identity is the device the user is *not* meant to reach for. That is not a reason to skip custom sounds — it is a reason not to build the product around them.

The differentiator is alarm-grade delivery and completion-relative recurrence (§2). Product effort belongs on the alert itself and on the rolling-window timing being correct — not on an identity system the platform will not carry.

---

## 8. Scope

### In scope for v1

- Fixed recurring alarms
- Completion-relative alarms with deferral and re-anchoring
- One-off alarms
- Alert categories with visual identity (symbol, colour) and an auto-assigned alert sound — no user-facing sound or haptic picker (§7.1)
- One-tap Done from the Watch, re-arming the next occurrence
- Completion history (data captured; minimal UI)
- Rolling-window AlarmKit scheduler with reconciliation
- Local SwiftData persistence

### Explicitly NOT in v1

- ❌ Calendar / EventKit integration — deferred to v2. Complex, and Timely Alarms already occupies it.
- ❌ Any backend, accounts, or multi-caregiver sync
- ❌ Payload capture on completion (ounces, doses) — **field exists, unused**
- ❌ Notes displayed in the alert — v2
- ❌ Analytics, streaks, adherence reporting
- ❌ Android, visionOS, macOS, iPad-specific UI
- ❌ Subscriptions or monetization

### v2 candidates, in rough priority order

1. Note payload displayed in the alert ("two blue pills")
2. Completion payload capture (ounces, dose)
3. Calendar integration for pre-event alerts
4. Multi-caregiver sync (CloudKit sharing — the first genuine backend need)

---

## 9. Open questions to resolve before building the completion flow

Answer these empirically. They are cheap and they gate real design decisions.

1. ~~Is the AlarmKit entitlement obtainable?~~ **Resolved — see §3.5. There is no entitlement to obtain.** Just add `NSAlarmKitUsageDescription` to Info.plist.
2. ~~What actions does the forwarded alarm presentation expose on the Watch?~~ **Resolved — see §3.6.** A custom Done plus the system Stop both appear on the Watch; the custom intent must stop the alarm itself.
3. ~~How many haptic identities are actually distinguishable?~~ **Descoped — no longer gates any decision.** `HapticLab Watch App` will answer it (singles vs. burst delivery, blind quiz, confusion matrix) if curiosity demands, but §3.1 shows an app-authored haptic sequence cannot reach a Focus-piercing alert regardless of the answer, and §7.1 now designs for a single auto-assigned identity. Run it only as a cheap upper bound, never as a gate.
4. **Do competitor alerts pierce Sleep Focus?** Set a reminder in Huckleberry or Pump Log, enable Sleep Focus, sleep. If they break through, the core wedge is weaker than assumed.

---

## 10. Build order

1. Get a plain SwiftUI app building to the physical iPhone (signing works end to end)
2. Minimal AlarmKit test — one hardcoded alarm, two minutes out → **answers Q2** (Watch forwarded actions) and confirms real-device delivery works
3. SwiftData model layer per §4
4. Next-fire calculation and the action-semantics table in §5, with unit tests — this is pure logic and should be fully tested independent of UI
5. Rolling-window scheduler and reconciliation per §6
6. iPhone UI: create, list, edit reminders
7. Watch target: Done affordance
8. Category configuration — name, symbol, colour only. Alert identity is auto-assigned (§7.1), so there is no picker to build.

**Test §5 heavily.** It's the part most likely to be subtly wrong, it's pure functions over dates, and bugs there produce alarms at wrong times — the single worst failure mode this app can have.

---

## 11. Legal and positioning notes

- Include a Terms of Service from the first public build. The clause that matters most: **no guarantee of delivery**, since alerts depend on iOS behavior, battery, Focus configuration, and Apple's alarm limits.
- Position as a **scheduling tool**, never a medical authority. No dosage calculation, no drug interactions, no health claims. This keeps it clear of medical-device territory and materially lowers risk.
- Developer account is enrolled as **Individual**. Revisit an LLC before any public launch positioned around medication adherence.
- EU: charging for anything makes you a **trader** under the DSA, which publishes your name, address, phone, and email on EU listings. Use a P.O. Box or mailbox service — Apple explicitly permits it.
