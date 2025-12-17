-- ForceReactiveDisk.lua
-- 力反馈盾牌管理插件 for WoW 1.12

local ADDON_NAME = "ForceReactiveDisk"
local FORCE_REACTIVE_DISK_ID = 18168 -- 力反馈盾牌物品ID

-- 默认设置（会被SavedVariables覆盖）
FRD_Settings = {
    durabilityThreshold = 30,
    autoMode = false, -- 主动检测模式
    checkInterval = 2.0, -- 检测频率（秒）
    monitorEnabled = false, -- 战斗中显示耐久监控
    monitorInterval = 0.5, -- 监控刷新频率（秒）
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

FRD:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- 确保设置已加载并设置默认值
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
        if FRD_Settings.monitorEnabled == nil then
            FRD_Settings.monitorEnabled = false
        end
        if not FRD_Settings.monitorInterval then
            FRD_Settings.monitorInterval = 0.5
        end
        if not FRD_Settings.minimap then
            FRD_Settings.minimap = { angle = 0, shown = true }
        end
        FRD:Initialize()
    elseif event == "PLAYER_ENTERING_WORLD" then
        FRD:UpdateMonitorVisibility(true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        FRD.inCombat = true
        if FRD_Settings.autoMode then
            FRD:StartAutoCheck()
        end
        FRD:UpdateMonitorVisibility(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FRD.inCombat = false
        FRD:StopAutoCheck()
        FRD:UpdateMonitorVisibility(true)
    elseif event == "BAG_UPDATE" or event == "UPDATE_INVENTORY_ALERTS" then
        FRD:UpdateMonitorText(false)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            FRD:UpdateMonitorText(false)
        end
    end
end)

-- 初始化
function FRD:Initialize()
    -- 创建小地图按钮
    self:CreateMinimapButton()
    -- 创建设置界面
    self:CreateSettingsFrame()
    -- 创建耐久监控UI
    self:CreateMonitorFrame()
    -- 注册斜杠命令
    self:RegisterSlashCommands()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件已加载!|r 使用 /frd 或 /forcedisk 来管理盾牌")
    self:UpdateMonitorVisibility(true)
end

-- 创建耐久监控小窗（战斗中显示）
function FRD:CreateMonitorFrame()
    if self.monitorFrame then
        return
    end

    local frame = CreateFrame("Frame", "FRDMonitorFrame", UIParent)
    frame:SetWidth(260)
    frame:SetHeight(70)
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

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText("")
    frame.text = text

    frame:EnableMouse(true)
    frame:SetMovable(true)
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

    local shouldShow = FRD_Settings.monitorEnabled and self.inCombat
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
    if offhandIsDisk then
        offhandDurability = self:GetOffhandDurability()
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

    local offhandLine
    if offhandIsDisk then
        local c = self:FormatDurabilityColor(offhandDurability)
        offhandLine = c .. "身上(副手): 力反馈盾牌 " .. string.format("%.1f", offhandDurability) .. "%|r"
    else
        offhandLine = "|cffff9900身上(副手): 未装备力反馈盾牌|r"
    end

    local bagLine
    if bagCount == 0 then
        bagLine = "|cffff0000背包: 0 个力反馈盾牌|r"
    else
        local bestColor = self:FormatDurabilityColor(best)
        local worstColor = self:FormatDurabilityColor(worst)
        bagLine = "|cff00ff00背包: " .. bagCount .. " 个|r  " .. bestColor .. "最高 " .. string.format("%.1f", best) .. "%|r  " .. worstColor .. "最低 " .. string.format("%.1f", worst) .. "%|r"
    end

    local thresholdLine = "|cffaaaaaa切换阈值: " .. (FRD_Settings.durabilityThreshold or 30) .. "%  刷新: " .. string.format("%.1f", (FRD_Settings.monitorInterval or 0.5)) .. "秒|r"

    local newText = offhandLine .. "\n" .. bagLine .. "\n" .. thresholdLine
    if force or self.monitorFrame.lastText ~= newText then
        self.monitorFrame.text:SetText(newText)
        self.monitorFrame.lastText = newText
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
    -- 检查副手是否装备力反馈盾牌
    if not self:IsOffhandForceReactiveDisk() then
        -- 副手没有装备力反馈盾牌,寻找背包中的盾牌
        local disks = self:FindAllDisksInBags()
        if table.getn(disks) > 0 then
            -- 按耐久度排序,选择耐久度最高的
            table.sort(disks, function(a, b) return a.durability > b.durability end)
            self:EquipDisk(disks[1].bag, disks[1].slot)
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已装备力反馈盾牌 (耐久度: " .. string.format("%.1f", disks[1].durability) .. "%)")
            end
        else
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 背包中没有找到力反馈盾牌!")
            end
        end
        return
    end
    
    -- 副手已装备力反馈盾牌,检查耐久度
    local currentDurability = self:GetOffhandDurability()
    if currentDurability < FRD_Settings.durabilityThreshold then
        -- 耐久度低于阈值,寻找更好的盾牌
        local disks = self:FindAllDisksInBags()
        if table.getn(disks) > 0 then
            -- 按耐久度排序
            table.sort(disks, function(a, b) return a.durability > b.durability end)
            local bestDisk = disks[1]
            
            -- 只在找到更好的盾牌时才切换
            if bestDisk.durability > currentDurability then
                self:EquipDisk(bestDisk.bag, bestDisk.slot)
                if not silent then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已切换盾牌 (" .. string.format("%.1f", currentDurability) .. "% -> " .. string.format("%.1f", bestDisk.durability) .. "%)")
                end
            else
                if not silent then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有更好的盾牌")
                end
            end
        else
            if not silent then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有备用盾牌")
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
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52, -52)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    local icon = button:CreateTexture("FRDMinimapIcon", "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Shield_21") -- 盾牌图标
    
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(52)
    overlay:SetHeight(52)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)
    
    button:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            FRD:CheckAndSwapDisk()
        elseif arg1 == "RightButton" then
            FRDSettingsFrame:Show()
        end
    end)
    
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("力反馈盾牌管理")
        GameTooltip:AddLine("左键: 检测并切换盾牌", 1, 1, 1)
        GameTooltip:AddLine("右键: 打开设置", 1, 1, 1)
        if FRD_Settings.autoMode then
            GameTooltip:AddLine("|cff00ff00主动模式: 已启用|r", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("|cff888888主动模式: 未启用|r", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- 支持拖拽
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        this:SetScript("OnUpdate", FRD.MinimapButton_OnUpdate)
    end)
    button:SetScript("OnDragStop", function()
        this:SetScript("OnUpdate", nil)
    end)
    
    self.minimapButton = button
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

-- 创建设置界面
function FRD:CreateSettingsFrame()
    local frame = CreateFrame("Frame", "FRDSettingsFrame", UIParent)
    frame:SetWidth(350)
    frame:SetHeight(370)
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
    autoLabel:SetText("启用主动检测模式（战斗中自动检测）")
    
    autoCheckbox:SetScript("OnClick", function()
        -- 复选框点击时不立即保存，等待确认按钮
    end)
    
    -- 检测频率标签
    local label2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -180)
    label2:SetText("检测频率 (秒):")
    
    -- 检测频率滑块
    local slider2 = CreateFrame("Slider", "FRDIntervalSlider", frame, "OptionsSliderTemplate")
    slider2:SetPoint("TOP", frame, "TOP", 0, -210)
    slider2:SetMinMaxValues(0.2, 10)
    slider2:SetValueStep(0.2)
    slider2:SetWidth(250)
    getglobal(slider2:GetName() .. "Low"):SetText("0.2秒")
    getglobal(slider2:GetName() .. "High"):SetText("10秒")
    
    -- 确保值在有效范围内
    local intervalValue = FRD_Settings.checkInterval or 2.0
    if intervalValue < 0.2 then intervalValue = 0.2 end
    if intervalValue > 10 then intervalValue = 10 end
    
    slider2:SetValue(intervalValue)
    getglobal(slider2:GetName() .. "Text"):SetText(string.format("%.1f秒", intervalValue))
    
    slider2:SetScript("OnValueChanged", function()
        local newValue = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(string.format("%.1f秒", newValue))
    end)

    -- 耐久监控复选框
    local monitorCheckbox = CreateFrame("CheckButton", "FRDMonitorCheckbox", frame, "UICheckButtonTemplate")
    monitorCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -250)
    monitorCheckbox:SetWidth(24)
    monitorCheckbox:SetHeight(24)
    monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)

    local monitorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    monitorLabel:SetPoint("LEFT", monitorCheckbox, "RIGHT", 5, 0)
    monitorLabel:SetText("启用战斗耐久监控（显示小窗）")

    -- 监控刷新频率标签
    local label3 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label3:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -285)
    label3:SetText("监控刷新频率 (秒):")

    -- 监控刷新频率滑块
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
    
    -- 保存设置的临时变量
    frame.tempSettings = {
        durabilityThreshold = FRD_Settings.durabilityThreshold,
        autoMode = FRD_Settings.autoMode,
        checkInterval = intervalValue,
        monitorEnabled = FRD_Settings.monitorEnabled,
        monitorInterval = monitorIntervalValue
    }
    
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
        FRD_Settings.checkInterval = slider2:GetValue()
        FRD_Settings.monitorEnabled = monitorCheckbox:GetChecked() == 1
        FRD_Settings.monitorInterval = slider3:GetValue()
        
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
        slider2:SetValue(FRD_Settings.checkInterval)
        monitorCheckbox:SetChecked(FRD_Settings.monitorEnabled)
        slider3:SetValue(FRD_Settings.monitorInterval or 0.5)
        frame:Hide()
    end)
    
    self.settingsFrame = frame
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
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor  (切换开关)")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor on/off")
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 用法: /frd monitor interval 0.5")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件命令:|r")
            DEFAULT_CHAT_FRAME:AddMessage("/frd 或 /frd check - 检测并切换盾牌")
            DEFAULT_CHAT_FRAME:AddMessage("/frd config - 打开设置界面")
            DEFAULT_CHAT_FRAME:AddMessage("/frd status - 显示当前状态")
            DEFAULT_CHAT_FRAME:AddMessage("/frd monitor - 切换战斗耐久监控")
        end
    end
end
