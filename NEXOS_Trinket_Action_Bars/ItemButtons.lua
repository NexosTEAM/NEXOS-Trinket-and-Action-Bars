-- Independent movable secure item buttons. No changes to trinket engine.
local owner=CreateFrame('Frame')
local db, widgets={},{}
local draggedSlot=nil
local function updateSelectionGlow()
 for index,widget in pairs(widgets) do
  if widget.selectionGlow then
   widget.selectionGlow:SetShown(draggedSlot==index)
   if widget.selectionEdges then for _,edge in ipairs(widget.selectionEdges) do edge:SetShown(draggedSlot==index) end end
  end
 end
end
local function say(s) print('|cff33bbffNEXOS Items:|r '..s) end
local function itemIcon(id)
 if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
 if GetItemIcon then return GetItemIcon(id) end
end
local function bagSize(b)
 if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(b) end
 return GetContainerNumSlots and GetContainerNumSlots(b) or 0
end
local function bagLink(b,s)
 if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(b,s) end
 return GetContainerItemLink and GetContainerItemLink(b,s)
end
local function cooldown(id)
 if not id then return 0,0 end
 if C_Item and C_Item.GetItemCooldown then return C_Item.GetItemCooldown(id) end
 if GetItemCooldown then return GetItemCooldown(id) end
 return 0,0
end
local function count(id)
 if not id then return '' end
 if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
 if GetItemCount then return GetItemCount(id) end
 return ''
end
local function configure(w)
 if InCombatLockdown() then return end
 local id=db.items[w.index]
 -- Use the canonical SecureActionButton attributes for the default action.
 -- The old type1/item1-only setup could leave the default action unresolved.
 w.action:SetAttribute('type',id and 'item' or nil)
 w.action:SetAttribute('item',id and ('item:'..id) or nil)
 w.action:SetAttribute('type1',nil)
 w.action:SetAttribute('item1',nil)
 -- Shift-left-click is a non-use action: pickup is handled by PostClick.
 -- A dedicated secure modifier action prevents the default item action firing.
 w.action:SetAttribute('shift-type1','macro')
 w.action:SetAttribute('shift-macrotext1','')
 -- Right-click is reserved for the picker; suppress the inherited item action.
 w.action:SetAttribute('type2','macro')
 w.action:SetAttribute('macrotext2','')
 w.action:SetAttribute('item2',nil)
 w.icon:SetTexture(id and itemIcon(id) or 'Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag')
 w.icon:SetDesaturated(not id)
 w.icon:SetAlpha(1)
 w.lastStart,w.lastDuration=nil,nil
end
local function refresh(w)
 local id=db.items[w.index]
 if not id then
  w.quantity:SetText('')
  w.icon:SetAlpha(1)
  w.icon:SetDesaturated(true)
  w.cd:Clear()
  w.lastStart,w.lastDuration=nil,nil
  return
 end
 -- Keep the assigned item visible as a dim ghost when its inventory count reaches zero.
 -- Counts are read live, not cached when the item was assigned.
 local n=tonumber(count(id)) or 0
 w.icon:SetTexture(itemIcon(id) or 'Interface\\Icons\\INV_Misc_QuestionMark')
 w.icon:SetAlpha(n>0 and 1 or 0.28)
 w.icon:SetDesaturated(n==0)
 -- Always show the actual quantity, including 1 and 0.
 w.quantity:SetText(tostring(n))
 if n==0 then
  w.cd:Clear()
  w.lastStart,w.lastDuration=nil,nil
  return
 end
 local s,d=cooldown(id); s=tonumber(s) or 0; d=tonumber(d) or 0
 if w.lastStart~=s or w.lastDuration~=d then
  w.lastStart,w.lastDuration=s,d
  if d>1.5 then w.cd:SetCooldown(s,d) else w.cd:Clear() end
 end
end
-- Exactly one selection window may be open across all item-bar slots.
-- Reusing a single active reference prevents overlapping pickers when switching slots.
local activePicker, activePickerOwner
local function choose(w)
 if activePicker then
  local sameSlot = (activePickerOwner == w)
  activePicker:Hide()
  activePicker = nil
  activePickerOwner = nil
  if sameSlot then return end
 end
 local picker=CreateFrame('Frame',nil,UIParent,'BackdropTemplate')
 picker:SetFrameStrata('DIALOG'); picker:SetSize(230,290)
 picker:SetPoint('TOPLEFT',UIParent,'CENTER',-115,130)
 picker:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
 picker:EnableMouse(true)
 local title=picker:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); title:SetPoint('TOPLEFT',8,-10); title:SetText('NEXOS ITEMS - SELECT')
 local close=CreateFrame('Button',nil,picker,'UIPanelCloseButton'); close:SetPoint('TOPRIGHT',1,1); close:SetSize(23,23)
 local scroll=CreateFrame('ScrollFrame',nil,picker,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',8,-28); scroll:SetPoint('BOTTOMRIGHT',-27,8)
 local content=CreateFrame('Frame',nil,scroll); content:SetSize(185,1); scroll:SetScrollChild(content)
 local entries,seen={},{}
 for b=0,(NUM_BAG_SLOTS or 4) do for s=1,bagSize(b) do
  local link=bagLink(b,s); local id=link and tonumber(link:match('item:(%d+)'))
  if id and not seen[id] then seen[id]=true; entries[#entries+1]={id=id,link=link} end
 end end
 table.sort(entries,function(a,b) return a.link<b.link end)
 table.insert(entries,1,{id=false,link='|cffff8888Clear this button|r'})
 content:SetHeight(#entries*27)
 for i,e in ipairs(entries) do
  local b=CreateFrame('Button',nil,content); b:SetSize(185,26); b:SetPoint('TOPLEFT',0,-(i-1)*27)
  local tex=b:CreateTexture(nil,'ARTWORK'); tex:SetSize(22,22); tex:SetPoint('LEFT',2,0); tex:SetTexture(e.id and itemIcon(e.id) or 'Interface\\Buttons\\UI-GroupLoot-Pass-Up')
  local label=b:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); label:SetPoint('LEFT',tex,'RIGHT',4,0); label:SetWidth(119); label:SetJustifyH('LEFT'); label:SetText(e.link)
  -- Show the total number owned across bags, not just one bag stack.
  -- The quantity is informational; it does not change the secure item action.
  if e.id then
   local amount=b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
   amount:SetPoint('RIGHT',b,'RIGHT',-4,0)
   amount:SetWidth(31)
   amount:SetJustifyH('RIGHT')
   amount:SetText(tostring(tonumber(count(e.id)) or 0))
   amount:SetTextColor(1,0.85,0.25)
  end
  b:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD')
  -- Show the real Blizzard item tooltip for each bag entry in the picker.
  -- Use the full item hyperlink to preserve enchant/bonus/quality information.
  b:SetScript('OnEnter',function(self)
   if not e.id then return end
   GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
   GameTooltip:SetHyperlink(e.link)
   GameTooltip:Show()
  end)
  b:SetScript('OnLeave',function(self)
   if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  b:SetScript('OnClick',function()
   if InCombatLockdown() then say('Item assignments can only change outside combat.'); return end
   db.items[w.index]=e.id or nil; configure(w); refresh(w); picker:Hide(); w.picker=nil
  end)
 end
 picker:SetScript('OnHide',function()
  if w.picker==picker then w.picker=nil end
  if activePicker==picker then activePicker=nil; activePickerOwner=nil end
 end)
 w.picker=picker
 activePicker=picker
 activePickerOwner=w
end
-- One movable 8 x 2 action panel. Individual buttons remain secure item actions.
local panel, minimap, popup
local TOTAL, SIZE, GAP = 16, 36, 3
local function columns() return db.orientation=='vertical' and 2 or 8 end
local function makeButton(i)
 local w=CreateFrame('Frame','NEXOSItemHolder'..i,panel)
 w.index=i; w:SetSize(SIZE,SIZE)
 local cols=columns()
 w:SetPoint('TOPLEFT',panel,'TOPLEFT',((i-1)%cols)*(SIZE+GAP),-18-math.floor((i-1)/cols)*(SIZE+GAP))
 local action=CreateFrame('Button','NEXOSItemAction'..i,w,'SecureActionButtonTemplate')
 action:SetAllPoints(); action:EnableMouse(true); action:RegisterForClicks('AnyDown','AnyUp'); w.action=action
 w.icon=action:CreateTexture(nil,'BACKGROUND'); w.icon:SetAllPoints(); w.icon:SetTexCoord(.08,.92,.08,.92)
 w.cd=CreateFrame('Cooldown',nil,action,'CooldownFrameTemplate'); w.cd:SetAllPoints(); w.cd:EnableMouse(false)
 -- Draw on the actual secure action frame, ABOVE its icon and cooldown.
 -- Textures do not capture mouse input; secure click behavior stays unchanged.
 -- Four clean, full-slot cyan edges. No Blizzard border artwork or glyphs.
 w.selectionGlow=action:CreateTexture(nil,'OVERLAY',nil,7)
 w.selectionGlow:SetColorTexture(0,0.9,1,0.95)
 w.selectionGlow:SetPoint('TOPLEFT',action,'TOPLEFT',0,0)
 w.selectionGlow:SetPoint('TOPRIGHT',action,'TOPRIGHT',0,0)
 w.selectionGlow:SetHeight(2)
 w.selectionGlow:Hide()
 w.selectionEdges={}
 local function edge(pointA,pointB,width,height)
  local t=action:CreateTexture(nil,'OVERLAY',nil,7)
  t:SetColorTexture(0,0.9,1,0.95)
  t:SetPoint(pointA,action,pointA,0,0)
  t:SetPoint(pointB,action,pointB,0,0)
  if width then t:SetWidth(width) else t:SetHeight(height) end
  t:Hide()
  w.selectionEdges[#w.selectionEdges+1]=t
 end
 edge('BOTTOMLEFT','BOTTOMRIGHT',nil,2)
 edge('TOPLEFT','BOTTOMLEFT',2,nil)
 edge('TOPRIGHT','BOTTOMRIGHT',2,nil)
 w.quantity=action:CreateFontString(nil,'OVERLAY','NumberFontNormalSmall'); w.quantity:SetPoint('BOTTOMRIGHT',-1,2)
 -- Secure item actions are performed by the WoW client. Assignments are made
 -- out of combat using an item dragged from bags or the character window.
 local function assignCursor()
  if InCombatLockdown() then return false end
  local kind,itemID=GetCursorInfo()
  if kind~='item' or not itemID then return false end
  local source=draggedSlot
  local old=db.items[i]
  local incoming=tonumber(itemID)
  if not incoming then return false end
  db.items[i]=incoming
  if source and source~=i and widgets[source] then
   db.items[source]=old
   configure(widgets[source]); refresh(widgets[source])
  end
  draggedSlot=nil
  updateSelectionGlow()
  ClearCursor()
  configure(w); refresh(w)
  return true
 end
 -- Keep item activation separate from assignment gestures.
 -- Never mutate secure attributes during a click. In particular, do not use
 -- PreClick to drop an item: the same click could activate the destination.
 action:SetScript('OnReceiveDrag',assignCursor)
 -- MouseUp is independent of secure PostClick dispatch on Forever.
 -- The shift modifier has a blank secure action set in configure(), so
 -- shift-click does not consume the assigned item.
 action:HookScript('OnMouseUp',function(_,button)
  if InCombatLockdown() then return end
  if button=='RightButton' then
   draggedSlot=nil
   updateSelectionGlow()
   choose(w)
  elseif button=='LeftButton' and IsShiftKeyDown() then
   local kind=GetCursorInfo()
   if kind=='item' then
    assignCursor()
   elseif draggedSlot and widgets[draggedSlot] then
    local source=draggedSlot
    draggedSlot=nil
    updateSelectionGlow()
    if source~=i then
     db.items[source],db.items[i]=db.items[i],db.items[source]
     configure(widgets[source]); refresh(widgets[source])
     configure(w); refresh(w)
    end
   elseif db.items[i] then
    draggedSlot=i
    updateSelectionGlow()
   end
  end
 end)
 -- If an item is dragged outside the bar, keep its original assignment.
 -- No slot is erased until the drop destination is known.

 action:SetScript('OnEnter',function()
  GameTooltip:SetOwner(action,'ANCHOR_RIGHT'); local id=db.items[i]
  if id then GameTooltip:SetHyperlink('item:'..id) else GameTooltip:AddLine('Empty NEXOS item slot') end
  GameTooltip:AddLine('Left-click: use  |  Shift-click: select / place  |  Right-click: choose',.3,.8,1); GameTooltip:Show()
 end)
 action:SetScript('OnLeave',function() GameTooltip:Hide() end)
 configure(w); refresh(w); widgets[i]=w
end
local function setupPanel()
 panel=CreateFrame('Frame','NEXOSItemBar',UIParent)
 local cols=columns(); panel:SetSize(cols*(SIZE+GAP)-GAP,18+math.ceil(TOTAL/cols)*(SIZE+GAP)-GAP)
 panel:SetMovable(true); panel:SetClampedToScreen(true); panel:EnableMouse(true)
 local pos=db.barPosition or {'CENTER','CENTER',0,-110}
 panel:SetPoint(pos[1],UIParent,pos[2],pos[3],pos[4])
 local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); title:SetPoint('TOP',0,-2); title:SetText('NEXOS')
 local drag=CreateFrame('Button',nil,panel); drag:SetPoint('TOPLEFT',panel,'TOPLEFT',0,0); drag:SetPoint('TOPRIGHT',panel,'TOPRIGHT',0,0); drag:SetHeight(17)
 drag:RegisterForDrag('LeftButton')
 -- NEXOSItemBar owns secure action buttons. StopMovingOrSizing is protected
 -- while combat lockdown is active, even if the drag began before combat.
 local moving=false
 local deferredStop=false
 local function finishMove()
  if not moving then return end
  if InCombatLockdown() then
   deferredStop=true
   return
  end
  panel:StopMovingOrSizing()
  moving=false
  deferredStop=false
  local p,_,rp,x,y=panel:GetPoint(1)
  db.barPosition={p,rp,x,y}
 end
 drag:RegisterEvent('PLAYER_REGEN_DISABLED')
 drag:RegisterEvent('PLAYER_REGEN_ENABLED')
 drag:SetScript('OnEvent',function(_,event)
  if event=='PLAYER_REGEN_DISABLED' then
   -- Never call a protected movement API once combat lockdown has started.
   if moving then deferredStop=true end
  elseif event=='PLAYER_REGEN_ENABLED' and (deferredStop or moving) then
   finishMove()
  end
 end)
 drag:SetScript('OnDragStart',function()
  if moving or InCombatLockdown() then return end
  moving=true
  panel:StartMoving()
 end)
 drag:SetScript('OnDragStop',finishMove)
 for i=1,TOTAL do makeButton(i) end
 panel:SetShown(db.barVisible~=false)
end
local function applyOrientation()
 if InCombatLockdown() then return end
 local cols=columns()
 panel:SetSize(cols*(SIZE+GAP)-GAP,18+math.ceil(TOTAL/cols)*(SIZE+GAP)-GAP)
 for i,w in ipairs(widgets) do
  w:ClearAllPoints()
  w:SetPoint('TOPLEFT',panel,'TOPLEFT',((i-1)%cols)*(SIZE+GAP),-18-math.floor((i-1)/cols)*(SIZE+GAP))
 end
end
local function setupMinimap()
 minimap=CreateFrame('Button','NEXOSItemMinimapButton',Minimap)
 minimap:SetSize(29,29); minimap:SetFrameStrata('MEDIUM'); minimap:SetMovable(true); minimap:RegisterForDrag('LeftButton')
 minimap:SetPoint('CENTER',Minimap,'CENTER',db.minimapX or -76,db.minimapY or -76)
 -- Fixed NEXOS trinket artwork: never substitute a bag or equipped item texture.
 -- A custom circular ring is drawn at the same center and diameter as the icon.
 local icon=minimap:CreateTexture(nil,'ARTWORK')
 icon:SetSize(24,24); icon:SetPoint('CENTER',minimap,'CENTER',0,0)
 icon:SetTexture('Interface\\AddOns\\NEXOS_Trinket_Action_Bars\\TrinketIcon')
 local border=minimap:CreateTexture(nil,'OVERLAY')
 border:SetSize(30,30); border:SetPoint('CENTER',minimap,'CENTER',0,0)
 border:SetTexture('Interface\\AddOns\\NEXOS_Trinket_Action_Bars\\MinimapRing')
 -- Keep the button on the minimap rim, never free-floating.
 local function snapToRim(self)
  local scale=UIParent:GetEffectiveScale()
  local cx,cy=GetCursorPosition(); cx,cy=cx/scale,cy/scale
  local mx,my=Minimap:GetCenter()
  local dx,dy=cx-mx,cy-my
  local distance=math.sqrt(dx*dx+dy*dy)
  if distance<1 then dx,dy,distance=1,0,1 end
  local radius=(Minimap:GetWidth() or 140)/2+5
  local x,y=radius*dx/distance,radius*dy/distance
  self:ClearAllPoints(); self:SetPoint('CENTER',Minimap,'CENTER',x,y)
  db.minimapX,db.minimapY=x,y
 end
 local function restoreRim(self)
  local x,y=db.minimapX or -76,db.minimapY or -76
  local distance=math.sqrt(x*x+y*y)
  if distance<1 then x,y,distance=-1,-1,math.sqrt(2) end
  local radius=(Minimap:GetWidth() or 140)/2+5
  x,y=radius*x/distance,radius*y/distance
  self:ClearAllPoints(); self:SetPoint('CENTER',Minimap,'CENTER',x,y)
  db.minimapX,db.minimapY=x,y
 end
 restoreRim(minimap)
 minimap:SetScript('OnDragStart',function(self)
  self:SetScript('OnUpdate',snapToRim)
 end)
 minimap:SetScript('OnDragStop',function(self)
  self:SetScript('OnUpdate',nil); snapToRim(self)
 end)
 minimap:SetScript('OnClick',function()
  if popup and popup:IsShown() then popup:Hide(); return end
  if not popup then
   popup=CreateFrame('Frame',nil,UIParent,'BackdropTemplate'); popup:SetSize(250,184); popup:SetFrameStrata('DIALOG')
   popup:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
   local title=popup:CreateFontString(nil,'OVERLAY','GameFontNormal'); title:SetPoint('TOP',0,-12); title:SetText('NEXOS SETTINGS')
   local function toggleAt(y,label,get,set)
    local check=CreateFrame('CheckButton',nil,popup,'UICheckButtonTemplate'); check:SetPoint('TOPLEFT',8,y)
    local text=popup:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); text:SetPoint('LEFT',check,'RIGHT',3,0); text:SetText(label)
    check:SetScript('OnClick',function(self)
     if InCombatLockdown() then self:SetChecked(get()); return end
     set(self:GetChecked() and true or false)
    end)
    return check
   end
   popup.toggle=toggleAt(-28,'Show item bar',function() return db.barVisible~=false end,function(v) db.barVisible=v; panel:SetShown(v) end)
   popup.trinketToggle=toggleAt(-59,'Show trinket menu',function() return db.trinketVisible~=false end,function(v)
    db.trinketVisible=v
    local trinkets=_G.NEXOSTrinketActionBarsFrame
    if trinkets then trinkets:SetShown(v) end
   end)
   popup.verticalToggle=toggleAt(-90,'Item bar vertical (2 x 8)',function() return db.orientation=='vertical' end,function(v)
    db.orientation=v and 'vertical' or 'horizontal'; applyOrientation()
   end)
   popup.trinketVerticalToggle=toggleAt(-121,'Trinkets vertical (1 x 2)',function() return db.trinketOrientation=='vertical' end,function(v)
    db.trinketOrientation=v and 'vertical' or 'horizontal'
    if _G.NEXOSTrinketApplyOrientation then _G.NEXOSTrinketApplyOrientation() end
   end)
  end
  popup.toggle:SetChecked(db.barVisible~=false)
  popup.trinketToggle:SetChecked(db.trinketVisible~=false)
  popup.verticalToggle:SetChecked(db.orientation=='vertical')
  popup.trinketVerticalToggle:SetChecked(db.trinketOrientation=='vertical')
  popup:ClearAllPoints(); popup:SetPoint('TOPRIGHT',minimap,'BOTTOMLEFT',0,-5); popup:Show()
 end)
 minimap:SetScript('OnEnter',function(self)
  GameTooltip:SetOwner(self,'ANCHOR_LEFT'); GameTooltip:AddLine('NEXOS Item Bar'); GameTooltip:AddLine('Click: visibility and orientation'); GameTooltip:AddLine('Drag: move minimap icon'); GameTooltip:Show()
 end)
 minimap:SetScript('OnLeave',function() GameTooltip:Hide() end)
 minimap:SetShown(db.showMinimap~=false)
end
SLASH_NEXOSITEMS1='/nexitems'
SlashCmdList.NEXOSITEMS=function(msg)
 msg=(msg or ''):lower():match('^%s*(.-)%s*$')
 if msg=='minimap' then db.showMinimap=not (db.showMinimap~=false); minimap:SetShown(db.showMinimap)
 elseif msg=='show' or msg=='hide' then
  if InCombatLockdown() then say('Change visibility outside combat.'); return end
  db.barVisible=(msg=='show'); panel:SetShown(db.barVisible)
 else say('Commands: /nexitems minimap, /nexitems show, /nexitems hide. Drag the NEXOS title to move the entire bar.') end
end
owner:RegisterEvent('PLAYER_LOGIN'); owner:RegisterEvent('PLAYER_REGEN_ENABLED')
owner:SetScript('OnEvent',function(_,event)
 if event=='PLAYER_LOGIN' then
  NEXOSTrinketActionBarsDB=NEXOSTrinketActionBarsDB or {}; db=NEXOSTrinketActionBarsDB
  db.items=db.items or {}; db.positions=db.positions or {}; db.visible=db.visible or {}
  setupPanel(); setupMinimap()
  if _G.NEXOSTrinketActionBarsFrame then _G.NEXOSTrinketActionBarsFrame:SetShown(db.trinketVisible~=false) end
 elseif event=='PLAYER_REGEN_ENABLED' then for _,w in ipairs(widgets) do configure(w) end end
end)
local elapsed=0
owner:SetScript('OnUpdate',function(_,dt)
 if not db then return end
 elapsed=elapsed+dt; if elapsed<.25 then return end; elapsed=0
 if panel and panel:IsShown() then for _,w in ipairs(widgets) do refresh(w) end end
end)
