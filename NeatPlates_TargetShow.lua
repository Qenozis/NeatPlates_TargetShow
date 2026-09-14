local addonName, addonTable = ...
local mouseoverCache, activeUnits = {}, {}
local positions = { "BOTTOM", "TOP", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

SLASH_NEATPLATESTARGETSHOW1 = "/npts"
SlashCmdList["NEATPLATESTARGETSHOW"] = function()
    if Settings and Settings.OpenToCategory then
        if addonTable.categoryID then Settings.OpenToCategory(addonTable.categoryID)
        else Settings.OpenToCategory("NeatPlates: Target Show") end
    else InterfaceOptionsFrame_OpenToCategory("NeatPlates: Target Show") end
end

local function GetUnitRoleString(unit)
    if not UnitExists(unit) then return "" end
    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" then return "Tank"
    elseif role == "HEALER" then return "Heal"
    elseif role == "DAMAGER" then return "DPS" end
    return ""
end

local function GetTargetDetails(targetUnit)
    if not targetUnit or not UnitExists(targetUnit) then return nil end
    local name = UnitName(targetUnit)
    local isPlayer = UnitIsPlayer(targetUnit)
    local isSubgroup = UnitInParty(targetUnit) or UnitInRaid(targetUnit) or UnitIsUnit(targetUnit, "player")
    local classColorHex, roleStr = "FFFFFF", "-"
    
    local db = _G["NeatPlatesTargetShowGlobals"]
    local profile = db and db.profiles and db.profiles[db.activeProfile]
    
    if isPlayer then
        if profile and profile.colorByClass then
            local _, classFilename = UnitClass(targetUnit)
            if classFilename then
                local colorObj = RAID_CLASS_COLORS[classFilename]
                if colorObj then classColorHex = string.format("%02x%02x%02x", colorObj.r*255, colorObj.g*255, colorObj.b*255) end
            end
        end
        if isSubgroup then
            local groupRole = GetUnitRoleString(targetUnit)
            roleStr = (groupRole ~= "") and groupRole or "Player"
        else roleStr = "-" end
    else
        roleStr = "NPC"
        if profile and profile.colorNPCGreen then classColorHex = "33FF33" end
    end
    return name, classColorHex, roleStr
end
local function GetUnitTargetData(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    local db = _G["NeatPlatesTargetShowGlobals"]
    local profile = db and db.profiles and db.profiles[db.activeProfile]
    local cacheDuration = profile and profile.cacheTime or 5

    if UnitIsUnit(unit, "mouseover") then
        local name, colorHex, role = GetTargetDetails("mouseovertarget")
        if name and guid then
            mouseoverCache[guid] = { name = name, colorHex = colorHex, role = role, time = GetTime() }
            return name, colorHex, role
        end
    end
    local targetUnit = nil
    if UnitIsUnit(unit, "target") then targetUnit = "targettarget"
    elseif UnitIsUnit(unit, "focus") then targetUnit = "focustarget"
    else
        local prefix = IsInRaid() and "raid" or "party"
        local numMembers = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
        for i = 1, numMembers do
            local memberToken = prefix .. i
            if UnitIsUnit(unit, memberToken .. "target") then targetUnit = memberToken .. "targettarget" break end
        end
    end
    if targetUnit and UnitExists(targetUnit) then return GetTargetDetails(targetUnit) end
    if guid and mouseoverCache[guid] then
        local cacheData = mouseoverCache[guid]
        if GetTime() - cacheData.time < cacheDuration then return cacheData.name, cacheData.colorHex, cacheData.role
        else mouseoverCache[guid] = nil end
    end
    return nil
end

local function GetNeatPlatesCarrier(plateFrame)
    if not plateFrame then return nil end
    if plateFrame.extended then return plateFrame.extended end
    local children = { plateFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsObjectType("StatusBar") then return child end
    end
    return plateFrame
end

local function ClearAllTargetTexts()
    local activePlates = C_NamePlate.GetNamePlates()
    if activePlates then
        for _, plateFrame in ipairs(activePlates) do
            local carrier = GetNeatPlatesCarrier(plateFrame)
            if carrier and carrier.TargetContainer then carrier.TargetContainer:Hide() end
        end
    end
end
local function ApplyTextAnchor(container, carrier)
    local db = _G["NeatPlatesTargetShowGlobals"]
    local profile = db and db.profiles and db.profiles[db.activeProfile] or {}
    local position = profile.textPosition or "BOTTOM"
    local offsetX, offsetY = profile.offsetX or 0, profile.offsetY or 0
    container:ClearAllPoints()
    if position == "BOTTOM" then container:SetPoint("TOP", carrier, "BOTTOM", offsetX, offsetY - 2)
    elseif position == "TOP" then container:SetPoint("BOTTOM", carrier, "TOP", offsetX, offsetY + 2)
    elseif position == "LEFT" then container:SetPoint("RIGHT", carrier, "LEFT", offsetX - 4, offsetY)
    elseif position == "RIGHT" then container:SetPoint("LEFT", carrier, "RIGHT", offsetX + 4, offsetY)
    elseif position == "TOPLEFT" then container:SetPoint("BOTTOMRIGHT", carrier, "TOPLEFT", offsetX - 2, offsetY + 2)
    elseif position == "TOPRIGHT" then container:SetPoint("BOTTOMLEFT", carrier, "TOPRIGHT", offsetX + 2, offsetY + 2)
    elseif position == "BOTTOMLEFT" then container:SetPoint("TOPRIGHT", carrier, "BOTTOMLEFT", offsetX - 2, offsetY - 2)
    elseif position == "BOTTOMRIGHT" then container:SetPoint("TOPLEFT", carrier, "BOTTOMRIGHT", offsetX + 2, offsetY - 2) end
end

local function UpdateTargetText(plateFrame, unit)
    local db = _G["NeatPlatesTargetShowGlobals"]
    local p = db and db.profiles and db.profiles[db.activeProfile]
    if not p or not p.enabled then return end
    local carrier = GetNeatPlatesCarrier(plateFrame)
    if not carrier or not plateFrame:IsShown() then return end

    if not carrier.TargetContainer then
        -- KLUCZOWA POPRAWKA: Dodajemy szablon "BackdropTemplate", który odblokowuje zaokrąglone rogi
        carrier.TargetContainer = CreateFrame("Frame", nil, carrier, "BackdropTemplate")
        carrier.TargetOfTargetText = carrier.TargetContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        
        -- Tworzymy teksturę tła jako osobny element, aby mieć pełną kontrolę nad przezroczystością tła
        carrier.TargetBg = carrier.TargetContainer:CreateTexture(nil, "BACKGROUND")
    end

    local container = carrier.TargetContainer
    local text = carrier.TargetOfTargetText

    if p.bringToFront then container:SetFrameLevel(carrier:GetFrameLevel() + 15)
    else container:SetFrameLevel(carrier:GetFrameLevel() - 1) end

    text:SetFont(GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF", p.fontSize or 11, "OUTLINE")
    ApplyTextAnchor(container, carrier)

    local name, colorHex, role = GetUnitTargetData(unit)
    if name then
        local displayText = "|cFF" .. colorHex .. name .. "|r"
        if p.showRole then displayText = displayText .. " |cFFFFFFFF(" .. role .. ")|r" end
        text:SetText(displayText)
        text:ClearAllPoints()
        text:SetPoint("CENTER", container, "CENTER", 0, 0)

        local pad = p.borderPadding or 2
        local textWidth = text:GetStringWidth()
        local textHeight = text:GetStringHeight()
        container:SetSize(textWidth + (pad * 2), textHeight + (pad * 2))

        if p.showBorder then
            -- Rysowanie koloru tła za pomocą dedykowanej tekstury
            carrier.TargetBg:SetAllPoints(container)
            carrier.TargetBg:SetColorTexture(p.bgR or 0, p.bgG or 0, p.bgB or 0, p.bgA or 0.5)
            carrier.TargetBg:Show()

            if p.roundedCorners then
                -- WYBÓR A: Zaokrąglone rogi (Prawidłowe użycie oficjalnej systemowej tekstury z gładkimi krawędziami)
                container:SetBackdrop({
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 8,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 }
                })
                -- Przypisanie koloru wybranego z Color Pickera bezpośrednio do zaokrąglonej ramki
                container:SetBackdropBorderColor(p.brR or 1, p.brG or 1, p.brB or 1, p.brA or 1)
            else
                -- WYBÓR B: Klasyczna kanciasta ramka klockowa
                container:SetBackdrop(nil) -- Czyścimy zaokrąglony backdrop
                if not carrier.TargetBorder then
                    carrier.TargetBorder = container:CreateTexture(nil, "BORDER")
                end
                carrier.TargetBorder:SetPoint("TOPLEFT", container, "TOPLEFT", -1, 1)
                carrier.TargetBorder:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 1, -1)
                carrier.TargetBorder:SetColorTexture(p.brR or 1, p.brG or 1, p.brB or 1, p.brA or 1)
                carrier.TargetBorder:Show()
            end
        else
            -- Ukrywanie wszystkiego, jeśli opcja Border & Background jest wyłączona
            carrier.TargetBg:Hide()
            if carrier.TargetBorder then carrier.TargetBorder:Hide() end
            container:SetBackdrop(nil)
            container:SetSize(textWidth, textHeight)
        end
        container:Show() text:Show()
    else container:Hide() end
end

local optionsFrame = CreateFrame("Frame", "NeatPlates_TargetShowOptionsFrame", UIParent)
optionsFrame.name = "NeatPlates: Target Show"

local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("NeatPlates: Target Show Settings")

local scrollFrame = CreateFrame("ScrollFrame", "NPTS_ScrollFrame", optionsFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
scrollFrame:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -30, 10)

local scrollChild = CreateFrame("Frame", "NPTS_ScrollChild", scrollFrame)
scrollChild:SetSize(380, 520)
scrollFrame:SetScrollChild(scrollChild)

local function CreateOptionCheckbox(name, text, relativeTo, yOffset)
    local cb = CreateFrame("CheckButton", name, scrollChild, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset)
    _G[cb:GetName() .. "Text"]:SetText(text)
    return cb
end

local function CreateSlider(name, text, low, high, relativeTo, xOff, yOff, width)
    local lbl = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", xOff, yOff)
    lbl:SetText(text)
    local s = CreateFrame("Slider", name, scrollChild, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 5, -3)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(1)
    s:SetWidth(width or 140)
    _G[s:GetName() .. "Low"]:SetText(low) _G[s:GetName() .. "High"]:SetText(high)
    local valText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.label = lbl s.valText = valText
    return s, valText
end

local profLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
profLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -10)
profLabel:SetText("Profile Manager:")

local dropdown = CreateFrame("Frame", "NPTS_ProfileDropdown", scrollChild, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPLEFT", profLabel, "BOTTOMLEFT", -15, -5)
UIDropDownMenu_SetWidth(dropdown, 140)

local profEB = CreateFrame("EditBox", "NPTS_ProfileEditBox", scrollChild, "InputBoxTemplate")
profEB:SetSize(140, 20)
profEB:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 20, -10)
profEB:SetAutoFocus(false)

local function CreateProfBtn(text, rel, point, x, y, func)
    local b = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    b:SetSize(90, 20) b:SetPoint(point, rel, x, y) b:SetText(text) b:SetScript("OnClick", func)
    return b
end

local btnNew = CreateProfBtn("Create New", profEB, "TOPRIGHT", 100, 0)
local btnCopy = CreateProfBtn("Copy Active", profEB, "BOTTOMLEFT", 0, -15)
local btnDel = CreateProfBtn("Delete", profEB, "BOTTOMRIGHT", 100, -15)

local cbEnabled = CreateOptionCheckbox("NPTS_CbEnabled", " Enable addon (Show target name around nameplates)", btnCopy, -20)
local cbClass = CreateOptionCheckbox("NPTS_CbClass", " Color names by class", cbEnabled, -5)
local cbRole = CreateOptionCheckbox("NPTS_CbRole", " Show role/status in brackets (e.g. Tank, NPC, -)", cbClass, -5)
local cbNPC = CreateOptionCheckbox("NPTS_CbNPC", " Color NPC names green", cbRole, -5)
local cbFront = CreateOptionCheckbox("NPTS_CbFront", " Bring to Front (Draw name ABOVE nameplates/z-index)", cbNPC, -5)
local cbBorder = CreateOptionCheckbox("NPTS_CbBorder", " Enable Border & Background around target name", cbFront, -5)
local cbRound = CreateOptionCheckbox("NPTS_CbRound", " Enable Rounded Corners (Smooth border edges)", cbBorder, -5)

local szSlider, szText = CreateSlider("NPTS_SizeSlider", "Font Size:", 6, 20, cbRound, 0, -15)
local xSlider, xText = CreateSlider("NPTS_XSlider", "X Offset:", -50, 50, szSlider, -5, -20)
local ySlider, yText = CreateSlider("NPTS_YSlider", "Y Offset:", -50, 50, xSlider, -5, -20)
local tSlider, tText = CreateSlider("NPTS_TimeSlider", "Display Time (Sec):", 3, 30, ySlider, -5, -20)
local pSlider, pText = CreateSlider("NPTS_PadSlider", "Border Padding:", 0, 20, tSlider, -5, -20)
local bgASlider, bgAText = CreateSlider("NPTS_BgASlider", "Background Alpha (Opacity %):", 0, 100, pSlider, -5, -20)
-- DWA SYSTEMOWE PRZYCISKI COLOR PICKERA (Zastępują suwaki RGB)
local function CreateColorButton(name, text, relativeTo, yOffset, key)
    local lbl = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset)
    lbl:SetText(text)
    
    local btn = CreateFrame("Button", name, scrollChild)
    btn:SetSize(18, 18)
    btn:SetPoint("LEFT", lbl, "RIGHT", 15, 0)
    
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetColorTexture(0.5, 0.5, 0.5, 1) -- Obwódka
    
    local colorTex = btn:CreateTexture(nil, "OVERLAY")
    colorTex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    colorTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    
    btn.lbl = lbl btn.colorTex = colorTex btn.key = key
    
    btn:SetScript("OnClick", function(self)
        if not cbBorder:GetChecked() then return end
        local db = _G["NeatPlatesTargetShowGlobals"]
        local p = db and db.profiles[db.activeProfile]
        if not p then return end
        
        local rKey, gKey, bKey = self.key.."R", self.key.."G", self.key.."B"
        
        ColorPickerFrame:SetupColorPickerAndShow({
            r = p[rKey] or 0, g = p[gKey] or 0, b = p[bKey] or 0,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                p[rKey], p[gKey], p[bKey] = r, g, b
                self.colorTex:SetColorTexture(r, g, b, 1)
            end,
            cancelFunc = function(prev)
                p[rKey], p[gKey], p[bKey] = prev.r, prev.g, prev.b
                self.colorTex:SetColorTexture(prev.r, prev.g, prev.b, 1)
            end
        })
    end)
    return btn
end

local bgColorBtn = CreateColorButton("NPTS_BgColorBtn", "Background Color:", bgASlider, -18, "bg")
local brColorBtn = CreateColorButton("NPTS_BrColorBtn", "Border Color:", bgColorBtn.lbl, -15, "br")

local function UpdateBorderSlidersLock()
    local enabled = cbBorder:GetChecked()
    local list = { pSlider, bgASlider }
    for _, s in ipairs(list) do
        if enabled then s:Enable() s.label:SetFontObject("GameFontNormal") s.valText:SetFontObject("GameFontHighlight")
        else s:Disable() s.label:SetFontObject("GameFontDisable") s.valText:SetFontObject("GameFontDisable") end
    end
    if enabled then
        bgColorBtn.lbl:SetFontObject("GameFontNormal") brColorBtn.lbl:SetFontObject("GameFontNormal")
    else
        bgColorBtn.lbl:SetFontObject("GameFontDisable") brColorBtn.lbl:SetFontObject("GameFontDisable")
    end
end

-- local radioLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
-- radioLabel:SetPoint("TOPLEFT", brColorBtn.lbl, "BOTTOMLEFT", 0, -20)
-- radioLabel:SetText("Text Position Around Nameplate:")

-- local radioButtons = {}
-- local function RadioButton_OnClick(self)
--     for _, rb in ipairs(radioButtons) do rb:SetChecked(false) end
--     self:SetChecked(true)
--     local db = _G["NeatPlatesTargetShowGlobals"]
--     if db and db.profiles and db.profiles[db.activeProfile] then db.profiles[db.activeProfile].textPosition = self.posValue end
--     ClearAllTargetTexts()
-- end

-- for i, pos in ipairs(positions) do
--     local rb = CreateFrame("CheckButton", "NPTS_Radio_" .. pos, scrollChild, "UIRadioButtonTemplate")
--     rb.posValue = pos
--     if i <= 4 then rb:SetPoint("TOPLEFT", radioLabel, "BOTTOMLEFT", (i-1) * 85, -10)
--     else rb:SetPoint("TOPLEFT", radioLabel, "BOTTOMLEFT", (i-5) * 85, -30) end
--     _G[rb:GetName() .. "Text"]:SetText(pos)
--     rb:SetScript("OnClick", RadioButton_OnClick)
--     table.insert(radioButtons, rb)
-- end

-- TWORZENIE DROPDOWNA DLA POZYCJI TEKSTU (Zastępuje stare Radio Buttons)
local positionLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
positionLabel:SetPoint("TOPLEFT", brColorBtn.lbl, "BOTTOMLEFT", 0, -25)
positionLabel:SetText("Text Position Around Nameplate:")

local posDropdown = CreateFrame("Frame", "NPTS_PositionDropdown", scrollChild, "UIDropDownMenuTemplate")
posDropdown:SetPoint("TOPLEFT", positionLabel, "BOTTOMLEFT", -15, -5)
UIDropDownMenu_SetWidth(posDropdown, 140)

local function PosDropdown_OnClick(self)
    local db = _G["NeatPlatesTargetShowGlobals"]
    if db and db.profiles and db.profiles[db.activeProfile] then
        db.profiles[db.activeProfile].textPosition = self.value
    end
    UIDropDownMenu_SetSelectedValue(posDropdown, self.value)
    UIDropDownMenu_SetText(posDropdown, self.value)
    ClearAllTargetTexts()
end

local function PosDropdown_Initialize(self, level)
    local db = _G["NeatPlatesTargetShowGlobals"]
    local currentPos = "BOTTOM"
    if db and db.profiles and db.profiles[db.activeProfile] then
        currentPos = db.profiles[db.activeProfile].textPosition or "BOTTOM"
    end
    
    local info = UIDropDownMenu_CreateInfo()
    for _, pos in ipairs(positions) do
        info.text = pos
        info.value = pos
        info.func = PosDropdown_OnClick
        info.checked = (currentPos == pos)
        UIDropDownMenu_AddButton(info)
    end
end

local function RefreshUI()
    local db = _G["NeatPlatesTargetShowGlobals"]
    if not db then return end local p = db.profiles[db.activeProfile] if not p then return end
    cbEnabled:SetChecked(p.enabled)
    cbClass:SetChecked(p.colorByClass)
    cbRole:SetChecked(p.showRole)
    cbNPC:SetChecked(p.colorNPCGreen)
    cbFront:SetChecked(p.bringToFront)
    cbBorder:SetChecked(p.showBorder)
    cbRound:SetChecked(p.roundedCorners or false)
    szSlider:SetValue(p.fontSize or 11) szText:SetText(p.fontSize or 11)
    xSlider:SetValue(p.offsetX or 0) xText:SetText(p.offsetX or 0)
    ySlider:SetValue(p.offsetY or 0) yText:SetText(p.offsetY or 0)
    tSlider:SetValue(p.cacheTime or 5) tText:SetText(p.cacheTime or 5)
    pSlider:SetValue(p.borderPadding or 2) pText:SetText(p.borderPadding or 2)
    bgASlider:SetValue(math.floor((p.bgA or 0.5) * 100)) bgAText:SetText(math.floor((p.bgA or 0.5) * 100))
    bgColorBtn.colorTex:SetColorTexture(p.bgR or 0, p.bgG or 0, p.bgB or 0, 1)
    brColorBtn.colorTex:SetColorTexture(p.brR or 1, p.brG or 1, p.brB or 1, 1)
    -- for _, rb in ipairs(radioButtons) do rb:SetChecked(rb.posValue == (p.textPosition or "BOTTOM")) end
    -- Wczytanie i ustawienie aktualnej pozycji w nowym dropdownie
    UIDropDownMenu_SetSelectedValue(posDropdown, p.textPosition or "BOTTOM")
    UIDropDownMenu_SetText(posDropdown, p.textPosition or "BOTTOM")
    UIDropDownMenu_SetText(dropdown, db.activeProfile)
    profLabel:SetText("Active Profile: |cFF00FF00" .. db.activeProfile .. "|r")
    UpdateBorderSlidersLock()
end

local function CopyTable(src, dst)
    if not src or not dst then return end
    for k, v in pairs(src) do dst[k] = v end
end

local function Dropdown_OnClick(self)
    local db = _G["NeatPlatesTargetShowGlobals"]
    db.activeProfile = self.value
    db.charToProfile[UnitName("player") .. "-" .. GetRealmName()] = self.value
    UIDropDownMenu_SetSelectedValue(dropdown, self.value)
    RefreshUI()
    ClearAllTargetTexts()
end

local function Dropdown_Initialize(self, level)
    local db = _G["NeatPlatesTargetShowGlobals"]
    if not db then return end
    local info = UIDropDownMenu_CreateInfo()
    for name, _ in pairs(db.profiles) do
        info.text = name
        info.value = name
        info.func = Dropdown_OnClick
        info.checked = (db.activeProfile == name)
        UIDropDownMenu_AddButton(info)
    end
end

btnNew:SetScript("OnClick", function()
        local name = profEB:GetText():trim()
        if name == "" then return end
        local db = _G["NeatPlatesTargetShowGlobals"]
        if not db.profiles[name] then db.profiles[name] = { enabled = true, colorByClass = true, showRole = true, colorNPCGreen = true, textPosition =
            "BOTTOM", fontSize = 11, offsetX = 0, offsetY = 0, cacheTime = 5, borderPadding = 2, bringToFront = false, showBorder = false, bgR = 0, bgG = 0, bgB = 0, bgA = 0.5, brR = 1, brG = 1, brB = 1, brA = 1 } end
        db.activeProfile = name
        db.charToProfile[UnitName("player") .. "-" .. GetRealmName()] = name
        profEB:SetText("")
        UIDropDownMenu_Initialize(dropdown, Dropdown_Initialize)
        UIDropDownMenu_Initialize(posDropdown, PosDropdown_Initialize)
        RefreshUI()
        ClearAllTargetTexts()
    end)

btnCopy:SetScript("OnClick", function()
        local name = profEB:GetText():trim()
        local db = _G["NeatPlatesTargetShowGlobals"]
        if name ~= "" and db.profiles[name] and db.activeProfile ~= name then
            CopyTable(db.profiles[db.activeProfile], db.profiles[name])
            profEB:SetText("")
            RefreshUI()
        end
    end)

btnDel:SetScript("OnClick", function()
        local name = profEB:GetText():trim()
        local db = _G["NeatPlatesTargetShowGlobals"]
        if name ~= "" and db.profiles[name] and name ~= "Default" and db.activeProfile ~= name then
            db.profiles[name] = nil
            profEB:SetText("")
            UIDropDownMenu_Initialize(dropdown, Dropdown_Initialize)
            UIDropDownMenu_Initialize(posDropdown, PosDropdown_Initialize)
            RefreshUI()
        end
    end)


if Settings and Settings.RegisterCanvasLayoutCategory then local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name) Settings.RegisterAddOnCategory(category) if category.GetID then addonTable.categoryID = category:GetID() else addonTable.categoryID = category end else InterfaceOptions_AddCategory(optionsFrame) end

szSlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) szText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].fontSize = val end end)
xSlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) xText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].offsetX = val end end)
ySlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) yText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].offsetY = val end end)
tSlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) tText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].cacheTime = val end end)
pSlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) pText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].borderPadding = val end end)
bgASlider:SetScript("OnValueChanged", function(self, v) local val = math.floor(v) bgAText:SetText(val) local db = _G["NeatPlatesTargetShowGlobals"] if db and self:IsMouseOver() then db.profiles[db.activeProfile].bgA = val / 100 end end)

cbEnabled:SetScript("OnClick", function(self) local db = _G["NeatPlatesTargetShowGlobals"] if db then db.profiles[db.activeProfile].enabled = self:GetChecked() end if not self:GetChecked() then ClearAllTargetTexts() end end)
cbClass:SetScript("OnClick", function(self) local db = _G["NeatPlatesTargetShowGlobals"] if db then db.profiles[db.activeProfile].colorByClass = self:GetChecked() end end)
cbRole:SetScript("OnClick", function(self) local db = _G["NeatPlatesTargetShowGlobals"] if db then db.profiles[db.activeProfile].showRole = self:GetChecked() end end)
cbNPC:SetScript("OnClick", function(self) local db = _G["NeatPlatesTargetShowGlobals"] if db then db.profiles[db.activeProfile].colorNPCGreen = self:GetChecked() end end)
cbFront:SetScript("OnClick", function(self) local db = _G["NeatPlatesTargetShowGlobals"] if db then db.profiles[db.activeProfile].bringToFront = self:GetChecked() end end)
cbBorder:SetScript("OnClick", function(self)
        local db = _G["NeatPlatesTargetShowGlobals"]
        if db then db.profiles[db.activeProfile].showBorder = self:GetChecked() end
        UpdateBorderSlidersLock()
    end)
cbRound:SetScript("OnClick", function(self)
    local db = _G["NeatPlatesTargetShowGlobals"]
    if db then db.profiles[db.activeProfile].roundedCorners = self:GetChecked() end
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if _G["NeatPlatesTargetShowGlobals"] == nil then
            _G["NeatPlatesTargetShowGlobals"] = { activeProfile = "Default", charToProfile = {}, profiles = { Default = { enabled = true, colorByClass = true, showRole = true, colorNPCGreen = true, textPosition = "BOTTOM", fontSize = 11, offsetX = 0, offsetY = 0, cacheTime = 5, borderPadding = 2, bringToFront = false, showBorder = false, bgR = 0, bgG = 0, bgB = 0, bgA = 0.5, brR = 1, brG = 1, brB = 1, brA = 1 } } }
        end
        local db = _G["NeatPlatesTargetShowGlobals"]
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        if not db.charToProfile[charKey] then db.charToProfile[charKey] = db.activeProfile or "Default" end
        db.activeProfile = db.charToProfile[charKey]
        if not db.profiles[db.activeProfile] then db.activeProfile = "Default" end
        UIDropDownMenu_Initialize(dropdown, Dropdown_Initialize)
        -- Inicjalizacja i wczytanie struktury menu rozwijanego pozycji
        UIDropDownMenu_Initialize(posDropdown, PosDropdown_Initialize)
        RefreshUI()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unitID = arg1
        activeUnits[unitID] = true
        local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
        if plateFrame then UpdateTargetText(plateFrame, unitID) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        activeUnits[arg1] = nil
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists("mouseover") then
            local plateFrame = C_NamePlate.GetNamePlateForUnit("mouseover")
            if plateFrame then UpdateTargetText(plateFrame, "mouseover") end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Pobieramy pełne dane z logu walki w patchu 2.5.6
        local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
        
        -- Interesują nas tylko akcje wykonywane PRZEZ wrogów (NPC) W graczy
        if sourceGUID and destName and (subEvent:find("_DAMAGE") or subEvent:find("_CAST_START") or subEvent:find("_MISSED")) then
            -- Sprawdzamy, czy cel (dest) to człowiek/gracz, a źródło to mob
            if sourceGUID:find("Creature") and destGUID:find("Player") then
                -- Wyciągamy metadane gracza (jego klasę, rolę itp.)
                local name, colorHex, role = GetTargetDetails(destName) -- Nasza istniejąca funkcja
                
                if name then
                    -- Wstrzykujemy dane bezpośrednio do naszego GUID-cache!
                    mouseoverCache[sourceGUID] = {
                        name = name,
                        colorHex = colorHex,
                        role = role,
                        time = GetTime() -- Odświeżamy timer wygasania (np. ustawione przez Ciebie 5-10s)
                    }
                end
            end
        end
    end
end)

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
    if self.timeSinceLastUpdate > 0.1 then
        self.timeSinceLastUpdate = 0
        local db = _G["NeatPlatesTargetShowGlobals"]
        if db and db.profiles and db.profiles[db.activeProfile] and db.profiles[db.activeProfile].enabled then
            for unitID, _ in pairs(activeUnits) do
                local plateFrame = C_NamePlate.GetNamePlateForUnit(unitID)
                if plateFrame and plateFrame:IsShown() then UpdateTargetText(plateFrame, unitID) end
            end
        end
    end
end)