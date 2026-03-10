### Requirement: Forbearance debuff detection
The addon SHALL track the Forbearance debuff (spell ID 25771) on the active target via `COMBAT_LOG_EVENT_UNFILTERED`. When `SPELL_AURA_APPLIED` fires for Forbearance on the active target, `hasForbearance` SHALL be set to true and `forbearanceExpiry` SHALL be set to `GetTime() + 60`.

#### Scenario: Forbearance applied to active target
- **WHEN** a `SPELL_AURA_APPLIED` fires for spell ID 25771 on the active target
- **THEN** `hasForbearance` SHALL be set to true and `forbearanceExpiry` SHALL be set to `GetTime() + 60`

#### Scenario: Forbearance applied to non-active target
- **WHEN** a `SPELL_AURA_APPLIED` fires for spell ID 25771 on a character that is not the active target
- **THEN** the addon SHALL ignore the event

### Requirement: Forbearance removal detection
When `SPELL_AURA_REMOVED` fires for Forbearance (25771) on the active target, `hasForbearance` SHALL be set to false and `forbearanceExpiry` SHALL be cleared.

#### Scenario: Forbearance removed from active target
- **WHEN** a `SPELL_AURA_REMOVED` fires for spell ID 25771 on the active target
- **THEN** `hasForbearance` SHALL be set to false and the button state SHALL be resolved

### Requirement: Forbearance countdown timer
While `hasForbearance` is true, the `OnUpdate` handler SHALL compute remaining time as `forbearanceExpiry - GetTime()` and update the button text and alert Forbearance line with the formatted time (`M:SS`). When the countdown reaches zero, the addon SHALL clear Forbearance state as a fallback.

#### Scenario: Countdown ticks during Forbearance
- **WHEN** `hasForbearance` is true and an OnUpdate tick fires
- **THEN** the button text SHALL display `"Forbearance M:SS"` with the remaining time and the alert Forbearance line (if alert is visible) SHALL update similarly

#### Scenario: Countdown reaches zero
- **WHEN** `hasForbearance` is true and `forbearanceExpiry - GetTime()` is less than or equal to zero
- **THEN** `hasForbearance` SHALL be set to false, `forbearanceExpiry` SHALL be cleared, and button state SHALL be resolved

### Requirement: BLOCKED visual state
When cooldowns are active (`next(activeBuffs)` is truthy) AND `hasForbearance` is true, the button SHALL display the BLOCKED visual state: orange background (`0.9, 0.5, 0, 0.9`), white text color, pulse animation stopped, and button text showing Forbearance countdown.

#### Scenario: Cooldowns active with Forbearance
- **WHEN** one or more tracked cooldowns are active on the target AND Forbearance is active
- **THEN** the button SHALL show orange background, white text, no pulse, and text `"Forbearance M:SS"`

#### Scenario: Forbearance expires while cooldowns still active
- **WHEN** Forbearance expires (removed or countdown reaches zero) AND tracked cooldowns are still active
- **THEN** the button SHALL transition to ACTIVE state (green background, pulse animation, `"BoP <target>"` text)

#### Scenario: Cooldowns expire while Forbearance still active
- **WHEN** all tracked cooldowns expire AND Forbearance is still active
- **THEN** the button SHALL transition to IDLE state (gray background, no pulse)

### Requirement: Alert frame Forbearance line
The alert frame SHALL include a second FontString below the main alert text. When an alert fires and `hasForbearance` is true, this line SHALL display `"Forbearance active! (M:SS)"`. When Forbearance is not active, this line SHALL be hidden.

#### Scenario: Alert fires with Forbearance active
- **WHEN** `ShowAlert()` is called and `hasForbearance` is true
- **THEN** the alert frame SHALL show the main alert text on the first line and `"Forbearance active! (M:SS)"` on the second line

#### Scenario: Alert fires without Forbearance
- **WHEN** `ShowAlert()` is called and `hasForbearance` is false
- **THEN** the Forbearance line SHALL be hidden

#### Scenario: Forbearance expires while alert is visible
- **WHEN** the alert frame is visible and Forbearance expires
- **THEN** the Forbearance line SHALL be hidden

### Requirement: State resolution function
A single `ResolveButtonState()` function SHALL determine the correct button visual state based on the combination of `activeBuffs`, `hasForbearance`, and `inCombat`. All state-changing code paths SHALL call this function instead of directly calling `SetButtonActive` or `SetButtonIdle`.

#### Scenario: State matrix
- **WHEN** `ResolveButtonState()` is called
- **THEN** the state SHALL be determined as:
  - No active buffs → IDLE (regardless of Forbearance)
  - Active buffs + no Forbearance → ACTIVE
  - Active buffs + Forbearance → BLOCKED
