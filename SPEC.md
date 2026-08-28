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

`WKInterfaceDevice.play()` has no effect when the app is inactive or backgrounded. The only exemption is an active workout session, which does not apply here.

**Consequence:** there is no way to author a "haptic language" where distinct buzz patterns identify distinct reminders while the app is closed. Differentiation comes from AlarmKit's sound-paired system alerts. Arbitrary haptic sequences work only in the foreground.

### 3.2 AlarmKit is iOS-first, not native watchOS

Alarms are scheduled by the **iPhone** app. The presentation is *forwarded* to the paired Watch. There is no watchOS alarm scheduling API.

**Consequence:** the iPhone app is the primary target. The Watch target is thin.

### 3.3 There is a system-enforced alarm ceiling

AlarmKit publishes no fixed maximum, but the system imposes a resource-dependent limit and returns `maximumLimitReached` when exceeded.

**Consequence:** the rolling-window scheduler in §6 is mandatory architecture, not an optimization. Do not attempt to materialize every future occurrence.

### 3.4 Notifications are not a fallback

If an alert degrades to `UNNotification`, it loses Focus-piercing delivery — which is the entire product thesis. Notifications may be used for genuinely ambient nudges, but never as a silent fallback for a missed alarm.

### 3.5 ⚠️ Unresolved: the AlarmKit entitlement

`com.apple.developer.alarmkit` may be a managed entitlement requiring Apple approval. Multiple developers report the capability not appearing in the Developer Portal, causing device builds to fail with *"Provisioning profile doesn't include the com.apple.developer.alarmkit entitlement"* — while the Simulator works fine with only the Info.plist key.

Shipping apps using AlarmKit exist on the App Store, so a working path exists. **Status unknown for this project until a device build is attempted.** Do not assume either outcome.

### 3.6 ⚠️ Unresolved: forwarded alarm actions on the Watch

Unknown what buttons the forwarded alarm presentation exposes on watchOS. The Done-vs-Dismiss model in §5 depends on this. **Verify empirically before building the completion flow.**

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
    var soundID: String               // AlarmKit sound → determines paired haptic
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

⚠️ See §3.6 — whether this is achievable on the forwarded Watch presentation is unverified.

---

## 6. The rolling-window scheduler

Mandatory, per §3.3.

**Rules:**

1. Materialize `ScheduledOccurrence` rows only for the **next 24–36 hours**.
2. Register each with AlarmKit and store the returned `alarmKitID`.
3. Top up the window as alarms fire and resolve.
4. On `maximumLimitReached`, shrink the window and retry rather than failing outward. Surface a warning if the user's configuration genuinely can't fit.
5. Treat the schedule as something you **rebuild**, not mutate. Reconciliation should be idempotent.

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
- **Alert identity is per-category**, configured once in settings, not per-reminder. Users should not be choosing sounds at creation time.
- ⚠️ **Assume ~3–4 distinguishable alert identities, not 10.** Verify by wearing the test app (see §9). Design the category system so a small number is not a limitation.

---

## 8. Scope

### In scope for v1

- Fixed recurring alarms
- Completion-relative alarms with deferral and re-anchoring
- One-off alarms
- Alert categories with distinct sound/haptic identity
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

1. **Is the AlarmKit entitlement obtainable?** Add the capability in Xcode's Signing & Capabilities, build to a physical iPhone. If it fails with the provisioning error, open a DTS ticket. *(Highest risk item in the project.)*
2. **What actions does the forwarded alarm presentation expose on the Watch?** Schedule a trivial alarm, let it fire while wearing the Series 11, observe the buttons. **§5.4 depends entirely on this.**
3. **How many haptic identities are actually distinguishable?** Throwaway Watch app, one button per `WKHapticType`, wear it two days. Expect 3–4 before they blur.
4. **Do competitor alerts pierce Sleep Focus?** Set a reminder in Huckleberry or Pump Log, enable Sleep Focus, sleep. If they break through, the core wedge is weaker than assumed.

---

## 10. Build order

1. Get a plain SwiftUI app building to the physical iPhone (signing works end to end)
2. Minimal AlarmKit test — one hardcoded alarm, two minutes out → **answers Q1 and Q2**
3. SwiftData model layer per §4
4. Next-fire calculation and the action-semantics table in §5, with unit tests — this is pure logic and should be fully tested independent of UI
5. Rolling-window scheduler and reconciliation per §6
6. iPhone UI: create, list, edit reminders
7. Watch target: Done affordance
8. Category and alert-identity configuration

**Test §5 heavily.** It's the part most likely to be subtly wrong, it's pure functions over dates, and bugs there produce alarms at wrong times — the single worst failure mode this app can have.

---

## 11. Legal and positioning notes

- Include a Terms of Service from the first public build. The clause that matters most: **no guarantee of delivery**, since alerts depend on iOS behavior, battery, Focus configuration, and Apple's alarm limits.
- Position as a **scheduling tool**, never a medical authority. No dosage calculation, no drug interactions, no health claims. This keeps it clear of medical-device territory and materially lowers risk.
- Developer account is enrolled as **Individual**. Revisit an LLC before any public launch positioned around medication adherence.
- EU: charging for anything makes you a **trader** under the DSA, which publishes your name, address, phone, and email on EU listings. Use a P.O. Box or mailbox service — Apple explicitly permits it.
