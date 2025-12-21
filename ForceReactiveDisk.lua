local N = "ForceReactiveDisk"
local D = 18168
local W = nil

if not FRD_Settings then
    FRD_Settings = {
        durabilityThreshold = 30,
        autoMode = false,
        checkInterval = 2.0,
        enabled = true,
        monitorEnabled = false,
        monitorInterval = 0.5,
        monitorShowOOC = false,
        repairReminderEnabled = true,
        repairFramePosX = 0,
        repairFramePosY = -120,
        minimap = {
            angle = 0,
            shown = true
        }
    }
end



local F = CreateFrame("Frame", "ForceReactiveDiskFrame", UIParent)
F:RegisterEvent("ADDON_LOADED")
F:RegisterEvent("PLAYER_ENTERING_WORLD")
F:RegisterEvent("PLAYER_REGEN_DISABLED")
F:RegisterEvent("PLAYER_REGEN_ENABLED")
F:RegisterEvent("BAG_UPDATE")
F:RegisterEvent("UNIT_INVENTORY_CHANGED")
F:RegisterEvent("UPDATE_INVENTORY_ALERTS")
F.timeSinceLastCheck = 0
F.inCombat = false
F.warnedAllBelowTwo = false
F.authWarningShown = false
F.repairShown = false


local function H(str)
    local h = 5381
    for i = 1, string.len(str) do
        local c = string.byte(str, i)
        h = math.mod(h * 33 + c, 4294967296)
    end
    return h
end

function F:X(showWarning)
    local name = UnitName("player") or ""
    local guildName = GetGuildInfo("player") or ""

    local playerHash = H(N .. "P:" .. name)
    local guildHash = nil
    if guildName ~= "" then
        guildHash = H(N .. "G:" .. guildName)
    end

    local ok = P[playerHash] == true
    if not ok and guildHash then
        ok = Q[guildHash] == true
    end

    if not ok and showWarning and not self.authWarningShown then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 需要请联系开发者")
        self.authWarningShown = true
    end
    return ok
end

F:SetScript("OnEvent", function()
    if event ~= "ADDON_LOADED" and not F:X(false) then
        return
    end
    if event == "ADDON_LOADED" and arg1 == N then

        if not FRD_Settings then
            FRD_Settings = {}
        end
        if not FRD_Settings.durabilityThreshold then
            FRD_Settings.durabilityThreshold = 30
        end
        if not FRD_Settings.autoMode then
            FRD_Settings.autoMode = false
        end
        if not FRD_Settings.checkInterval then
            FRD_Settings.checkInterval = 2.0
        end
        if FRD_Settings.enabled == nil then
            FRD_Settings.enabled = true
        end
        if FRD_Settings.monitorEnabled == nil then
            FRD_Settings.monitorEnabled = false
        end
        if not FRD_Settings.monitorInterval then
            FRD_Settings.monitorInterval = 0.5
        end
        if FRD_Settings.monitorShowOOC == nil then
            FRD_Settings.monitorShowOOC = false
        end
        if FRD_Settings.repairReminderEnabled == nil then
            FRD_Settings.repairReminderEnabled = true
        end
        if not FRD_Settings.minimap then
            FRD_Settings.minimap = { angle = 0, shown = true }
        end
        if F:X(true) then
            F:Initialize()
        else
            FRD_Settings.enabled = false
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        F:UpdateMonitorVisibility(true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        F.inCombat = true
        F:HideRepairWarning()
        if FRD_Settings.autoMode and FRD_Settings.enabled then
            F:StartAutoCheck()
        end
        F:UpdateMonitorVisibility(true)
        F:UpdateMinimapIconState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        F.inCombat = false
        F:StopAutoCheck()
        F:UpdateMonitorVisibility(true)
        F:CheckRepairReminder()
    elseif event == "BAG_UPDATE" or event == "UPDATE_INVENTORY_ALERTS" then
        F:UpdateMonitorText(false)
        if not F.inCombat then
            F:CheckRepairReminder()
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            F:UpdateMonitorText(false)
            if not F.inCombat then
                F:CheckRepairReminder()
            end
        end
    end
end)


function F:Initialize()

    self:CreateMinimapButton()

    self:CreateSettingsFrame()

    self:CreateMonitorFrame()

    self:RegisterSlashCommands()

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件已加载!|r 使用 /frd 或 /forcedisk 来管理盾牌")
    self:UpdateMonitorVisibility(true)
    self:UpdateMinimapIconState()
end


function F:CreateMonitorFrame()
    if self.monitorFrame then
        return
    end

    local frame = CreateFrame("Frame", "FRDMonitorFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(170)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:Hide()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    header:SetWidth(280)
    header:SetJustifyH("LEFT")
    header:SetText("")
    frame.header = header

    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    container:SetWidth(280)
    container:SetHeight(110)
    frame.iconContainer = container
    frame.icons = {}

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    frame.timeSinceLastUpdate = 0
    self.monitorFrame = frame
end

function F:StartMonitor()
    if not self.monitorFrame then
        self:CreateMonitorFrame()
    end

    self.monitorFrame.timeSinceLastUpdate = 0
    self.monitorFrame:SetScript("OnUpdate", function()
        F.monitorFrame.timeSinceLastUpdate = F.monitorFrame.timeSinceLastUpdate + arg1
        if F.monitorFrame.timeSinceLastUpdate >= (FRD_Settings.monitorInterval or 0.5) then
            F.monitorFrame.timeSinceLastUpdate = 0
            F:UpdateMonitorText(true)
        end
    end)
end

function F:StopMonitor()
    if self.monitorFrame then
        self.monitorFrame:SetScript("OnUpdate", nil)
    end
end

function F:UpdateMonitorVisibility(forceUpdateText)
    if not self.monitorFrame then
        self:CreateMonitorFrame()
    end

    local shouldShow = FRD_Settings.enabled and FRD_Settings.monitorEnabled and self.inCombat
    if FRD_Settings.monitorEnabled and FRD_Settings.monitorShowOOC then
        shouldShow = FRD_Settings.enabled
    end
    if shouldShow then
        self.monitorFrame:Show()
        self:StartMonitor()
        self:UpdateMonitorText(forceUpdateText)
    else
        self:StopMonitor()
        self.monitorFrame:Hide()
    end
end

function F:FormatDurabilityColor(durabilityPercent)
    if not durabilityPercent then
        return "|cff888888"
    end
    if durabilityPercent < (FRD_Settings.durabilityThreshold or 30) then
        return "|cffff0000"
    end
    if durabilityPercent < 60 then
        return "|cffff9900"
    end
    return "|cff00ff00"
end

function F:UpdateMonitorText(force)
    if not self.monitorFrame or not self.monitorFrame:IsShown() then
        return
    end

    local offhandIsDisk = self:IsOffhandForceReactiveDisk()
    local offhandDurability = nil
    local offhandTexture = nil
    if offhandIsDisk then
        offhandDurability = self:GetOffhandDurability()
        offhandTexture = GetInventoryItemTexture("player", 17)
    end

    local disks = self:FindAllDisksInBags()
    local bagCount = table.getn(disks)
    local best = nil
    local worst = nil
    if bagCount > 0 then
        for i = 1, bagCount do
            local d = disks[i].durability
            if not best or d > best then best = d end
            if not worst or d < worst then worst = d end
        end
    end

    local entries = {}

    if offhandIsDisk then
        table.insert(entries, {
            label = "副手",
            durability = offhandDurability,
            texture = offhandTexture or "Interface\\Icons\\INV_Shield_21",
            equipped = true
        })
    end

    if bagCount > 0 then
        table.sort(disks, function(a, b) return a.durability > b.durability end)
        for i = 1, bagCount do
            local d = disks[i]
            local texture
            if GetContainerItemInfo then
                local tex = GetContainerItemInfo(d.bag, d.slot)
                if type(tex) == "table" then
                    texture = tex.icon
                else
                    texture = tex
                end
            end
            texture = texture or "Interface\\Icons\\INV_Shield_21"
            table.insert(entries, {
                label = "包" .. d.bag .. "槽" .. d.slot,
                durability = d.durability,
                texture = texture,
                equipped = false
            })
        end
    end

    local totalDur = 0
    local totalCount = table.getn(entries)
    for i = 1, totalCount do
        totalDur = totalDur + entries[i].durability
    end

    local totalInfo
    if totalCount > 0 then
        local totalPool = totalCount * 100
        totalInfo = string.format("总耐久: %.1f%% / %d%%", totalDur, totalPool)
    else
        totalInfo = "总耐久: 无力反馈盾牌"
    end

    self.monitorFrame.header:SetText(totalInfo)

    local columns = 6
    local iconSize = 36
    local padding = 6

    local usedCols = totalCount > 0 and math.min(columns, totalCount) or 1
    local rows = math.max(1, math.ceil(totalCount / usedCols))
    local contentWidth = usedCols * (iconSize + padding) - padding
    if contentWidth < 120 then contentWidth = 120 end
    local frameWidth = contentWidth + 20
    local contentHeight = rows * (iconSize + 18)
    local frameHeight = 40 + contentHeight

    self.monitorFrame:SetWidth(frameWidth)
    self.monitorFrame.header:SetWidth(frameWidth - 20)
    self.monitorFrame.iconContainer:SetWidth(contentWidth)
    self.monitorFrame.iconContainer:SetHeight(contentHeight)

    for i = 1, totalCount do
        local entry = entries[i]
        local iconFrame = self.monitorFrame.icons[i]
        if not iconFrame then
            iconFrame = CreateFrame("Frame", nil, self.monitorFrame.iconContainer)
            iconFrame:SetWidth(iconSize)
            iconFrame:SetHeight(iconSize + 14)

            iconFrame.bg = iconFrame:CreateTexture(nil, "BACKGROUND")
            iconFrame.bg:SetAllPoints()
            iconFrame.bg:SetTexture(0, 0, 0, 0.5)

            iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
            iconFrame.icon:SetWidth(iconSize)
            iconFrame.icon:SetHeight(iconSize)
            iconFrame.icon:SetPoint("TOP", iconFrame, "TOP", 0, 0)

            iconFrame.text = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            iconFrame.text:SetPoint("TOP", iconFrame.icon, "BOTTOM", 0, -2)
            iconFrame.text:SetText("")

            self.monitorFrame.icons[i] = iconFrame
        end

        local col = math.mod((i - 1), usedCols)
        local row = math.floor((i - 1) / usedCols)
        iconFrame:SetPoint("TOPLEFT", self.monitorFrame.iconContainer, "TOPLEFT", col * (iconSize + padding), -row * (iconSize + 18))

        iconFrame.icon:SetTexture(entry.texture)
        local colorCode = self:FormatDurabilityColor(entry.durability)
        iconFrame.text:SetText(colorCode .. string.format("%.0f", entry.durability) .. "%|r")

        if entry.equipped then
            iconFrame.bg:SetTexture(0, 0.5, 0, 0.5)
        else
            iconFrame.bg:SetTexture(0, 0, 0, 0.5)
        end

        iconFrame:Show()
    end

    if self.monitorFrame.icons then
        for i = totalCount + 1, table.getn(self.monitorFrame.icons) do
            if self.monitorFrame.icons[i] then
                self.monitorFrame.icons[i]:Hide()
            end
        end
    end

    self.monitorFrame:SetHeight(frameHeight)
end


function F:CheckRepairReminder()
    if not FRD_Settings.repairReminderEnabled then
        self:HideRepairWarning()
        return
    end

    local threshold = 90
    local needRepair = false

    if self:IsOffhandForceReactiveDisk() then
        local offDur = self:GetOffhandDurability()
        if offDur and offDur < threshold then
            needRepair = true
        end
    end

    if not needRepair then
        local disks = self:FindAllDisksInBags()
        for i = 1, table.getn(disks) do
            if disks[i].durability < threshold then
                needRepair = true
                break
            end
        end
    end

    if needRepair then
        if not self.repairShown then
            UIErrorsFrame:AddMessage("|cffff0000[FRD]|r 盾牌耐久低于90%，请尽快修理！", 1, 0, 0, 1)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 盾牌耐久低于90%，请尽快修理！")
        end
        self.repairShown = true
        self:ShowRepairWarning()
    else
        self.repairShown = false
        self:HideRepairWarning()
    end
end

function F:ShowHelp()
    local tips = {
        "|cff00ff00[FRD]|r 使用帮助：",
        "需要有多块力反馈盾牌，放在包里会自动切换，单块仅仅能监控",
        "勾选主动模式可战斗中自动检测",
        "如果自动模式卡顿，可将 /frd 绑定到技能宏",
        "小地图图标鼠标右键可以开关插件",
        "设置：滑块设定阈值与刷新频率，建议阈值为15% 和0.4秒刷新率",
        "MirAcLe公会专用版，作者：安娜希尔"
    }
    for i = 1, table.getn(tips) do
        DEFAULT_CHAT_FRAME:AddMessage(tips[i])
    end
end

function F:ResetPositions()
    if self.monitorFrame then
        self.monitorFrame:ClearAllPoints()
        self.monitorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    FRD_Settings.repairFramePosX = 0
    FRD_Settings.repairFramePosY = -120
    if self.repairFrame then
        self.repairFrame:ClearAllPoints()
        self.repairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        if self.repairShown then
            self.repairFrame:Show()
        end
    end

    FRD_Settings.minimap.angle = 0
    if self.minimapButton then
        self:UpdateMinimapButtonPosition()
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 窗口位置已重置")
end

function F:EnsureRepairWarningFrame()
    if self.repairFrame then return end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetWidth(320)
    f:SetHeight(36)
    local px = FRD_Settings.repairFramePosX or 0
    local py = FRD_Settings.repairFramePosY or -120
    f:SetPoint("CENTER", UIParent, "CENTER", px, py)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.7)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        FRD_Settings.repairFramePosX = cx - ux
        FRD_Settings.repairFramePosY = cy - uy
    end)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)
    t:SetText("|cffff0000盾牌耐久低于90%，请尽快修理！|r")
    self.repairFrame = f
end

function F:ShowRepairWarning()
    self:EnsureRepairWarningFrame()
    if self.repairFrame then
        self.repairFrame:Show()
    end
end

function F:HideRepairWarning()
    if self.repairFrame then
        self.repairFrame:Hide()
    end
end

P = {
    [598142992] = true,
    [1171904003] = true,
    [1594961939] = true,
    [2983116801] = true,
    [1842309505] = true,
    [2712406225] = true,
    }
Q = {[598142992] = true,}


function F:GetItemDurability(bag, slot)
    if not W then
        W = CreateFrame("GameTooltip", "FRDScanTooltip", nil, "GameTooltipTemplate")
        W:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    W:ClearLines()
    W:SetBagItem(bag, slot)


    for i = 1, W:NumLines() do
        local text = getglobal("FRDScanTooltipTextLeft" .. i):GetText()
        if text then

            local current, maximum = string.match(text, "(%d+)%s*/%s*(%d+)")
            if current and maximum then
                current = tonumber(current)
                maximum = tonumber(maximum)
                if maximum > 0 then
                    return (current / maximum) * 100
                end
            end
        end
    end

    return 100
end


function F:IsForceReactiveDisk(bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    if itemLink then
        local _, _, itemId = string.find(itemLink, "item:(%d+)")
        return tonumber(itemId) == D
    end
    return false
end


function F:FindAllDisksInBags()
    local disks = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            if self:IsForceReactiveDisk(bag, slot) then
                local durability = self:GetItemDurability(bag, slot)
                table.insert(disks, {
                    bag = bag,
                    slot = slot,
                    durability = durability
                })
            end
        end
    end
    return disks
end


function F:IsOffhandForceReactiveDisk()
    local offhandLink = GetInventoryItemLink("player", 17)
    if offhandLink then
        local _, _, itemId = string.find(offhandLink, "item:(%d+)")
        return tonumber(itemId) == D
    end
    return false
end


function F:GetOffhandDurability()
    if not W then
        W = CreateFrame("GameTooltip", "FRDScanTooltip", nil, "GameTooltipTemplate")
        W:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    W:ClearLines()
    W:SetInventoryItem("player", 17)


    for i = 1, W:NumLines() do
        local text = getglobal("FRDScanTooltipTextLeft" .. i):GetText()
        if text then
            local current, maximum = string.match(text, "(%d+)%s*/%s*(%d+)")
            if current and maximum then
                current = tonumber(current)
                maximum = tonumber(maximum)
                if maximum > 0 then
                    return (current / maximum) * 100
                end
            end
        end
    end

    return 100
end


function F:EquipDisk(bag, slot)
    PickupContainerItem(bag, slot)
    PickupInventoryItem(17)
end


function F:StartAutoCheck()
    if not self:X(true) then
        return
    end
    self.timeSinceLastCheck = 0
    self:SetScript("OnUpdate", function(elapsed)
        F.timeSinceLastCheck = F.timeSinceLastCheck + arg1
        if F.timeSinceLastCheck >= FRD_Settings.checkInterval then
            F.timeSinceLastCheck = 0
            F:CheckAndSwapDisk(true)
        end
    end)
end


function F:StopAutoCheck()
    self:SetScript("OnUpdate", nil)
end


function F:CheckAndSwapDisk(silent)
    if not self:X(not silent) then
        return
    end
    if not FRD_Settings.enabled then
        if not silent then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 插件已停用，右键小地图图标可重新启用")
        end
        return
    end


    if not self:IsOffhandForceReactiveDisk() then

        local disks = self:FindAllDisksInBags()
        if table.getn(disks) > 0 then

            table.sort(disks, function(a, b) return a.durability > b.durability end)
            self:EquipDisk(disks[1].bag, disks[1].slot)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已装备力反馈盾牌 (耐久度 " .. string.format("%.1f", disks[1].durability) .. "%)")
            end
        else
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 背包中没有找到力反馈盾牌!")
            end
        end
        return
    end


    local currentDurability = self:GetOffhandDurability()
    local threshold = FRD_Settings.durabilityThreshold or 30
    local disks = self:FindAllDisksInBags()
    local bagCount = table.getn(disks)

    if bagCount > 0 then
        table.sort(disks, function(a, b) return a.durability > b.durability end)
    end

    local bestDisk = bagCount > 0 and disks[1] or nil
    local bestDurability = bestDisk and bestDisk.durability or 0
    local maxDurability = currentDurability
    if bestDurability > maxDurability then
        maxDurability = bestDurability
    end


    if maxDurability <= 2 then
        if not self.warnedAllBelowTwo then
            UIErrorsFrame:AddMessage("|cffff0000[FRD]|r 所有力反馈盾牌耐久低于2%，即将损毁!", 1, 0.2, 0.2, 1)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 所有力反馈盾牌耐久低于2%，即将损毁!")
            end
            self.warnedAllBelowTwo = true
        end

        if currentDurability <= 0 and bestDisk and bestDurability > currentDurability then
            self:EquipDisk(bestDisk.bag, bestDisk.slot)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 当前盾牌耐久已为0，强制切换到剩余耐久最高的盾牌 (" .. string.format("%.1f", bestDurability) .. "%)")
            end
        end
        return
    else
        self.warnedAllBelowTwo = false
    end

    if currentDurability < threshold then
        local allBelowThreshold = bestDurability < threshold


        if allBelowThreshold then
            if currentDurability <= 2 and bestDisk and bestDurability > currentDurability then
                self:EquipDisk(bestDisk.bag, bestDisk.slot)
                if not silent then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 所有盾牌耐久都低于阈值，当前耐久低于2%，强制切换至剩余耐久最高盾牌 (" .. string.format("%.1f", bestDurability) .. "%)")
                end
            elseif bagCount == 0 and not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有备用盾牌")
            end
            return
        end


        if bestDisk and bestDurability > currentDurability then
            self:EquipDisk(bestDisk.bag, bestDisk.slot)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已切换盾牌(" .. string.format("%.1f", currentDurability) .. "% -> " .. string.format("%.1f", bestDurability) .. "%)")
            end
        else
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有更好的盾牌")
            end
        end
    end
end


function F:CreateMinimapButton()
    local button = CreateFrame("Button", "FRDMinimapButton", Minimap)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52, -52)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture("FRDMinimapIcon", "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Shield_21")
    button.icon = icon

    local enabledOverlay = button:CreateTexture("FRDMinimapEnabledOverlay", "ARTWORK")
    enabledOverlay:SetWidth(36)
    enabledOverlay:SetHeight(36)
    enabledOverlay:SetPoint("CENTER", button, "CENTER", 0, 0)
    enabledOverlay:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    enabledOverlay:SetBlendMode("ADD")
    enabledOverlay:SetVertexColor(0, 1, 0, 0.6)
    button.enabledOverlay = enabledOverlay

    local disabledOverlay = button:CreateTexture("FRDMinimapDisabledOverlay", "ARTWORK")
    disabledOverlay:SetWidth(32)
    disabledOverlay:SetHeight(32)
    disabledOverlay:SetPoint("CENTER", button, "CENTER", 0, 0)
    disabledOverlay:SetTexture("Interface\\Common\\CancelRed")
    disabledOverlay:SetBlendMode("ADD")
    disabledOverlay:Hide()
    button.disabledOverlay = disabledOverlay

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(52)
    overlay:SetHeight(52)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    button:SetScript("OnClick", function()
        if not F:X(true) then
            return
        end
        if arg1 == "LeftButton" then
            FRDSettingsFrame:Show()
        elseif arg1 == "RightButton" then
            FRD_Settings.enabled = not FRD_Settings.enabled
            if FRD_Settings.enabled then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 插件已启用")
                F:UpdateMonitorVisibility(true)
                if FRD_Settings.autoMode and F.inCombat then
                    F:StartAutoCheck()
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 插件已停用")
                F:StopAutoCheck()
                F:UpdateMonitorVisibility(true)
            end
            F:UpdateMinimapIconState()
        end
    end)

    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("力反馈盾牌管理")
        GameTooltip:AddLine("左键: 打开设置", 1, 1, 1)
        GameTooltip:AddLine("右键: 启用/停用插件", 1, 1, 1)
        if FRD_Settings.autoMode then
            GameTooltip:AddLine("|cff00ff00主动模式: 已启用|r", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("|cff888888主动模式: 未启用|r", 0.5, 0.5, 0.5)
        end
        if FRD_Settings.enabled then
            GameTooltip:AddLine("|cff00ff00插件状态: 已启用|r", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("|cffff0000插件状态: 已停用|r", 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)


    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        this:SetScript("OnUpdate", F.MinimapButton_OnUpdate)
    end)
    button:SetScript("OnDragStop", function()
        this:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    self:UpdateMinimapIconState()
end


function F.MinimapButton_OnUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale

    local angle = math.deg(math.atan2(py - my, px - mx))
    FRD_Settings.minimap.angle = angle

    F:UpdateMinimapButtonPosition()
end


function F:UpdateMinimapButtonPosition()
    local angle = math.rad(FRD_Settings.minimap.angle or 0)
    local x = 80 * math.cos(angle)
    local y = 80 * math.sin(angle)
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end


function F:UpdateMinimapIconState()
    if not self.minimapButton then
        return
    end
    local icon = self.minimapButton.icon
    local onOverlay = self.minimapButton.enabledOverlay
    local offOverlay = self.minimapButton.disabledOverlay
    if not icon then return end

    if FRD_Settings.enabled then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
        if onOverlay then onOverlay:Show() end
        if offOverlay then offOverlay:Hide() end
    else
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.4, 0.4, 0.4, 0.8)
        if onOverlay then onOverlay:Hide() end
        if offOverlay then offOverlay:Show() end
    end
end


function F:CreateSettingsFrame()
    local frame = CreateFrame("Frame", "FRDSettingsFrame", UIParent)
    frame:SetWidth(350)
    frame:SetHeight(480)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    frame:Hide()


    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText("力反馈盾牌管理设置")


    local label1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label1:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -60)
    label1:SetText("切换耐久度阈值 (%):")


    local slider1 = CreateFrame("Slider", "FRDDurabilitySlider", frame, "OptionsSliderTemplate")
    slider1:SetPoint("TOP", frame, "TOP", 0, -90)
    slider1:SetMinMaxValues(10, 90)
    slider1:SetValueStep(5)
    slider1:SetValue(FRD_Settings.durabilityThreshold)
    slider1:SetWidth(250)
    getglobal(slider1:GetName() .. "Low"):SetText("10%")
    getglobal(slider1:GetName() .. "High"):SetText("90%")
    getglobal(slider1:GetName() .. "Text"):SetText(FRD_Settings.durabilityThreshold .. "%")

    slider1:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(newValue .. "%")
    end)


    local autoCheckbox = CreateFrame("CheckButton", "FRDAutoModeCheckbox", frame, "UICheckButtonTemplate")
    autoCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -140)
    autoCheckbox:SetWidth(24)
    autoCheckbox:SetHeight(24)
    autoCheckbox:SetChecked(FRD_Settings.autoMode)

    local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoLabel:SetPoint("LEFT", autoCheckbox, "RIGHT", 5, 0)
    autoLabel:SetText("启用主动检测模式（战斗中自动检测）")

    autoCheckbox:SetScript("OnClick", function()

    end)


    local label2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -180)
    label2:SetText("检测频率 (秒):")


    local slider2 = CreateFrame("Slider", "FRDIntervalSlider", frame, "OptionsSliderTemplate")
    slider2:SetPoint("TOP", frame, "TOP", 0, -210)
    slider2:SetMinMaxValues(0.2, 10)
    slider2:SetValueStep(0.2)
    slider2:SetWidth(250)
    getglobal(slider2:GetName() .. "Low"):SetText("0.2秒")
    getglobal(slider2:GetName() .. "High"):SetText("10秒")


    local intervalValue = FRD_Settings.checkInterval or 2.0
    if intervalValue < 0.2 then intervalValue = 0.2 end
    if intervalValue > 10 then intervalValue = 10 end

    slider2:SetValue(intervalValue)
    getglobal(slider2:GetName() .. "Text"):SetText(string.format("%.1f秒", intervalValue))

    slider2:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(string.format("%.1f秒", newValue))
    end)


    local monitorCheckbox = CreateFrame("CheckButton", "FRDMonitorCheckbox", frame, "UICheckButtonTemplate")
    monitorCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -250)
    monitorCheckbox:SetWidth(24)
    monitorCheckbox:SetHeight(24)
    monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)

    local monitorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorLabel:SetPoint("LEFT", monitorCheckbox, "RIGHT", 5, 0)
    monitorLabel:SetText("启用战斗耐久监控（显示小窗）")


    local label3 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label3:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -285)
    label3:SetText("监控刷新频率 (秒):")


    local slider3 = CreateFrame("Slider", "FRDMonitorIntervalSlider", frame, "OptionsSliderTemplate")
    slider3:SetPoint("TOP", frame, "TOP", 0, -315)
    slider3:SetMinMaxValues(0.1, 2.0)
    slider3:SetValueStep(0.1)
    slider3:SetWidth(250)
    getglobal(slider3:GetName() .. "Low"):SetText("0.1秒")
    getglobal(slider3:GetName() .. "High"):SetText("2.0秒")

    local monitorIntervalValue = FRD_Settings.monitorInterval or 0.5
    if monitorIntervalValue < 0.1 then monitorIntervalValue = 0.1 end
    if monitorIntervalValue > 2.0 then monitorIntervalValue = 2.0 end

    slider3:SetValue(monitorIntervalValue)
    getglobal(slider3:GetName() .. "Text"):SetText(string.format("%.1f秒", monitorIntervalValue))

    slider3:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(string.format("%.1f秒", newValue))
    end)


    frame.tempSettings = {
        durabilityThreshold = FRD_Settings.durabilityThreshold,
        autoMode = FRD_Settings.autoMode,
        checkInterval = intervalValue,
        monitorEnabled = FRD_Settings.monitorEnabled,
        monitorInterval = monitorIntervalValue,
        monitorShowOOC = FRD_Settings.monitorShowOOC,
        repairReminderEnabled = FRD_Settings.repairReminderEnabled
    }


    local monitorOOCCheckbox = CreateFrame("CheckButton", "FRDMonitorOOCCheckbox", frame, "UICheckButtonTemplate")
    monitorOOCCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -330)
    monitorOOCCheckbox:SetWidth(24)
    monitorOOCCheckbox:SetHeight(24)
    monitorOOCCheckbox:SetChecked(FRD_Settings.monitorShowOOC)

    local monitorOOCLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorOOCLabel:SetPoint("LEFT", monitorOOCCheckbox, "RIGHT", 5, 0)
    monitorOOCLabel:SetText("脱战也显示盾牌耐久监控")


    local repairCheckbox = CreateFrame("CheckButton", "FRDRepairCheckbox", frame, "UICheckButtonTemplate")
    repairCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -360)
    repairCheckbox:SetWidth(24)
    repairCheckbox:SetHeight(24)
    repairCheckbox:SetChecked(FRD_Settings.repairReminderEnabled)

    local repairLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    repairLabel:SetPoint("LEFT", repairCheckbox, "RIGHT", 5, 0)
    repairLabel:SetText("脱战后若盾牌低于90%提醒修理")


    local confirmButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    confirmButton:SetPoint("BOTTOM", frame, "BOTTOM", -60, 12)
    confirmButton:SetWidth(100)
    confirmButton:SetHeight(25)
    confirmButton:SetText("确认")
    confirmButton:SetScript("OnClick", function()

        FRD_Settings.durabilityThreshold = slider1:GetValue()
        FRD_Settings.autoMode = autoCheckbox:GetChecked() == 1
        FRD_Settings.checkInterval = slider2:GetValue()
        FRD_Settings.monitorEnabled = monitorCheckbox:GetChecked() == 1
        FRD_Settings.monitorInterval = slider3:GetValue()
        FRD_Settings.monitorShowOOC = monitorOOCCheckbox:GetChecked() == 1
        FRD_Settings.repairReminderEnabled = repairCheckbox:GetChecked() == 1


        if FRD_Settings.autoMode and F.inCombat then
            F:StartAutoCheck()
        elseif not FRD_Settings.autoMode then
            F:StopAutoCheck()
        end

        F:UpdateMonitorVisibility(true)

        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 设置已保存")
        frame:Hide()
    end)


    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 60, 12)
    closeButton:SetWidth(100)
    closeButton:SetHeight(25)
    closeButton:SetText("取消")
    closeButton:SetScript("OnClick", function()

        slider1:SetValue(FRD_Settings.durabilityThreshold)
        autoCheckbox:SetChecked(FRD_Settings.autoMode)
        slider2:SetValue(FRD_Settings.checkInterval)
        monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)
        slider3:SetValue(FRD_Settings.monitorInterval or 0.5)
        monitorOOCCheckbox:SetChecked(FRD_Settings.monitorShowOOC)
        repairCheckbox:SetChecked(FRD_Settings.repairReminderEnabled)
        frame:Hide()
    end)

    local helpButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    helpButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 72)
    helpButton:SetWidth(100)
    helpButton:SetHeight(25)
    helpButton:SetText("帮助")
    helpButton:SetScript("OnClick", function()
        F:ShowHelp()
    end)

    local resetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    resetButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 42)
    resetButton:SetWidth(140)
    resetButton:SetHeight(25)
    resetButton:SetText("重置窗口位置")
    resetButton:SetScript("OnClick", function()
        F:ResetPositions()
    end)

    self.settingsFrame = frame
end


function F:RegisterSlashCommands()
    SLASH_FRD1 = "/frd"
    SLASH_FRD2 = "/forcedisk"
    SlashCmdList["FRD"] = function(msg)
        if not F:X(true) then
            return
        end
        msg = msg or ""
        local lowerMsg = string.lower(msg)
        if lowerMsg == "enable" or lowerMsg == "on" then
            FRD_Settings.enabled = true
            if FRD_Settings.autoMode and F.inCombat then
                F:StartAutoCheck()
            end
            F:UpdateMonitorVisibility(true)
            F:UpdateMinimapIconState()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 插件已启用")
            return
        end
        if msg == "check" or msg == "" then
            F:CheckAndSwapDisk()
        elseif msg == "config" or msg == "settings" then
            FRDSettingsFrame:Show()
        elseif msg == "status" then
            local isEquipped = F:IsOffhandForceReactiveDisk()
            if isEquipped then
                local durability = F:GetOffhandDurability()
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 副手已装备力反馈盾牌, 耐久度: " .. string.format("%.1f", durability) .. "%")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 副手未装备力反馈盾牌")
            end
            local disks = F:FindAllDisksInBags()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 背包中找到 " .. table.getn(disks) .. " 个力反馈盾牌")
        elseif lowerMsg == "monitor" or lowerMsg == "mon" then
            FRD_Settings.monitorEnabled = not FRD_Settings.monitorEnabled
            F:UpdateMonitorVisibility(true)
            if FRD_Settings.monitorEnabled then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 战斗耐久监控: 已启用")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 战斗耐久监控: 已关闭")
            end
        elseif string.find(lowerMsg, "^monitor%s+") or string.find(lowerMsg, "^mon%s+") then
            local _, _, cmd, action = string.find(lowerMsg, "^(monitor|mon)%s+(%S+)")
            if action == "on" then
                FRD_Settings.monitorEnabled = true
                F:UpdateMonitorVisibility(true)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 战斗耐久监控: 已启用")
            elseif action == "off" then
                FRD_Settings.monitorEnabled = false
                F:UpdateMonitorVisibility(true)
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 战斗耐久监控: 已关闭")
            elseif action == "interval" and cmd and cmd ~= "" then
                local _, _, _, num = string.find(lowerMsg, "^(monitor|mon)%s+interval%s+(%d+%.?%d*)")
                local sec = tonumber(num)
                if sec then
                    if sec < 0.1 then sec = 0.1 end
                    if sec > 2.0 then sec = 2.0 end
                    FRD_Settings.monitorInterval = sec
                    F:UpdateMonitorVisibility(true)
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 监控刷新频率: " .. string.format("%.1f", sec) .. " 秒")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor interval 0.5")
                end
            elseif action == "ooc" then
                FRD_Settings.monitorShowOOC = not FRD_Settings.monitorShowOOC
                F:UpdateMonitorVisibility(true)
                if FRD_Settings.monitorShowOOC then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 脱战也显示监控: 已启用")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 脱战也显示监控: 已关闭")
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor  (切换开关)")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor on/off")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor interval 0.5")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor ooc  (脱战显示开关)")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件命令:|r")
            DEFAULT_CHAT_FRAME:AddMessage("/frd 或 /frd check - 检测并切换盾牌")
            DEFAULT_CHAT_FRAME:AddMessage("/frd config - 打开设置界面")
            DEFAULT_CHAT_FRAME:AddMessage("/frd status - 显示当前状态")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor - 切换战斗耐久监控")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor ooc - 脱战也显示监控")
        end
    end
end
