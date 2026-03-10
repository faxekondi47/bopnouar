## 1. Forbearance State Tracking

- [x] 1.1 Add Forbearance constants (`FORBEARANCE_SPELL_ID = 25771`, `FORBEARANCE_DURATION = 60`) and state variables (`hasForbearance`, `forbearanceExpiry`)
- [x] 1.2 Extend `COMBAT_LOG_EVENT_UNFILTERED` handler to detect Forbearance `SPELL_AURA_APPLIED`/`SPELL_AURA_REMOVED` on the active target (spell ID 25771)
- [x] 1.3 Clear Forbearance state (`hasForbearance`, `forbearanceExpiry`) in `ApplyTarget()` when the active target changes

## 2. BLOCKED Visual State

- [x] 2.1 Create `SetButtonBlocked()` function — orange background (`0.9, 0.5, 0, 0.9`), white text, stop pulse, set text to `"Forbearance M:SS"`
- [x] 2.2 Create `ResolveButtonState()` function that reads `activeBuffs`, `hasForbearance`, and `inCombat` to call the correct visual state function (idle/active/blocked)
- [x] 2.3 Replace all direct `SetButtonActive()`/`SetButtonIdle()` calls with `ResolveButtonState()` (in ShowAlert, SPELL_AURA_REMOVED, PLAYER_REGEN_ENABLED, ApplyTarget)

## 3. Countdown Timer

- [x] 3.1 Extend the `OnUpdate` handler to compute Forbearance remaining time and update button text and alert Forbearance line each tick while `hasForbearance` is true
- [x] 3.2 Add countdown-reaches-zero fallback: clear Forbearance state and call `ResolveButtonState()` when timer expires

## 4. Alert Frame Forbearance Line

- [x] 4.1 Add a second FontString (`alertForbText`) to the alert frame, anchored below `alertText`
- [x] 4.2 In `ShowAlert()`, show/hide the Forbearance line and set initial text based on `hasForbearance`
- [x] 4.3 Hide the Forbearance line when Forbearance expires while alert is visible

## 5. Testing

- [x] 5.1 Update `/bopnouar test` slash command to support `test forbearance` — simulates CD active + Forbearance state for visual verification
