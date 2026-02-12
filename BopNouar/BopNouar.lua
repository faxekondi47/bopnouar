local TARGET_NAME = "Twistedrogue"
local BOP_SPELL = "Blessing of Protection"
local ALERT_DURATION = 5
local IDLE_ALPHA = 0

local TRACKED_SPELLS = {
    [13750] = "Adrenaline Rush",
    [13877] = "Blade Flurry",
}

-- Track which buffs are currently active (handles both expiring independently)
local activeBuffs = {}

-- Main frame for event handling and timers
local frame = CreateFrame("Frame", "BopNouarFrame", UIParent)

---------------------------------------------------------------------------
-- BoP button (SecureActionButton)
--
-- IMPORTANT: On secure frames in TBC Classic, Show(), Hide(), EnableMouse(),
-- SetPoint(), and SetSize() are ALL protected and will cause "action blocked"
-- errors if called during combat. SetAlpha() is NOT protected.
--
-- Strategy: The button is always shown and always mouse-enabled. We use
-- SetAlpha() to make it invisible when idle and visible when triggered.
-- An accidental click on the invisible button is harmless - BoP has a cast
-- time and costs mana, so it won't go off without intention.
---------------------------------------------------------------------------
local bopButton = CreateFrame("Button", "BopNouarButton", UIParent, "SecureActionButtonTemplate")
bopButton:SetSize(220, 50)
bopButton:SetPoint("CENTER", 0, 140)
bopButton:SetFrameStrata("DIALOG")
bopButton:RegisterForClicks("AnyUp")
bopButton:SetAttribute("type", "macro")
bopButton:SetAttribute("macrotext", "/cast [@" .. TARGET_NAME .. "] " .. BOP_SPELL)
bopButton:SetAlpha(IDLE_ALPHA)

local bopBtnBg = bopButton:CreateTexture(nil, "BACKGROUND")
bopBtnBg:SetAllPoints()
bopBtnBg:SetColorTexture(0, 0.6, 0, 0.9)

local bopBtnText = bopButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bopBtnText:SetPoint("CENTER")
bopBtnText:SetText("BoP " .. TARGET_NAME)
bopBtnText:SetTextColor(1, 1, 1, 1)

bopButton:SetScript("OnEnter", function(self)
    if self:GetAlpha() > 0 then
        bopBtnBg:SetColorTexture(0, 0.8, 0, 1)
    end
end)

bopButton:SetScript("OnLeave", function(self)
    bopBtnBg:SetColorTexture(0, 0.6, 0, 0.9)
end)

---------------------------------------------------------------------------
-- Alert frame (non-secure, pure visual - safe to Show/Hide in combat)
---------------------------------------------------------------------------
local alertFrame = CreateFrame("Frame", "BopNouarAlert", UIParent)
alertFrame:SetSize(400, 100)
alertFrame:SetPoint("CENTER", 0, 200)
alertFrame:SetFrameStrata("DIALOG")
alertFrame:Hide()

local alertBg = alertFrame:CreateTexture(nil, "BACKGROUND")
alertBg:SetAllPoints()
alertBg:SetColorTexture(0.8, 0, 0, 0.7)

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
alertText:SetPoint("CENTER", alertFrame, "CENTER", 0, 15)
alertText:SetTextColor(1, 1, 0, 1)

local alertSubText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alertSubText:SetPoint("CENTER", alertFrame, "CENTER", 0, -15)
alertSubText:SetTextColor(1, 1, 1, 1)
alertSubText:SetText("Click the button below to BoP!")

---------------------------------------------------------------------------
-- Auto-hide timer
---------------------------------------------------------------------------
local hideTimer = 0
local timerActive = false

frame:SetScript("OnUpdate", function(self, elapsed)
    if not timerActive then return end
    hideTimer = hideTimer - elapsed
    if hideTimer <= 0 then
        timerActive = false
        alertFrame:Hide()
        bopButton:SetAlpha(IDLE_ALPHA)
    end
end)

---------------------------------------------------------------------------
-- Alert functions
---------------------------------------------------------------------------
local function ShowAlert(spellName)
    alertText:SetText(TARGET_NAME .. " popped " .. spellName .. "!")
    alertFrame:Show()
    bopButton:SetAlpha(1)
    PlaySound(8959)
    hideTimer = ALERT_DURATION
    timerActive = true
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cFFFF0000[BopNouar]|r " .. TARGET_NAME .. " used " .. spellName .. "! BoP NOW!",
        1, 1, 0
    )
end

local function HideAlert()
    alertFrame:Hide()
    bopButton:SetAlpha(IDLE_ALPHA)
    timerActive = false
end

-- Dismiss after clicking
bopButton:HookScript("OnClick", function()
    HideAlert()
end)

---------------------------------------------------------------------------
-- Combat log scanning
---------------------------------------------------------------------------
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Loaded. Watching " .. TARGET_NAME ..
            " for Adrenaline Rush / Blade Flurry."
        )
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, _, destName, _, _, spellId =
            CombatLogGetCurrentEventInfo()

        -- Strip realm suffix for cross-realm compatibility ("Name-Realm" -> "Name")
        local nameOnly = destName and destName:match("^([^-]+)") or destName
        if nameOnly ~= TARGET_NAME then return end

        if TRACKED_SPELLS[spellId] then
            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                activeBuffs[spellId] = true
                ShowAlert(TRACKED_SPELLS[spellId])
            elseif subevent == "SPELL_AURA_REMOVED" then
                activeBuffs[spellId] = nil
                if not next(activeBuffs) then
                    HideAlert()
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_BOPNOUAR1 = "/bopnouar"
SlashCmdList["BOPNOUAR"] = function(msg)
    if msg == "test" then
        ShowAlert("Adrenaline Rush")
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Watching for " .. TARGET_NAME ..
            "'s Adrenaline Rush / Blade Flurry"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Type /bopnouar test to test the alert"
        )
    end
end
