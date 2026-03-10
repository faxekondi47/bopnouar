## Why

When a paladin has already used Blessing of Protection on the tracked target, the target receives a 1-minute Forbearance debuff preventing another BoP. Currently the addon shows the button as active (green, pulsing) when the rogue pops cooldowns, with no indication that BoP will fail due to Forbearance. This leads to the paladin clicking the button, nothing visible happening, and confusion about whether the addon is broken.

## What Changes

- Track Forbearance debuff (spell ID 25771) on the active target via combat log events
- Add a new BLOCKED visual state (orange) for when cooldowns are active but Forbearance prevents BoP
- Show a countdown timer on the button displaying Forbearance remaining time
- Show Forbearance status on a new line in the alert frame when relevant
- Transition from BLOCKED → ACTIVE automatically when Forbearance expires while cooldowns are still active

## Capabilities

### New Capabilities
- `forbearance-tracking`: Detect and track Forbearance debuff on the active target, maintain countdown timer, and drive a new BLOCKED visual state on the button and alert frame

### Modified Capabilities
- `dynamic-target`: Forbearance tracking must reset when the active target changes (same as activeBuffs cleanup)

## Impact

- `BopNouar/BopNouar.lua`: All changes are in this single file — new state tracking variables, updated combat log handler, new visual state function, modified OnUpdate for countdown, updated alert text
