-- ForceReactiveDisk.lua
-- 力反馈盾牌管理插件 for WoW 1.12

local ADDON_NAME = "ForceReactiveDisk"
local FRD_VERSION = 2.0
local FORCE_REACTIVE_DISK_ID = 18168 -- 力反馈盾牌物品ID

-- 默认设置（会被SavedVariables覆盖）
FRD_Settings = {
    durabilityThreshold = 30,
    autoMode = false, -- 主动检测模式
    checkInterval = 2.0, -- 检测频率（秒）
    enabled = true, -- 插件开关
    economyShieldEnabled = false, -- 启用勤俭盾牌
    economyShieldThreshold = 50, -- 勤俭盾牌血量阈值(%)
    monitorEnabled = false, -- 战斗中显示耐久监控
    monitorInterval = 0.5, -- 监控刷新频率（秒）
    monitorShowOOC = false, -- 脱战后也显示监控
    repairReminderEnabled = true, -- 脱战时低耐久提醒
    minimap = {
        angle = 0,
        shown = true
    }
}

-- 创建主框架
local FRD = CreateFrame("Frame", "ForceReactiveDiskFrame", UIParent)
FRD:RegisterEvent("ADDON_LOADED")
FRD:RegisterEvent("PLAYER_ENTERING_WORLD")
FRD:RegisterEvent("PLAYER_REGEN_DISABLED") -- 进入战斗
FRD:RegisterEvent("PLAYER_REGEN_ENABLED") -- 离开战斗
FRD:RegisterEvent("BAG_UPDATE")
FRD:RegisterEvent("UNIT_INVENTORY_CHANGED")
FRD:RegisterEvent("UPDATE_INVENTORY_ALERTS")
FRD.timeSinceLastCheck = 0
FRD.inCombat = false
FRD.warnedAllBelowTwo = false
FRD.warnedEconomyShieldMissing = false

FRD:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- 确保设置已加载并设置默认值
        if not FRD_Settings then
            FRD_Settings = {}
        end
        local oldVersion = FRD_Settings.version or 0
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
        if FRD_Settings.economyShieldEnabled == nil then
            FRD_Settings.economyShieldEnabled = false
        end
        if not FRD_Settings.economyShieldThreshold then
            FRD_Settings.economyShieldThreshold = 50
        end
        if FRD_Settings.economyShieldItemId == nil and FRD_Settings.economyShieldItemLink then
            FRD_Settings.economyShieldItemId = FRD:GetItemIdFromLink(FRD_Settings.economyShieldItemLink)
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
        if not FRD_Settings.repairReminderPosition then
            FRD_Settings.repairReminderPosition = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 }
        end
        if not FRD_Settings.minimap then
            FRD_Settings.minimap = { angle = 0, shown = true }
        end
        if oldVersion < FRD_VERSION then
            -- 版本迁移时默认确保插件启用
            FRD_Settings.enabled = true
            FRD:MigrateSettings(oldVersion)
        end
        FRD_Settings.version = FRD_VERSION
        FRD:Initialize()
    elseif event == "PLAYER_ENTERING_WORLD" then
        FRD:UpdateMonitorVisibility(true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        FRD.inCombat = true
        FRD:HideRepairReminder()
        if FRD_Settings.autoMode and FRD_Settings.enabled then
            FRD:StartAutoCheck()
            if FRD_Settings.economyShieldEnabled then
                FRD:CheckAndSwapDisk(true)
            end
        end
        FRD:UpdateMonitorVisibility(true)
        FRD:UpdateMinimapIconState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        FRD.inCombat = false
        FRD:StopAutoCheck()
        if FRD_Settings.autoMode and FRD_Settings.enabled and FRD_Settings.economyShieldEnabled then
            FRD:CheckAndSwapDisk(true)
        end
        FRD:UpdateMonitorVisibility(true)
        FRD:CheckRepairReminder()
    elseif event == "BAG_UPDATE" or event == "UPDATE_INVENTORY_ALERTS" then
        FRD:UpdateMonitorText(false)
        FRD:CheckRepairReminder()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            FRD:UpdateMonitorText(false)
            FRD:CheckRepairReminder()
        end
    end
end)

-- 配置迁移（基于版本号）
function FRD:MigrateSettings(oldVersion)
    -- 示例：补齐新字段或矫正旧数据
    if oldVersion < 1.68 then
        -- 确保修理提醒位置存在
        if not FRD_Settings.repairReminderPosition then
            FRD_Settings.repairReminderPosition = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 }
        end
    end
    if oldVersion < 1.69 then
        if FRD_Settings.economyShieldEnabled == nil then
            FRD_Settings.economyShieldEnabled = false
        end
        if not FRD_Settings.economyShieldThreshold then
            FRD_Settings.economyShieldThreshold = 50
        end
    end
end

-- 初始化
function FRD:Initialize()
    -- 创建小地图按钮
    self:CreateMinimapButton()
    -- 创建设置界面
    self:CreateSettingsFrame()
    -- 创建耐久监控UI
    self:CreateMonitorFrame()
    -- 兼容旧版本光标API
    self:HookCursorPickup()
    -- 注册斜杠命令
    self:RegisterSlashCommands()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件已加载!|r 使用 /frd 或 /forcedisk 来管理盾牌")
    self:UpdateMonitorVisibility(true)
    self:UpdateMinimapIconState()
end

-- 创建耐久监控小窗（战斗中显示）
function FRD:CreateMonitorFrame()
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
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    frame.timeSinceLastUpdate = 0
    self.monitorFrame = frame
end

function FRD:StartMonitor()
    if not self.monitorFrame then
        self:CreateMonitorFrame()
    end

    self.monitorFrame.timeSinceLastUpdate = 0
    self.monitorFrame:SetScript("OnUpdate", function()
        FRD.monitorFrame.timeSinceLastUpdate = FRD.monitorFrame.timeSinceLastUpdate + arg1
        if FRD.monitorFrame.timeSinceLastUpdate >= (FRD_Settings.monitorInterval or 0.5) then
            FRD.monitorFrame.timeSinceLastUpdate = 0
            FRD:UpdateMonitorText(true)
        end
    end)
end

function FRD:StopMonitor()
    if self.monitorFrame then
        self.monitorFrame:SetScript("OnUpdate", nil)
    end
end

function FRD:UpdateMonitorVisibility(forceUpdateText)
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

function FRD:FormatDurabilityColor(durabilityPercent)
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

function FRD:UpdateMonitorText(force)
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
    local frdTotalDur = 0
    local frdCount = 0

    if offhandIsDisk then
        table.insert(entries, {
            label = "副手",
            durability = offhandDurability,
            texture = offhandTexture or "Interface\\Icons\\INV_Shield_21",
            equipped = true
        })
        frdTotalDur = frdTotalDur + (offhandDurability or 0)
        frdCount = frdCount + 1
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
                equipped = false,
                bag = d.bag,
                slot = d.slot
            })
            frdTotalDur = frdTotalDur + d.durability
            frdCount = frdCount + 1
        end
    end

    local totalInfo
    if frdCount > 0 then
        local totalPool = frdCount * 100
        totalInfo = string.format("总耐久: %.1f%% / %d%%", frdTotalDur, totalPool)
    else
        totalInfo = "总耐久: 无力反馈盾牌"
    end

    self.monitorFrame.header:SetText(totalInfo)

    local economyEntry = self:GetEconomyShieldMonitorEntry()
    if economyEntry then
        if frdCount > 0 then
            table.insert(entries, { isSpacer = true })
        end
        table.insert(entries, economyEntry)
    end

    local totalCount = table.getn(entries)

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
            iconFrame = CreateFrame("Button", nil, self.monitorFrame.iconContainer)
            iconFrame:SetWidth(iconSize)
            iconFrame:SetHeight(iconSize + 14)
            iconFrame:RegisterForClicks("LeftButtonUp")

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

            iconFrame:SetScript("OnClick", function()
                if this.isEconomy then
                    FRD:EquipEconomyShield(false)
                elseif this.bag and this.slot then
                    FRD:EquipDisk(this.bag, this.slot)
                end
            end)

            self.monitorFrame.icons[i] = iconFrame
        end

        local col = math.mod((i - 1), usedCols)
        local row = math.floor((i - 1) / usedCols)
        iconFrame:SetPoint("TOPLEFT", self.monitorFrame.iconContainer, "TOPLEFT", col * (iconSize + padding), -row * (iconSize + 18))

        if entry.isSpacer then
            iconFrame.icon:Hide()
            iconFrame.text:SetText("")
            iconFrame.bg:SetTexture(0, 0, 0, 0)
            iconFrame.bag = nil
            iconFrame.slot = nil
            iconFrame.isEconomy = nil
            iconFrame.isSpacer = true
            iconFrame:EnableMouse(false)
        else
            iconFrame.icon:Show()
            iconFrame.icon:SetTexture(entry.texture)
            if entry.isEconomy then
                local labelColor = entry.found and "|cff00ff00" or "|cff888888"
                iconFrame.text:SetText(labelColor .. "勤俭盾牌|r")
            else
                local colorCode = self:FormatDurabilityColor(entry.durability)
                iconFrame.text:SetText(colorCode .. string.format("%.0f", entry.durability) .. "%|r")
            end
            iconFrame.bag = entry.bag
            iconFrame.slot = entry.slot
            iconFrame.isEconomy = entry.isEconomy
            iconFrame.isSpacer = nil
            iconFrame:EnableMouse(true)

            if entry.equipped then
                iconFrame.bg:SetTexture(0, 0.5, 0, 0.5)
            else
                iconFrame.bg:SetTexture(0, 0, 0, 0.5)
            end
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

-- 重置可拖动小窗位置（监控与修理提示）
function FRD:ResetFramePositions()
    -- 监控小窗
    if not self.monitorFrame then
        self:CreateMonitorFrame()
    end
    if self.monitorFrame then
        self.monitorFrame:ClearAllPoints()
        self.monitorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    -- 修理提醒
    FRD_Settings.repairReminderPosition = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 }
    if self.repairReminderFrame then
        self.repairReminderFrame:ClearAllPoints()
        self.repairReminderFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 小窗口位置已重置")
end

-- 脱战后低耐久提醒
function FRD:CheckRepairReminder()
    if not FRD_Settings.enabled or not FRD_Settings.repairReminderEnabled then
        self:HideRepairReminder()
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
        if not self.inCombat then
            self:ShowRepairReminder()
        end
    else
        self:HideRepairReminder()
    end
end

function FRD:EnsureRepairReminderFrame()
    if self.repairReminderFrame then
        return
    end
    local frame = CreateFrame("Frame", "FRDRepairReminderFrame", UIParent)
    frame:SetWidth(400)
    frame:SetHeight(50)
    local pos = FRD_Settings.repairReminderPosition or { point = "TOP", relativePoint = "TOP", x = 0, y = -120 }
    frame:SetPoint(pos.point or "TOP", UIParent, pos.relativePoint or pos.point or "TOP", pos.x or 0, pos.y or -120)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = this:GetPoint()
        FRD_Settings.repairReminderPosition = {
            point = point or "TOP",
            relativePoint = relativePoint or point or "TOP",
            x = xOfs or 0,
            y = yOfs or -120
        }
    end)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetText("|cffff0000[FRD]|r 盾牌耐久低于90%，请尽快修理！")
    frame.text = text
    frame:Hide()
    self.repairReminderFrame = frame
end

function FRD:ShowRepairReminder()
    self:EnsureRepairReminderFrame()
    if self.repairReminderFrame then
        self.repairReminderFrame:Show()
    end
end

function FRD:HideRepairReminder()
    if self.repairReminderFrame then
        self.repairReminderFrame:Hide()
    end
end

-- 获取物品耐久度百分比（使用tooltip扫描）
function FRD:GetItemDurability(bag, slot)
    if not FRDScanTooltip then
        CreateFrame("GameTooltip", "FRDScanTooltip", nil, "GameTooltipTemplate")
        FRDScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    
    FRDScanTooltip:ClearLines()
    FRDScanTooltip:SetBagItem(bag, slot)
    
    -- 扫描tooltip文本查找耐久度
    for i = 1, FRDScanTooltip:NumLines() do
        local text = getglobal("FRDScanTooltipTextLeft" .. i):GetText()
        if text then
            -- 匹配 "耐久度 XX / YY" 或 "Durability XX / YY"
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
    
    return 100 -- 如果没有耐久度信息，假设为满耐久
end

-- 检查指定位置是否是力反馈盾牌
function FRD:IsForceReactiveDisk(bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    if itemLink then
        local _, _, itemId = string.find(itemLink, "item:(%d+)")
        return tonumber(itemId) == FORCE_REACTIVE_DISK_ID
    end
    return false
end

-- 查找背包中所有力反馈盾牌
function FRD:FindAllDisksInBags()
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

-- 检查副手是否装备力反馈盾牌
function FRD:IsOffhandForceReactiveDisk()
    local offhandLink = GetInventoryItemLink("player", 17) -- 17是副手槽位
    if offhandLink then
        local _, _, itemId = string.find(offhandLink, "item:(%d+)")
        return tonumber(itemId) == FORCE_REACTIVE_DISK_ID
    end
    return false
end

-- 获取副手耐久度
function FRD:GetOffhandDurability()
    if not FRDScanTooltip then
        CreateFrame("GameTooltip", "FRDScanTooltip", nil, "GameTooltipTemplate")
        FRDScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    
    FRDScanTooltip:ClearLines()
    FRDScanTooltip:SetInventoryItem("player", 17)
    
    -- 扫描tooltip文本查找耐久度
    for i = 1, FRDScanTooltip:NumLines() do
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

-- 从物品链接获取物品ID
function FRD:GetItemIdFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local _, _, itemId = string.find(itemLink, "item:(%d+)")
    return tonumber(itemId)
end

-- 从物品链接获取物品名称
function FRD:GetItemNameFromLink(itemLink)
    if not itemLink then
        return nil
    end
    return string.match(itemLink, "%[(.+)%]")
end

-- 获取勤俭盾牌物品ID
function FRD:GetEconomyShieldItemId()
    if FRD_Settings.economyShieldItemId then
        return FRD_Settings.economyShieldItemId
    end
    if FRD_Settings.economyShieldItemLink then
        local itemId = self:GetItemIdFromLink(FRD_Settings.economyShieldItemLink)
        FRD_Settings.economyShieldItemId = itemId
        return itemId
    end
    return nil
end

-- 旧版本兼容：记录光标物品信息
function FRD:HookCursorPickup()
    if self.cursorHooked then
        return
    end
    self.cursorHooked = true

    if PickupContainerItem and not self.originalPickupContainerItem then
        self.originalPickupContainerItem = PickupContainerItem
        PickupContainerItem = function(bag, slot)
            if FRD then
                FRD.cursorItemLink = GetContainerItemLink(bag, slot)
                FRD.cursorItemId = FRD:GetItemIdFromLink(FRD.cursorItemLink)
            end
            FRD.originalPickupContainerItem(bag, slot)
        end
    end

    if PickupInventoryItem and not self.originalPickupInventoryItem then
        self.originalPickupInventoryItem = PickupInventoryItem
        PickupInventoryItem = function(slot)
            if FRD then
                FRD.cursorItemLink = GetInventoryItemLink("player", slot)
                FRD.cursorItemId = FRD:GetItemIdFromLink(FRD.cursorItemLink)
            end
            FRD.originalPickupInventoryItem(slot)
        end
    end
end

function FRD:ClearCursorItemCache()
    self.cursorItemId = nil
    self.cursorItemLink = nil
end

-- 获取光标物品信息（兼容无 GetCursorInfo 环境）
function FRD:GetCursorItemInfo()
    if GetCursorInfo then
        local cursorType, itemId, itemLink = GetCursorInfo()
        if cursorType ~= "item" then
            return nil
        end
        if not itemId and itemLink then
            itemId = self:GetItemIdFromLink(itemLink)
        end
        return itemId, itemLink
    end

    if CursorHasItem and CursorHasItem() then
        local itemId = self.cursorItemId
        local itemLink = self.cursorItemLink
        if not itemId and itemLink then
            itemId = self:GetItemIdFromLink(itemLink)
        end
        return itemId, itemLink
    end

    return nil
end

-- 获取玩家当前血量百分比
function FRD:GetPlayerHealthPercent()
    local maxHealth = UnitHealthMax("player")
    if not maxHealth or maxHealth <= 0 then
        return 0
    end
    return (UnitHealth("player") / maxHealth) * 100
end

-- 查找勤俭盾牌（副手优先，其次背包）
function FRD:FindEconomyShield()
    local itemId = self:GetEconomyShieldItemId()
    if not itemId then
        return nil
    end

    local offhandLink = GetInventoryItemLink("player", 17)
    if offhandLink then
        local offhandId = self:GetItemIdFromLink(offhandLink)
        if offhandId and offhandId == itemId and offhandId ~= FORCE_REACTIVE_DISK_ID then
            self.warnedEconomyShieldMissing = false
            return {
                equipped = true,
                durability = self:GetOffhandDurability(),
                texture = GetInventoryItemTexture("player", 17)
            }
        end
    end

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local id = self:GetItemIdFromLink(link)
                if id and id == itemId and id ~= FORCE_REACTIVE_DISK_ID then
                    local texture
                    if GetContainerItemInfo then
                        local tex = GetContainerItemInfo(bag, slot)
                        if type(tex) == "table" then
                            texture = tex.icon
                        else
                            texture = tex
                        end
                    end
                    self.warnedEconomyShieldMissing = false
                    return {
                        bag = bag,
                        slot = slot,
                        durability = self:GetItemDurability(bag, slot),
                        texture = texture or "Interface\\Icons\\INV_Shield_05",
                        equipped = false
                    }
                end
            end
        end
    end

    return nil
end

-- 装备勤俭盾牌
function FRD:EquipEconomyShield(silent)
    local economy = self:FindEconomyShield()
    if not economy then
        return false
    end
    if economy.equipped then
        return true
    end
    if economy.bag and economy.slot then
        self:EquipDisk(economy.bag, economy.slot)
        if not silent then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已装备勤俭盾牌")
        end
        return true
    end
    return false
end

-- 勤俭盾牌丢失提示
function FRD:WarnEconomyShieldMissing()
    if self.warnedEconomyShieldMissing then
        return
    end
    self.warnedEconomyShieldMissing = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 未找到勤俭盾牌，已回退到力反馈盾牌逻辑")
end

-- 勤俭盾牌逻辑处理，返回是否已处理
function FRD:HandleEconomyShieldSwap(silent)
    if not FRD_Settings.economyShieldEnabled then
        return false
    end
    if not self:GetEconomyShieldItemId() then
        return false
    end

    if self.inCombat then
        local threshold = FRD_Settings.economyShieldThreshold or 50
        if threshold < 1 then threshold = 1 end
        if threshold > 100 then threshold = 100 end
        local healthPercent = self:GetPlayerHealthPercent()
        if healthPercent > threshold then
            if self:EquipEconomyShield(silent) then
                return true
            end
            self:WarnEconomyShieldMissing()
        end
        return false
    end

    if self:EquipEconomyShield(silent) then
        return true
    end
    self:WarnEconomyShieldMissing()
    return false
end

-- 勤俭盾牌监控条目
function FRD:GetEconomyShieldMonitorEntry()
    if not FRD_Settings.economyShieldEnabled then
        return nil
    end
    if not self:GetEconomyShieldItemId() then
        return nil
    end

    local info = self:FindEconomyShield()
    local texture = FRD_Settings.economyShieldTexture or "Interface\\Icons\\INV_Shield_05"
    local entry = {
        label = "勤俭盾牌",
        texture = texture,
        durability = nil,
        equipped = false,
        isEconomy = true,
        found = false
    }
    if info then
        entry.texture = info.texture or texture
        entry.durability = info.durability
        entry.equipped = info.equipped
        entry.bag = info.bag
        entry.slot = info.slot
        entry.found = true
    end
    return entry
end

-- 力反馈盾牌全部损坏时强制切换勤俭盾牌
function FRD:TryEquipEconomyShieldWhenAllDisksBroken(silent, offhandIsDisk, currentDurability, disks)
    if not FRD_Settings.economyShieldEnabled then
        return false
    end
    if not self:GetEconomyShieldItemId() then
        return false
    end

    local totalDisks = table.getn(disks) + (offhandIsDisk and 1 or 0)
    if totalDisks <= 0 then
        return false
    end

    local allBroken = true
    if offhandIsDisk and currentDurability and currentDurability > 0 then
        allBroken = false
    end
    for i = 1, table.getn(disks) do
        if disks[i].durability > 0 then
            allBroken = false
            break
        end
    end

    if not allBroken then
        return false
    end

    local economy = self:FindEconomyShield()
    if economy then
        if economy.equipped then
            return true
        end
        if economy.bag and economy.slot then
            self:EquipDisk(economy.bag, economy.slot)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 所有力反馈盾牌耐久为0，已强制切换到勤俭盾牌")
            end
            return true
        end
    end

    return false
end

-- 装备盾牌
function FRD:EquipDisk(bag, slot)
    PickupContainerItem(bag, slot)
    PickupInventoryItem(17) -- 副手槽位
end

-- 开始自动检测
function FRD:StartAutoCheck()
    self.timeSinceLastCheck = 0
    self:SetScript("OnUpdate", function(elapsed)
        FRD.timeSinceLastCheck = FRD.timeSinceLastCheck + arg1
        if FRD.timeSinceLastCheck >= FRD_Settings.checkInterval then
            FRD.timeSinceLastCheck = 0
            FRD:CheckAndSwapDisk(true) -- 静默模式，不输出聊天信息
        end
    end)
end

-- 停止自动检测
function FRD:StopAutoCheck()
    self:SetScript("OnUpdate", nil)
end

-- 主要检测和切换逻辑
function FRD:CheckAndSwapDisk(silent)
    if not FRD_Settings.enabled then
        if not silent then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 插件已停用，右键小地图图标可重新启用")
        end
        return
    end

    if self:HandleEconomyShieldSwap(silent) then
        return
    end

    local offhandIsDisk = self:IsOffhandForceReactiveDisk()
    local currentDurability = nil
    if offhandIsDisk then
        currentDurability = self:GetOffhandDurability()
    end
    local disks = self:FindAllDisksInBags()
    local bagCount = table.getn(disks)

    if self:TryEquipEconomyShieldWhenAllDisksBroken(silent, offhandIsDisk, currentDurability, disks) then
        return
    end

    -- 检查副手是否装备力反馈盾牌
    if not offhandIsDisk then
        -- 副手没有装备力反馈盾牌，寻找背包中的盾牌
        if bagCount > 0 then
            -- 按耐久度排序，选择耐久度最高的
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
    
    -- 副手已装备力反馈盾牌,检查耐久度
    local threshold = FRD_Settings.durabilityThreshold or 30

    if bagCount > 0 then
        table.sort(disks, function(a, b) return a.durability > b.durability end)
    end

    local bestDisk = bagCount > 0 and disks[1] or nil
    local bestDurability = bestDisk and bestDisk.durability or 0
    local maxDurability = currentDurability
    if bestDurability > maxDurability then
        maxDurability = bestDurability
    end
    local allBelowThreshold = (currentDurability < threshold) and (bestDurability < threshold) -- 只有当所有盾牌都低于阈值时才启用2%紧急逻辑

    -- 所有盾牌都低于2%时，一次性提醒并按残余耐久依次用尽
    if allBelowThreshold and maxDurability <= 2 then
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

        -- 所有盾牌都低于阈值时，使用“低于2%再切”的紧急逻辑
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

        -- 仍有盾牌高于阈值，立即切换到最佳盾牌
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

-- 创建小地图按钮
function FRD:CreateMinimapButton()
    local button = CreateFrame("Button", "FRDMinimapButton", Minimap)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8) -- 确保位于更高层级
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52, -52)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- 先注册点击，再注册拖拽
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    
    local icon = button:CreateTexture("FRDMinimapIcon", "BACKGROUND")
    icon:SetWidth(26)
    icon:SetHeight(26)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDarnassus")
    button.icon = icon

    local disabledOverlay = button:CreateTexture("FRDMinimapDisabledOverlay", "ARTWORK")
    disabledOverlay:SetWidth(32)
    disabledOverlay:SetHeight(32)
    disabledOverlay:SetPoint("CENTER", button, "CENTER", 0, 0)
    disabledOverlay:SetTexture("Interface\\Common\\CancelRed")
    disabledOverlay:SetBlendMode("ADD")
    disabledOverlay:Hide()
    button.disabledOverlay = disabledOverlay
    
    button:SetScript("OnClick", function()
        local mouseBtn = arg1 -- 1.12 环境使用全局 arg1
        if mouseBtn == "LeftButton" then
            FRDSettingsFrame:Show()
        elseif mouseBtn == "RightButton" then
            FRD_Settings.enabled = not FRD_Settings.enabled
            if FRD_Settings.enabled then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 插件已启用")
                FRD:UpdateMonitorVisibility(true)
                if FRD_Settings.autoMode and FRD.inCombat then
                    FRD:StartAutoCheck()
                end
                FRD:CheckRepairReminder()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 插件已停用")
                FRD:StopAutoCheck()
                FRD:UpdateMonitorVisibility(true)
                FRD:HideRepairReminder()
            end
            FRD:UpdateMinimapIconState()
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
    
    -- 拖拽脚本
    button:SetScript("OnDragStart", function()
        this:SetScript("OnUpdate", FRD.MinimapButton_OnUpdate)
    end)
    button:SetScript("OnDragStop", function()
        this:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    
    -- 延迟更新位置和状态，确保界面加载完毕
    self:ScheduleTimer(function()
        FRD:UpdateMinimapButtonPosition()
        FRD:UpdateMinimapIconState()
    end, 0.5)
end

-- 简单的延迟执行函数
function FRD:ScheduleTimer(func, delay)
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed >= delay then
            func()
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

-- 小地图按钮拖拽更新
function FRD.MinimapButton_OnUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    
    local angle = math.deg(math.atan2(py - my, px - mx))
    FRD_Settings.minimap.angle = angle
    
    FRD:UpdateMinimapButtonPosition()
end

-- 更新小地图按钮位置
function FRD:UpdateMinimapButtonPosition()
    local angle = math.rad(FRD_Settings.minimap.angle or 0)
    local x = 80 * math.cos(angle)
    local y = 80 * math.sin(angle)
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- 更新小地图图标状态（启用/禁用时高亮或变暗）
function FRD:UpdateMinimapIconState()
    if not self.minimapButton then
        return
    end
    local icon = self.minimapButton.icon
    local offOverlay = self.minimapButton.disabledOverlay
    if not icon then return end

    if FRD_Settings.enabled then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
        if offOverlay then offOverlay:Hide() end
    else
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.4, 0.4, 0.4, 0.8)
        if offOverlay then offOverlay:Show() end
    end
end

-- 构建勤俭盾牌信息
function FRD:BuildEconomyShieldInfo(itemId, itemLink)
    if not itemId then
        return nil
    end
    if itemId == FORCE_REACTIVE_DISK_ID then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 力反馈盾牌不能设置为勤俭盾牌")
        return nil
    end

    local name = self:GetItemNameFromLink(itemLink)
    local texture = nil
    if GetItemInfo then
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
        if not name then
            name = itemName
        end
        texture = itemTexture
    end
    if not texture then
        texture = "Interface\\Icons\\INV_Shield_05"
    end
    if not name then
        name = "未知盾牌"
    end

    return {
        itemId = itemId,
        itemLink = itemLink,
        name = name,
        texture = texture
    }
end

-- 更新勤俭盾牌选择显示
function FRD:UpdateEconomyShieldSelectionDisplay()
    if not self.settingsFrame or not self.settingsFrame.economyShieldButton then
        return
    end
    local pending = self.settingsFrame.economyShieldPending
    local texture = (pending and pending.texture) or "Interface\\Icons\\INV_Shield_05"
    local name = (pending and pending.name) or "未设置"
    self.settingsFrame.economyShieldButton.icon:SetTexture(texture)
    self.settingsFrame.economyShieldName:SetText(name)
end

-- 设置勤俭盾牌临时选择
function FRD:SetEconomyShieldPending(info)
    if not self.settingsFrame then
        return
    end
    self.settingsFrame.economyShieldPending = info
    self:UpdateEconomyShieldSelectionDisplay()
end

-- 清空勤俭盾牌临时选择
function FRD:ClearEconomyShieldPending()
    if not self.settingsFrame then
        return
    end
    self.settingsFrame.economyShieldPending = nil
    self:UpdateEconomyShieldSelectionDisplay()
end

-- 重置勤俭盾牌临时选择
function FRD:ResetEconomyShieldPendingFromSettings()
    if not self.settingsFrame then
        return
    end
    if FRD_Settings.economyShieldItemId then
        local info = {
            itemId = FRD_Settings.economyShieldItemId,
            itemLink = FRD_Settings.economyShieldItemLink,
            name = FRD_Settings.economyShieldName,
            texture = FRD_Settings.economyShieldTexture
        }
        if GetItemInfo and info.itemId and (not info.name or not info.texture) then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(info.itemId)
            if not info.name then
                info.name = itemName
            end
            if not info.texture then
                info.texture = itemTexture
            end
        end
        if not info.texture then
            info.texture = "Interface\\Icons\\INV_Shield_05"
        end
        if not info.name then
            info.name = "未知盾牌"
        end
        self.settingsFrame.economyShieldPending = info
    else
        self.settingsFrame.economyShieldPending = nil
    end
    self:UpdateEconomyShieldSelectionDisplay()
end

-- 应用勤俭盾牌设置
function FRD:ApplyEconomyShieldPendingToSettings()
    local pending = self.settingsFrame and self.settingsFrame.economyShieldPending
    if pending then
        FRD_Settings.economyShieldItemId = pending.itemId
        FRD_Settings.economyShieldItemLink = pending.itemLink
        FRD_Settings.economyShieldName = pending.name
        FRD_Settings.economyShieldTexture = pending.texture
    else
        FRD_Settings.economyShieldItemId = nil
        FRD_Settings.economyShieldItemLink = nil
        FRD_Settings.economyShieldName = nil
        FRD_Settings.economyShieldTexture = nil
    end
    self.warnedEconomyShieldMissing = false
end

-- 从光标设置勤俭盾牌
function FRD:TrySetEconomyShieldFromCursor()
    local itemId, itemLink = self:GetCursorItemInfo()
    if not itemId then
        return
    end
    local info = self:BuildEconomyShieldInfo(itemId, itemLink)
    if info then
        self:SetEconomyShieldPending(info)
    end
    ClearCursor()
    self:ClearCursorItemCache()
end

-- 从当前副手设置勤俭盾牌
function FRD:TrySetEconomyShieldFromOffhand()
    local offhandLink = GetInventoryItemLink("player", 17)
    if not offhandLink then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前副手为空")
        return
    end
    local itemId = self:GetItemIdFromLink(offhandLink)
    local info = self:BuildEconomyShieldInfo(itemId, offhandLink)
    if info then
        self:SetEconomyShieldPending(info)
    end
end

-- 创建设置界面
function FRD:CreateSettingsFrame()
    local frame = CreateFrame("Frame", "FRDSettingsFrame", UIParent)
    frame:SetWidth(350)
    frame:SetHeight(560)
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
    
    -- 标题
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText("力反馈盾牌管理设置")
    
    -- 耐久度阈值标签
    local label1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label1:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -60)
    label1:SetText("切换耐久度阈值 (%):")
    
    -- 耐久度滑块
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
    
    -- 主动模式复选框
    local autoCheckbox = CreateFrame("CheckButton", "FRDAutoModeCheckbox", frame, "UICheckButtonTemplate")
    autoCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -140)
    autoCheckbox:SetWidth(24)
    autoCheckbox:SetHeight(24)
    autoCheckbox:SetChecked(FRD_Settings.autoMode)
    
    local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoLabel:SetPoint("LEFT", autoCheckbox, "RIGHT", 5, 0)
    autoLabel:SetWidth(260)
    autoLabel:SetJustifyH("LEFT")
    autoLabel:SetText("启用主动检测模式（战斗中自动检测）")
    
    autoCheckbox:SetScript("OnClick", function()
        -- 复选框点击时不立即保存，等待确认按钮
    end)
    
    -- 勤俭盾牌模块
    local economyPanel = CreateFrame("Frame", "FRDEconomyShieldPanel", frame)
    economyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -160)
    economyPanel:SetWidth(310)
    economyPanel:SetHeight(160)
    economyPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    economyPanel:SetBackdropColor(0, 0, 0, 0.35)

    local economyTitle = economyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    economyTitle:SetPoint("TOPLEFT", economyPanel, "TOPLEFT", 10, -8)
    economyTitle:SetText("勤俭盾牌模块")

    -- 勤俭盾牌开关
    local economyCheckbox = CreateFrame("CheckButton", "FRDEconomyShieldCheckbox", economyPanel, "UICheckButtonTemplate")
    economyCheckbox:SetPoint("TOPLEFT", economyPanel, "TOPLEFT", 10, -26)
    economyCheckbox:SetWidth(24)
    economyCheckbox:SetHeight(24)
    economyCheckbox:SetChecked(FRD_Settings.economyShieldEnabled)

    local economyLabel = economyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    economyLabel:SetPoint("LEFT", economyCheckbox, "RIGHT", 5, 0)
    economyLabel:SetWidth(255)
    economyLabel:SetJustifyH("LEFT")
    economyLabel:SetText("启用勤俭盾牌（低血量前使用非力反馈盾牌）")

    -- 勤俭盾牌血量阈值
    local economyLabel2 = economyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    economyLabel2:SetPoint("TOPLEFT", economyPanel, "TOPLEFT", 10, -50)
    economyLabel2:SetText("勤俭盾牌血量阈值 (%):")

    local economySlider = CreateFrame("Slider", "FRDEconomyThresholdSlider", economyPanel, "OptionsSliderTemplate")
    economySlider:SetPoint("TOP", economyPanel, "TOP", 0, -70)
    economySlider:SetMinMaxValues(1, 100)
    economySlider:SetValueStep(1)
    economySlider:SetWidth(250)
    getglobal(economySlider:GetName() .. "Low"):SetText("1%")
    getglobal(economySlider:GetName() .. "High"):SetText("100%")

    local economyThresholdValue = FRD_Settings.economyShieldThreshold or 50
    if economyThresholdValue < 1 then economyThresholdValue = 1 end
    if economyThresholdValue > 100 then economyThresholdValue = 100 end

    economySlider:SetValue(economyThresholdValue)
    getglobal(economySlider:GetName() .. "Text"):SetText(economyThresholdValue .. "%")

    economySlider:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(newValue .. "%")
    end)

    -- 勤俭盾牌设置
    local economyLabel3 = economyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    economyLabel3:SetPoint("TOPLEFT", economyPanel, "TOPLEFT", 10, -98)
    economyLabel3:SetText("勤俭盾牌设置:")

    local economyButton = CreateFrame("Button", "FRDEconomyShieldButton", economyPanel)
    economyButton:SetPoint("TOPLEFT", economyPanel, "TOPLEFT", 10, -116)
    economyButton:SetWidth(32)
    economyButton:SetHeight(32)
    economyButton:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    economyButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    economyButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    economyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    economyButton:RegisterForDrag("LeftButton")

    local economyIcon = economyButton:CreateTexture(nil, "ARTWORK")
    economyIcon:SetWidth(26)
    economyIcon:SetHeight(26)
    economyIcon:SetPoint("CENTER", economyButton, "CENTER", 0, 0)
    economyButton.icon = economyIcon

    economyButton:SetScript("OnReceiveDrag", function()
        FRD:TrySetEconomyShieldFromCursor()
    end)
    economyButton:SetScript("OnClick", function()
        local mouseBtn = arg1
        if mouseBtn == "RightButton" then
            FRD:ClearEconomyShieldPending()
            return
        end
        local itemId = FRD:GetCursorItemInfo()
        if itemId then
            FRD:TrySetEconomyShieldFromCursor()
        else
            FRD:TrySetEconomyShieldFromOffhand()
        end
    end)
    economyButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("勤俭盾牌设置", 1, 1, 1)
        GameTooltip:AddLine("左键: 使用当前副手", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("拖拽: 从背包选择盾牌", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("右键: 清除设置", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    economyButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local economyName = economyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    economyName:SetPoint("LEFT", economyButton, "RIGHT", 8, 0)
    economyName:SetWidth(210)
    economyName:SetJustifyH("LEFT")
    economyName:SetText("未设置")

    frame.economyShieldButton = economyButton
    frame.economyShieldName = economyName

    -- 检测频率标签
    local label2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -330)
    label2:SetWidth(130)
    label2:SetJustifyH("LEFT")
    label2:SetText("检测频率(秒)")
    
    -- 检测频率滑块
    local slider2 = CreateFrame("Slider", "FRDIntervalSlider", frame, "OptionsSliderTemplate")
    slider2:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -350)
    slider2:SetMinMaxValues(0.1, 10)
    slider2:SetValueStep(0.1)
    slider2:SetWidth(130)
    getglobal(slider2:GetName() .. "Low"):SetText("0.1")
    getglobal(slider2:GetName() .. "High"):SetText("10")
    
    -- 确保值在有效范围内
    local intervalValue = FRD_Settings.checkInterval or 2.0
    if intervalValue < 0.1 then intervalValue = 0.1 end
    if intervalValue > 10 then intervalValue = 10 end
    
    slider2:SetValue(intervalValue)
    getglobal(slider2:GetName() .. "Text"):SetText(string.format("%.1f秒", intervalValue))
    
    slider2:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(string.format("%.1f秒", newValue))
    end)

    -- 耐久监控复选框
    local monitorCheckbox = CreateFrame("CheckButton", "FRDMonitorCheckbox", frame, "UICheckButtonTemplate")
    monitorCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -390)
    monitorCheckbox:SetWidth(24)
    monitorCheckbox:SetHeight(24)
    monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)

    local monitorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorLabel:SetPoint("LEFT", monitorCheckbox, "RIGHT", 5, 0)
    monitorLabel:SetWidth(260)
    monitorLabel:SetJustifyH("LEFT")
    monitorLabel:SetText("启用战斗耐久监控（显示小窗）")

    -- 监控刷新频率标签
    local label3 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label3:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -330)
    label3:SetWidth(130)
    label3:SetJustifyH("LEFT")
    label3:SetText("监控刷新(秒)")

    -- 监控刷新频率滑块
    local slider3 = CreateFrame("Slider", "FRDMonitorIntervalSlider", frame, "OptionsSliderTemplate")
    slider3:SetPoint("TOPLEFT", frame, "TOPLEFT", 180, -350)
    slider3:SetMinMaxValues(0.1, 2.0)
    slider3:SetValueStep(0.1)
    slider3:SetWidth(130)
    getglobal(slider3:GetName() .. "Low"):SetText("0.1")
    getglobal(slider3:GetName() .. "High"):SetText("2.0")

    local monitorIntervalValue = FRD_Settings.monitorInterval or 0.5
    if monitorIntervalValue < 0.1 then monitorIntervalValue = 0.1 end
    if monitorIntervalValue > 2.0 then monitorIntervalValue = 2.0 end

    slider3:SetValue(monitorIntervalValue)
    getglobal(slider3:GetName() .. "Text"):SetText(string.format("%.1f秒", monitorIntervalValue))

    slider3:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(string.format("%.1f秒", newValue))
    end)
    
    -- 保存设置的临时变量
    frame.tempSettings = {
        durabilityThreshold = FRD_Settings.durabilityThreshold,
        autoMode = FRD_Settings.autoMode,
        economyShieldEnabled = FRD_Settings.economyShieldEnabled,
        economyShieldThreshold = economyThresholdValue,
        checkInterval = intervalValue,
        monitorEnabled = FRD_Settings.monitorEnabled,
        monitorInterval = monitorIntervalValue,
        monitorShowOOC = FRD_Settings.monitorShowOOC,
        repairReminderEnabled = FRD_Settings.repairReminderEnabled
    }

    -- 脱战也显示监控复选框
    local monitorOOCCheckbox = CreateFrame("CheckButton", "FRDMonitorOOCCheckbox", frame, "UICheckButtonTemplate")
    monitorOOCCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -420)
    monitorOOCCheckbox:SetWidth(24)
    monitorOOCCheckbox:SetHeight(24)
    monitorOOCCheckbox:SetChecked(FRD_Settings.monitorShowOOC)

    local monitorOOCLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorOOCLabel:SetPoint("LEFT", monitorOOCCheckbox, "RIGHT", 5, 0)
    monitorOOCLabel:SetWidth(260)
    monitorOOCLabel:SetJustifyH("LEFT")
    monitorOOCLabel:SetText("脱战也显示盾牌耐久监控")

    -- 脱战低耐久修理提醒复选框
    local repairCheckbox = CreateFrame("CheckButton", "FRDRepairCheckbox", frame, "UICheckButtonTemplate")
    repairCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -450)
    repairCheckbox:SetWidth(24)
    repairCheckbox:SetHeight(24)
    repairCheckbox:SetChecked(FRD_Settings.repairReminderEnabled)

    local repairLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    repairLabel:SetPoint("LEFT", repairCheckbox, "RIGHT", 5, 0)
    repairLabel:SetWidth(260)
    repairLabel:SetJustifyH("LEFT")
    repairLabel:SetText("脱战后若盾牌低于90%提醒修理")
    
    -- 确认按钮
    local confirmButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    confirmButton:SetPoint("BOTTOM", frame, "BOTTOM", -55, 20)
    confirmButton:SetWidth(100)
    confirmButton:SetHeight(25)
    confirmButton:SetText("确认")
    confirmButton:SetScript("OnClick", function()
        -- 保存设置
        FRD_Settings.durabilityThreshold = slider1:GetValue()
        FRD_Settings.autoMode = autoCheckbox:GetChecked() == 1
        FRD_Settings.economyShieldEnabled = economyCheckbox:GetChecked() == 1
        FRD_Settings.economyShieldThreshold = economySlider:GetValue()
        FRD_Settings.checkInterval = slider2:GetValue()
        FRD_Settings.monitorEnabled = monitorCheckbox:GetChecked() == 1
        FRD_Settings.monitorInterval = slider3:GetValue()
        FRD_Settings.monitorShowOOC = monitorOOCCheckbox:GetChecked() == 1
        FRD_Settings.repairReminderEnabled = repairCheckbox:GetChecked() == 1
        FRD:ApplyEconomyShieldPendingToSettings()
        
        -- 如果主动模式状态改变，更新检测状态
        if FRD_Settings.autoMode and FRD.inCombat then
            FRD:StartAutoCheck()
        elseif not FRD_Settings.autoMode then
            FRD:StopAutoCheck()
        end

        FRD:UpdateMonitorVisibility(true)
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 设置已保存")
        frame:Hide()
    end)
    
    -- 关闭按钮
    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 55, 20)
    closeButton:SetWidth(100)
    closeButton:SetHeight(25)
    closeButton:SetText("取消")
    closeButton:SetScript("OnClick", function()
        -- 恢复原始设置
        slider1:SetValue(FRD_Settings.durabilityThreshold)
        autoCheckbox:SetChecked(FRD_Settings.autoMode)
        economyCheckbox:SetChecked(FRD_Settings.economyShieldEnabled)
        local resetEconomyValue = FRD_Settings.economyShieldThreshold or 50
        if resetEconomyValue < 1 then resetEconomyValue = 1 end
        if resetEconomyValue > 100 then resetEconomyValue = 100 end
        economySlider:SetValue(resetEconomyValue)
        slider2:SetValue(FRD_Settings.checkInterval)
        monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)
        slider3:SetValue(FRD_Settings.monitorInterval or 0.5)
        monitorOOCCheckbox:SetChecked(FRD_Settings.monitorShowOOC)
        repairCheckbox:SetChecked(FRD_Settings.repairReminderEnabled)
        FRD:ResetEconomyShieldPendingFromSettings()
        frame:Hide()
    end)

    -- 帮助按钮
    local helpButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    helpButton:SetPoint("BOTTOM", frame, "BOTTOM", 60, 60)
    helpButton:SetWidth(100)
    helpButton:SetHeight(22)
    helpButton:SetText("帮助")

    -- 重置位置按钮（与帮助同一行）
    local resetPosButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    resetPosButton:SetPoint("BOTTOM", frame, "BOTTOM", -60, 60)
    resetPosButton:SetWidth(120)
    resetPosButton:SetHeight(22)
    resetPosButton:SetText("重置窗口位置")
    resetPosButton:SetScript("OnClick", function()
        FRD:ResetFramePositions()
    end)

    -- 帮助内容框
    local helpFrame = CreateFrame("Frame", "FRDHelpFrame", frame)
    helpFrame:SetWidth(380)
    helpFrame:SetHeight(480)
    -- 将帮助窗口放在设置框右侧，避免遮挡功能区
    helpFrame:ClearAllPoints()
    helpFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    helpFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    helpFrame:Hide()

    local helpTitle = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    helpTitle:SetPoint("TOP", helpFrame, "TOP", 0, -18)
    helpTitle:SetText("帮助信息")

    local helpText = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", helpFrame, "TOPLEFT", 16, -46)
    helpText:SetWidth(340)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(table.concat({
        "插件功能简介",
        "· 自动切换力反馈盾牌（需背包有多块）；单块仅监控，不自动切换。",
        "· 勾选主动模式：战斗中自动检测并切换盾牌。",
        "· 勤俭盾牌：战斗中血量高于阈值使用指定非力反馈盾牌，低于阈值后切回力反馈盾牌。",
        "· 勤俭盾牌设置：拖拽背包盾牌到图标或点击图标使用当前副手，右键清除。",
        "· 如果不希望主动侦测，或者自动模式遇到使用问题，可将 /frd 绑定技能宏触发检测。",
        "· 小地图图标：右键可切换插件开关。",
        "",
        "· 作者：安娜希尔",
        "",
        "设置建议",
        "· 阈值：建议 15%。",
        "· 刷新频率：建议 0.4 秒。",
        "",
        "命令使用说明",
        "· /frd on            启用插件",
        "· /frd off           停用插件",
        "· /frd               被动模式：按逻辑检测并切换，可绑定宏",
        "· /frd config        打开设置界面",
        "· /frd reset         重置监控与修理提醒位置",
        "· /frd status        显示副手状态与背包盾牌数量",
        "· /frd monitor|mon   切换战斗耐久监控开/关",
        "· /frd monitor on|off   显式打开/关闭监控",
        "· /frd monitor interval <秒>  (0.1–2.0) 设置刷新频率",
        "· /frd monitor ooc   切换脱战显示监控"
    }, "\n"))

    local helpClose = CreateFrame("Button", nil, helpFrame, "GameMenuButtonTemplate")
    helpClose:SetPoint("BOTTOM", helpFrame, "BOTTOM", 0, 16)
    helpClose:SetWidth(90)
    helpClose:SetHeight(22)
    helpClose:SetText("关闭")
    helpClose:SetScript("OnClick", function()
        helpFrame:Hide()
    end)

    helpButton:SetScript("OnClick", function()
        if helpFrame:IsShown() then
            helpFrame:Hide()
        else
            helpFrame:Show()
        end
    end)
    
    self.settingsFrame = frame
    self:ResetEconomyShieldPendingFromSettings()
end

-- 注册斜杠命令
function FRD:RegisterSlashCommands()
    SLASH_FRD1 = "/frd"
    SLASH_FRD2 = "/forcedisk"
    SlashCmdList["FRD"] = function(msg)
        msg = msg or ""
        local lowerMsg = string.lower(msg)
        if msg == "check" or msg == "" then
            FRD:CheckAndSwapDisk()
        elseif msg == "config" or msg == "settings" then
            FRDSettingsFrame:Show()
        elseif lowerMsg == "on" then
            FRD_Settings.enabled = true
            FRD:UpdateMonitorVisibility(true)
            FRD:UpdateMinimapIconState()
            if FRD_Settings.autoMode and FRD.inCombat then
                FRD:StartAutoCheck()
            end
            FRD:CheckRepairReminder()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 插件已启用")
        elseif lowerMsg == "off" then
            FRD_Settings.enabled = false
            FRD:StopAutoCheck()
            FRD:UpdateMonitorVisibility(true)
            FRD:HideRepairReminder()
            FRD:UpdateMinimapIconState()
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 插件已停用")
        elseif lowerMsg == "help" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 命令清单：")
            DEFAULT_CHAT_FRAME:AddMessage("/frd 或 /frd check - 检测并切换盾牌（被动模式，可绑定宏）")
            DEFAULT_CHAT_FRAME:AddMessage("/frd on / off - 启用/停用插件")
            DEFAULT_CHAT_FRAME:AddMessage("/frd config - 打开设置界面")
            DEFAULT_CHAT_FRAME:AddMessage("/frd reset - 重置监控和修理提醒位置")
            DEFAULT_CHAT_FRAME:AddMessage("/frd status - 显示副手状态与背包盾牌数量")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor (mon) - 切换战斗耐久监控")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor on|off - 显式开关监控")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor interval <0.1-2.0> - 设置监控刷新频率")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor ooc - 切换脱战显示监控")
        elseif msg == "reset" or msg == "resetpos" then
            FRD:ResetFramePositions()
        elseif msg == "status" then
            local isEquipped = FRD:IsOffhandForceReactiveDisk()
            if isEquipped then
                local durability = FRD:GetOffhandDurability()
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 副手已装备力反馈盾牌, 耐久度: " .. string.format("%.1f", durability) .. "%")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 副手未装备力反馈盾牌")
            end
            local disks = FRD:FindAllDisksInBags()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 背包中找到 " .. table.getn(disks) .. " 个力反馈盾牌")
        elseif lowerMsg == "monitor" or lowerMsg == "mon" then
            FRD_Settings.monitorEnabled = not FRD_Settings.monitorEnabled
            FRD:UpdateMonitorVisibility(true)
            if FRD_Settings.monitorEnabled then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 战斗耐久监控: 已启用")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 战斗耐久监控: 已关闭")
            end
        elseif string.find(lowerMsg, "^monitor%s+") or string.find(lowerMsg, "^mon%s+") then
            local _, _, cmd, action = string.find(lowerMsg, "^(monitor|mon)%s+(%S+)")
            if action == "on" then
                FRD_Settings.monitorEnabled = true
                FRD:UpdateMonitorVisibility(true)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 战斗耐久监控: 已启用")
            elseif action == "off" then
                FRD_Settings.monitorEnabled = false
                FRD:UpdateMonitorVisibility(true)
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 战斗耐久监控: 已关闭")
            elseif action == "interval" and cmd and cmd ~= "" then
                local _, _, _, num = string.find(lowerMsg, "^(monitor|mon)%s+interval%s+(%d+%.?%d*)")
                local sec = tonumber(num)
                if sec then
                    if sec < 0.1 then sec = 0.1 end
                    if sec > 2.0 then sec = 2.0 end
                    FRD_Settings.monitorInterval = sec
                    FRD:UpdateMonitorVisibility(true)
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 监控刷新频率: " .. string.format("%.1f", sec) .. " 秒")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor interval 0.5")
                end
            elseif action == "ooc" then
                FRD_Settings.monitorShowOOC = not FRD_Settings.monitorShowOOC
                FRD:UpdateMonitorVisibility(true)
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
