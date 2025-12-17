-- ForceReactiveDisk.lua
-- 力反馈盾牌管理插件 for WoW 1.12

local ADDON_NAME = "ForceReactiveDisk"
local FORCE_REACTIVE_DISK_ID = 18168 -- 力反馈盾牌物品ID

-- 默认设置（会被SavedVariables覆盖）
FRD_Settings = {
    durabilityThreshold = 30,
    minimap = {
        angle = 0,
        shown = true
    }
}

-- 创建主框架
local FRD = CreateFrame("Frame", "ForceReactiveDiskFrame", UIParent)
FRD:RegisterEvent("ADDON_LOADED")
FRD:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- 确保设置已加载
        if not FRD_Settings then
            FRD_Settings = {
                durabilityThreshold = 30,
                minimap = {
                    angle = 0,
                    shown = true
                }
            }
        end
        FRD:Initialize()
    end
end)

-- 初始化
function FRD:Initialize()
    -- 创建小地图按钮
    self:CreateMinimapButton()
    -- 创建设置界面
    self:CreateSettingsFrame()
    -- 注册斜杠命令
    self:RegisterSlashCommands()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件已加载!|r 使用 /frd 或 /forcedisk 来管理盾牌")
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

-- 主要检测和切换逻辑
function FRD:CheckAndSwapDisk()
    -- 检查副手是否装备力反馈盾牌
    if not self:IsOffhandForceReactiveDisk() then
        -- 副手没有装备力反馈盾牌,寻找背包中的盾牌
        local disks = self:FindAllDisksInBags()
        if table.getn(disks) > 0 then
            -- 按耐久度排序,选择耐久度最高的
            table.sort(disks, function(a, b) return a.durability > b.durability end)
            self:EquipDisk(disks[1].bag, disks[1].slot)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已装备力反馈盾牌 (耐久度: " .. string.format("%.1f", disks[1].durability) .. "%)")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FRD]|r 背包中没有找到力反馈盾牌!")
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
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FRD]|r 已切换盾牌 (" .. string.format("%.1f", currentDurability) .. "% -> " .. string.format("%.1f", bestDisk.durability) .. "%)")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有更好的盾牌")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[FRD]|r 当前盾牌耐久度 " .. string.format("%.1f", currentDurability) .. "%, 背包中没有备用盾牌")
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
    frame:SetWidth(300)
    frame:SetHeight(200)
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
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -60)
    label:SetText("切换耐久度阈值 (%):")
    
    -- 耐久度滑块
    local slider = CreateFrame("Slider", "FRDDurabilitySlider", frame, "OptionsSliderTemplate")
    slider:SetPoint("TOP", frame, "TOP", 0, -90)
    slider:SetMinMaxValues(10, 90)
    slider:SetValueStep(5)
    slider:SetValue(FRD_Settings.durabilityThreshold)
    slider:SetWidth(200)
    getglobal(slider:GetName() .. "Low"):SetText("10%")
    getglobal(slider:GetName() .. "High"):SetText("90%")
    getglobal(slider:GetName() .. "Text"):SetText(FRD_Settings.durabilityThreshold .. "%")
    
    slider:SetScript("OnValueChanged", function()
        FRD_Settings.durabilityThreshold = this:GetValue()
        getglobal(this:GetName() .. "Text"):SetText(FRD_Settings.durabilityThreshold .. "%")
    end)
    
    -- 关闭按钮
    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
    closeButton:SetWidth(100)
    closeButton:SetHeight(25)
    closeButton:SetText("关闭")
    closeButton:SetScript("OnClick", function() frame:Hide() end)
    
    self.settingsFrame = frame
end

-- 注册斜杠命令
function FRD:RegisterSlashCommands()
    SLASH_FRD1 = "/frd"
    SLASH_FRD2 = "/forcedisk"
    SlashCmdList["FRD"] = function(msg)
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
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00力反馈盾牌管理插件命令:|r")
            DEFAULT_CHAT_FRAME:AddMessage("/frd 或 /frd check - 检测并切换盾牌")
            DEFAULT_CHAT_FRAME:AddMessage("/frd config - 打开设置界面")
            DEFAULT_CHAT_FRAME:AddMessage("/frd status - 显示当前状态")
        end
    end
end