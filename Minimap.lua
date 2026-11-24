-- Fettle: minimap button (drag to move around the minimap).
local _, ns = ...

local button

local function Position()
  local angle = math.rad(ns.db.minimap.angle or 200)
  local r = ((Minimap:GetWidth() or 140) / 2) + 6
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function ns.UpdateMinimap()
  if not button then return end
  if ns.db.minimap.hide then button:Hide() else button:Show(); Position() end
end

function ns.InitMinimap()
  if button or not Minimap then return end
  button = CreateFrame("Button", "FettleMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(ns.ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.ToggleUI(2) else ns.ToggleUI() end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      Position()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Fettle")
    local me = ns.Me()
    local m, l = ns.Summary(me)
    GameTooltip:AddLine(m .. " missing, " .. l .. " low", 1, 1, 1)
    GameTooltip:AddLine("Left-click: checklist   Right-click: wish list", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  ns.UpdateMinimap()
end
