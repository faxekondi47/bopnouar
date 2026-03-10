## Context

The addon has three button visual states (idle/gray, active/green, and the in-combat dimmed idle). When the rogue pops cooldowns, the button goes green+pulsing and the paladin clicks to BoP. However, if Forbearance (25771) is already on the target from a previous BoP, the spell silently fails — no visual feedback tells the paladin why.

TBC Classic constraints apply: `SetAttribute()` is protected in combat, so we cannot toggle `type` to actually disable clicks mid-fight. The button must remain technically clickable during combat.

## Goals / Non-Goals

**Goals:**
- Track Forbearance debuff on the active target via combat log
- Show a distinct BLOCKED visual state (orange) when CDs are active but Forbearance is up
- Display a countdown timer showing remaining Forbearance duration on the button
- Show Forbearance info in the alert frame on a new line below the main text
- Auto-transition BLOCKED → ACTIVE when Forbearance expires while CDs are still active

**Non-Goals:**
- Actually disabling button clicks during combat (protected API limitation)
- Tracking Forbearance on non-active targets
- Tracking the source of Forbearance (which spell caused it)

## Decisions

### 1. Forbearance tracking via combat log (same as CD tracking)

Track `SPELL_AURA_APPLIED` / `SPELL_AURA_REMOVED` for spell ID 25771 on the active target, using the same `COMBAT_LOG_EVENT_UNFILTERED` handler. Store as a boolean `hasForbearance` plus a `forbearanceExpiry` timestamp (`GetTime() + 60`).

**Why not UnitDebuff polling?** Combat log events are already the addon's detection mechanism. Adding a polling loop would be inconsistent and less efficient. The combat log gives us the exact application time for the countdown.

### 2. Countdown via OnUpdate timer (reuse existing frame)

The existing `frame:SetScript("OnUpdate", ...)` handles the alert auto-hide timer. Extend it to also update the Forbearance countdown text when `hasForbearance` is true. Calculate remaining time as `forbearanceExpiry - GetTime()`. When the countdown hits zero, treat it as Forbearance expiry (fallback in case the `SPELL_AURA_REMOVED` event is missed).

**Why a timer fallback?** If the target dies or leaves range, the `SPELL_AURA_REMOVED` event may never fire. The 60-second timer ensures the BLOCKED state always resolves.

### 3. Visual state: orange background, no pulse, countdown text

BLOCKED state: orange background (`0.9, 0.5, 0, 0.9`), white text, no pulse animation, button text changes to show countdown (e.g., `"Forbearance 0:34"`). This is visually distinct from both idle (gray) and active (green+pulse).

The button label (`"BoP <target>"`) is replaced by the Forbearance countdown during BLOCKED state, and restored when transitioning out.

### 4. Alert frame shows Forbearance on second line

When an alert fires and Forbearance is active, add a second line: `"Forbearance active! (0:34)"`. Use a separate FontString anchored below the existing alert text. This line updates via OnUpdate alongside the button countdown.

### 5. State resolution is a function, not spread across handlers

Create a single `ResolveButtonState()` function that reads `activeBuffs`, `hasForbearance`, and `inCombat` to determine the correct visual state. Call it from all state-changing code paths instead of directly calling `SetButtonActive`/`SetButtonIdle`. This prevents state inconsistencies.

## Risks / Trade-offs

- **Forbearance SPELL_AURA_REMOVED may not fire** (target dies, leaves range) → Mitigated by the 60-second timer fallback in OnUpdate
- **Button remains clickable during BLOCKED** (TBC secure API limitation) → Acceptable; the orange visual + countdown clearly communicates "don't click yet"
- **Hardcoded 60-second duration** → Forbearance is always 60s in TBC Classic; if this changes in a future patch, only one constant needs updating
