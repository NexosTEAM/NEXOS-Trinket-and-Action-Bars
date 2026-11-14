-- NEXOS Trinket and Action Bars: trinket equipment and item controls.
local addon = CreateFrame('Frame')
local slots = {13,14}
local buttons, menuButtons = {}, {}
local menu, root
local db
local pending = {} -- Per-slot user selections waiting for combat to end.
local function Say(msg) print('|cff33bbffNEXOS Trinket and Action Bars:|r '..msg) end
local function Icon(item)
  if not item then return 'Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket' end
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(item) or 'Interface\\Icons\\INV_Misc_QuestionMark' end
  return (type(GetItemIcon)=='function' and GetItemIcon(item)) or 'Interface\\Icons\\INV_Misc_QuestionMark'
end
local function ItemInfo(link)
  if not link then return false end
  local id = tonumber(link:match('item:(%d+)'))
  if not id then return false end
  local equipLoc
  if C_Item and C_Item.GetItemInfoInstant then
    local _,_,_,loc = C_Item.GetItemInfoInstant(id)
    equipLoc=loc
  elseif GetItemInfoInstant then
    local _,_,_,loc = GetItemInfoInstant(id)
    equipLoc=loc
  end
  if not equipLoc and GetItemInfo then local _,_,_,_,_,_,_,_,loc=GetItemInfo(link); equipLoc=loc end
  return equipLoc=='INVTYPE_TRINKET'
end
local function BagLink(bag, index)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag,index) end
  return GetContainerItemLink and GetContainerItemLink(bag,index)
end
local function BagSize(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
-- Poll only the two equipped trinket cooldowns. Using a trinket from the
-- character panel does not necessarily fire an equipment or bag event.
-- Keep this independent of the inventory/menu refresh path.
local cooldownState = {}
local function RefreshCooldowns()
  for i, slot in ipairs(slots) do
    local button = buttons[i]
    if button and button.cooldown then
      local start, duration, enabled = GetInventoryItemCooldown('player', slot)
      start, duration = tonumber(start) or 0, tonumber(duration) or 0
      local active = duration > 1.5 and enabled ~= 0
      local old = cooldownState[slot]
      if not old or old.start ~= start or old.duration ~= duration or old.active ~= active then
        cooldownState[slot] = {start=start, duration=duration, active=active}
        if active then
          button.cooldown:SetCooldown(start, duration)
        elseif button.cooldown.Clear then
          button.cooldown:Clear()
        else
          button.cooldown:SetCooldown(0, 0)
        end
      end
    end
  end
end
local cooldownElapsed = 0
local cooldownWatcher = CreateFrame('Frame')
cooldownWatcher:SetScript('OnUpdate', function(_, elapsed)
  if not root or not root:IsShown() then return end
  cooldownElapsed = cooldownElapsed + elapsed
  if cooldownElapsed >= 0.25 then
    cooldownElapsed = 0
    RefreshCooldowns()
  end
end)
local function Refresh()
  for i,slot in ipairs(slots) do
    local item=GetInventoryItemID('player',slot)
    buttons[i].icon:SetTexture(item and Icon(item) or 'Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket')
    local queued=pending[slot]
    buttons[i].pendingIcon:SetTexture(queued and Icon(queued.itemID or queued.link) or nil)
    buttons[i].pendingIcon:SetShown(queued ~= nil)
    buttons[i].pendingBorder:SetShown(queued ~= nil)
    buttons[i].label:SetText('')
  end
  RefreshCooldowns()
end
local function HideMenu() if menu then menu:Hide() end end
local function Swap(entry,slot)
  HideMenu()
  if not entry or not entry.link then return end
  if InCombatLockdown() then
    pending[slot] = {link=entry.link, itemID=tonumber(entry.link:match('item:(%d+)'))}
    Say('Trinket queued for '..(slot==13 and 'TOP' or 'BOTTOM')..' slot; equipping automatically after combat.')
    Refresh()
    return
  end
  if CursorHasItem and CursorHasItem() then Say('Clear the cursor before swapping.'); return end
  local link=entry.link
  if type(EquipItemByName)=='function' then
    EquipItemByName(link,slot)
  elseif C_Item and type(C_Item.EquipItemByName)=='function' then
    C_Item.EquipItemByName(link,slot)
  elseif type(PickupInventoryItem)=='function' then
    if entry.sourceSlot then
      if entry.sourceSlot==slot then return end
      PickupInventoryItem(entry.sourceSlot)
    elseif entry.bag and entry.index then
      if C_Container and type(C_Container.PickupContainerItem)=='function' then
        C_Container.PickupContainerItem(entry.bag,entry.index)
      elseif type(PickupContainerItem)=='function' then
        PickupContainerItem(entry.bag,entry.index)
      else Say('Bag pickup API is unavailable.'); return end
    else Say('Trinket location is unavailable.'); return end
    if CursorHasItem and not CursorHasItem() then Say('Could not pick up trinket.'); return end
    PickupInventoryItem(slot)
    if CursorHasItem and CursorHasItem() then
      if entry.bag and entry.index then
        if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(entry.bag,entry.index)
        elseif PickupContainerItem then PickupContainerItem(entry.bag,entry.index) end
      elseif entry.sourceSlot then PickupInventoryItem(entry.sourceSlot) end
      if CursorHasItem() and ClearCursor then ClearCursor() end
    end
  else Say('No supported equipment API found.'); return end
  if C_Timer and C_Timer.After then C_Timer.After(.2,Refresh) else Refresh() end
end
local function ApplyPending()
  if InCombatLockdown() then return end
  for _,slot in ipairs(slots) do
    local choice=pending[slot]
    if choice then
      pending[slot]=nil
      if choice.itemID and GetInventoryItemID('player',slot)==choice.itemID then
        -- Already equipped.
      else
        -- Re-resolve the item in case bags moved during combat.
        local found
        for _,other in ipairs(slots) do
          local link=GetInventoryItemLink('player',other)
          if link and tonumber(link:match('item:(%d+)'))==choice.itemID then found={link=link,sourceSlot=other}; break end
        end
        if not found then
          for bag=0,(NUM_BAG_SLOTS or 4) do
            for index=1,(BagSize(bag) or 0) do
              local link=BagLink(bag,index)
              if link and tonumber(link:match('item:(%d+)'))==choice.itemID then found={link=link,bag=bag,index=index}; break end
            end
            if found then break end
          end
        end
        if found then Swap(found,slot) else Say('Queued trinket no longer found in bags/equipment for '..(slot==13 and 'TOP' or 'BOTTOM')..' slot.') end
      end
    end
  end
  Refresh()
end
local function BuildMenu(slot)
  -- The menu is ordinary UI: allow selecting trinkets in combat; equip later.
  if menu:IsShown() and menu.slot==slot then HideMenu(); return end
  menu.slot=slot
  local options,seen={},{}
  local function Add(link,where,sourceSlot,bag,index)
    if link and ItemInfo(link) and not seen[link] then
      seen[link]=true
      options[#options+1]={link=link,where=where,sourceSlot=sourceSlot,bag=bag,index=index}
    end
  end
  for _,s in ipairs(slots) do Add(GetInventoryItemLink('player',s),s==slot and 'Equipped' or 'Other slot',s) end
  local bags=NUM_BAG_SLOTS or 4
  for bag=0,bags do for index=1,(BagSize(bag) or 0) do Add(BagLink(bag,index),'Bag '..bag,nil,bag,index) end end
  table.sort(options,function(a,b) return (a.link or '')<(b.link or '') end)
  local maxRows=math.min(#options,14)
  menu:SetHeight(math.max(38,32+maxRows*29))
  for i=1,#menuButtons do menuButtons[i]:Hide() end
  for i=1,maxRows do
    local entry=options[i]
    local b=menuButtons[i]
    if not b then
      b=CreateFrame('Button',nil,menu,'BackdropTemplate')
      b:SetSize(252,27)
      b.icon=b:CreateTexture(nil,'ARTWORK'); b.icon:SetSize(23,23); b.icon:SetPoint('LEFT',3,0)
      b.text=b:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); b.text:SetPoint('LEFT',b.icon,'RIGHT',7,0); b.text:SetWidth(210); b.text:SetJustifyH('LEFT')
      b:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD')
      b:SetScript('OnClick',function(self) Swap(self.entry,menu.slot) end)
      b:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end)
      b:SetScript('OnLeave',function() GameTooltip:Hide() end)
      menuButtons[i]=b
    end
    b:ClearAllPoints(); b:SetPoint('TOPLEFT',menu,'TOPLEFT',6,-26-(i-1)*29)
    b.entry=entry; b.link=entry.link; b.icon:SetTexture(Icon(tonumber(entry.link:match('item:(%d+)'))))
    local name=(type(GetItemInfo)=='function' and GetItemInfo(entry.link)) or entry.link:match('%[(.-)%]') or 'Trinket'
    b.text:SetText((entry.where=='Equipped' and '|cff55ff77' or '|cffffffff')..name..'|r')
    b:Show()
  end
  menu.title:SetText('TRINKETS  >  '..(slot==13 and 'TOP' or 'BOTTOM')..' SLOT  ('..#options..')')
  menu:ClearAllPoints(); menu:SetPoint('TOPLEFT',buttons[slot==13 and 1 or 2],'BOTTOMLEFT',0,-4)
  menu:Show()
  if #options>maxRows then Say('Showing first '..maxRows..' trinkets; clear bag space to see other choices.') end
end
local function Initialize()
  NEXOSTrinketActionBarsDB=NEXOSTrinketActionBarsDB or {}
  db=NEXOSTrinketActionBarsDB
  db.point=db.point or {'CENTER',nil,'CENTER',0,0}
  root=CreateFrame('Frame','NEXOSTrinketActionBarsFrame',UIParent)
  root:SetSize(92,54); root:SetMovable(true); root:EnableMouse(true); root:RegisterForDrag('LeftButton')
  root:SetClampedToScreen(true)
  -- Compact icon-only frame: no large dark backdrop or decorative border.
  root:SetPoint(db.point[1],UIParent,db.point[3],db.point[4],db.point[5])
  root:SetScript('OnDragStart',function(self) if not db.locked and not InCombatLockdown() then self:StartMoving() end end)
  root:SetScript('OnDragStop',function(self)
    self:StopMovingOrSizing()
    local p,_,rp,x,y=self:GetPoint(1)
    db.point={p,nil,rp,x,y}
  end)
  local heading=root:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); heading:SetPoint('TOP',root,'TOP',0,-2); heading:SetWidth(92); heading:SetJustifyH('CENTER'); heading:SetText('|cff33bbffNEXOS|r')
  -- The title is the dedicated drag handle in both orientations.
  local dragHandle=CreateFrame('Frame',nil,root)
  dragHandle:SetHeight(16); dragHandle:SetPoint('TOP',root,'TOP',0,0)
  dragHandle:EnableMouse(true); dragHandle:RegisterForDrag('LeftButton')
  dragHandle:SetScript('OnDragStart',function() if not db.locked and not InCombatLockdown() then root:StartMoving() end end)
  dragHandle:SetScript('OnDragStop',function()
    root:StopMovingOrSizing()
    local p,_,rp,x,y=root:GetPoint(1)
    db.point={p,nil,rp,x,y}
  end)
  for i,slot in ipairs(slots) do
    local b=CreateFrame('Button',nil,root,'BackdropTemplate'); b:SetSize(36,36)
    b:SetPoint('TOPLEFT',8+(i-1)*40,-16)
    b.icon=b:CreateTexture(nil,'ARTWORK'); b.icon:SetAllPoints(b)
    b.empty=b:CreateTexture(nil,'BACKGROUND'); b.empty:SetAllPoints(b); b.empty:SetTexture('Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket')
    b.cooldown=CreateFrame('Cooldown',nil,b,'CooldownFrameTemplate'); b.cooldown:SetAllPoints(b)
    b.label=b:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); b.label:SetPoint('BOTTOMRIGHT',-1,1)
    -- Keep the equipped item visible; show the queued destination as a small inset icon.
    b.pendingBorder=b:CreateTexture(nil,'OVERLAY',nil,1)
    b.pendingBorder:SetSize(22,22); b.pendingBorder:SetPoint('BOTTOMRIGHT',b,'BOTTOMRIGHT',3,-3)
    b.pendingBorder:SetColorTexture(0,0,0,0.95); b.pendingBorder:Hide()
    b.pendingIcon=b:CreateTexture(nil,'OVERLAY',nil,2)
    b.pendingIcon:SetSize(18,18); b.pendingIcon:SetPoint('CENTER',b.pendingBorder,'CENTER',0,0)
    b.pendingIcon:SetTexCoord(.08,.92,.08,.92); b.pendingIcon:Hide()
    b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
    b:SetScript('OnClick',function() BuildMenu(slot) end)
    b:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetInventoryItem('player',slot); if pending[slot] then
      GameTooltip:AddLine('Queued after combat:',.3,.8,1)
      GameTooltip:AddLine(pending[slot].link or 'Trinket',1,1,1)
    end
    GameTooltip:AddLine('Click to swap trinket',.3,.8,1); GameTooltip:Show() end)
    b:SetScript('OnLeave',function() GameTooltip:Hide() end)
    buttons[i]=b
  end
  _G.NEXOSTrinketApplyOrientation=function()
    if InCombatLockdown() then return end
    local vertical=db.trinketOrientation=='vertical'
    root:SetSize(vertical and 76 or 92,vertical and 94 or 54)
    heading:ClearAllPoints()
    dragHandle:ClearAllPoints()
    if vertical then
      -- Stacked letters beside both trinkets, rather than a clipped horizontal title.
      heading:SetText('|cff33bbffG\nO\nD\nM\nO\nD\nE|r')
      heading:SetWidth(14)
      heading:SetHeight(78)
      -- Lower the stacked title so G aligns with the top trinket rather than above it.
      heading:SetPoint('TOPLEFT',root,'TOPLEFT',5,-18)
      heading:SetJustifyH('CENTER')
      dragHandle:SetWidth(18)
      dragHandle:SetHeight(94)
      dragHandle:SetPoint('LEFT',root,'LEFT',3,0)
    else
      heading:SetText('|cff33bbffNEXOS|r')
      heading:SetWidth(92)
      heading:SetHeight(14)
      heading:SetPoint('TOP',root,'TOP',0,-2)
      dragHandle:SetWidth(92)
      dragHandle:SetHeight(16)
      dragHandle:SetPoint('TOP',root,'TOP',0,0)
    end
    for i,b in ipairs(buttons) do
      b:ClearAllPoints()
      b:SetPoint('TOPLEFT',vertical and 20 or (8+(i-1)*40),vertical and (-16-(i-1)*39) or -16)
    end
  end
  _G.NEXOSTrinketApplyOrientation()
  menu=CreateFrame('Frame',nil,root,'BackdropTemplate'); menu:SetSize(264,38)
  menu:SetFrameStrata('DIALOG')
  menu:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=13,insets={left=3,right=3,top=3,bottom=3}})
  menu.title=menu:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); menu.title:SetPoint('TOPLEFT',8,-9)
  menu:Hide()
  SLASH_NEXOSTRINKET1='/nextrinket'
  SlashCmdList.NEXOSTRINKET=function(msg)
    msg=(msg or ''):lower()
    if msg=='lock' then db.locked=true; Say('Position locked.')
    elseif msg=='unlock' then db.locked=false; Say('Position unlocked.')
    elseif msg=='reset' then root:ClearAllPoints(); root:SetPoint('CENTER'); db.point={'CENTER',nil,'CENTER',0,0}; root:Show()
    elseif msg=='hide' then root:Hide()
    else root:SetShown(not root:IsShown()) end
  end
  Refresh()
end
addon:RegisterEvent('PLAYER_REGEN_ENABLED')
addon:RegisterEvent('PLAYER_LOGIN')
addon:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
addon:RegisterEvent('BAG_UPDATE_DELAYED')
addon:RegisterEvent('PLAYER_ENTERING_WORLD')
addon:SetScript('OnEvent',function(self,event)
  if event=='PLAYER_LOGIN' then Initialize() elseif root and event=='PLAYER_REGEN_ENABLED' then ApplyPending() elseif root then Refresh() end
end)
