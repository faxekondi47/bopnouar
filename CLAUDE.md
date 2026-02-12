# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BopNouar is a World of Warcraft addon targeting **TBC Classic Anniversary** (Interface 20505). It monitors a specific player ("Twistedrogue") for Rogue cooldowns (Adrenaline Rush, Blade Flurry) via the combat log and presents an instant Blessing of Protection button when those buffs are detected.

## Architecture

Single-file addon: `BopNouar/BopNouar.lua` with `BopNouar/BopNouar.toc` as the addon manifest.

Key design constraint: The BoP button is a `SecureActionButtonTemplate` which means **Show(), Hide(), EnableMouse(), SetPoint(), SetSize(), SetAttribute() are all protected and cannot be called in combat** in TBC Classic. The addon works around this with:
- **`SetAttribute("type", nil/macro)`** to toggle clickability out of combat
- **`SecureHandlerStateTemplate`** (`BopNouarSecureManager`) with `RegisterStateDriver` to set `type="macro"` on combat entry via the restricted environment (which CAN call SetAttribute during combat)
- **Visual states** (gray dimmed idle / green pulsing active) to indicate button functionality
- Button is always visible at alpha=1; never use SetAlpha for visibility toggling

The addon has three logical layers:
- **SecureActionButton** (`BopNouarButton`) — always-visible macro button, type-attribute-toggled with idle/active visual states, shift+drag movable, executes `/cast [@Twistedrogue] Blessing of Protection`
- **SecureHandlerStateTemplate** (`BopNouarSecureManager`) — manages combat state transitions for the button's type attribute
- **Alert frame** (`BopNouarAlert`) — non-secure visual overlay, safe to Show/Hide in combat
- **Combat log scanner** — listens to `COMBAT_LOG_EVENT_UNFILTERED`, tracks `SPELL_AURA_APPLIED`/`SPELL_AURA_REFRESH`/`SPELL_AURA_REMOVED` for spell IDs 13750 and 13877

## WoW Addon Development Notes

- Lua is the only scripting language; addon code runs in WoW's sandboxed Lua 5.1 environment
- No build step — the `.toc` and `.lua` files are loaded directly by the game client
- Test in-game with `/bopnouar test` to trigger the alert UI without a real combat event
- `/bopnouar reset` resets button position to default (blocked during combat)
- Shift+drag to reposition the button; position persists via `SavedVariables: BopNouarDB`
- `SetAttribute()` is protected in combat — use `SecureHandlerStateTemplate` + `RegisterStateDriver` for combat-time attribute changes
- Mid-combat buff removal can only update visuals (textures, text color, animations); type attribute cleanup defers to `PLAYER_REGEN_ENABLED`
- The `.toc` `## Interface:` value must match the game client version (20505 for TBC Classic Anniversary)
- Cross-realm names come as "Name-Realm"; the addon strips the realm suffix via pattern matching
