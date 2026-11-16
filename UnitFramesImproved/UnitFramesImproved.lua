-- Credits to stassart on curse.com for suggesting to use InCombatLockdown() checks in the code
-- Full credits and changelog in README.md (original by Althalla / Kim Forsberg, WotLK enhancements by Dabsec + Grok)

-- Debug function. Adds message to the chatbox (only visible to the loacl player)
local namefontsize = 12
local function dout(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg);
end

local function tokenize(str)
	local tbl = {};
	for v in string.gmatch(str, "[^ ]+") do
		tinsert(tbl, v);
	end
	return tbl;
end

local UnitFramesImproved_UpdateTargetName

-- local function UnitFramesImproved_HookTargetFrameToT()
-- 	if TargetFrame and not UnitFramesImproved_TargetFrameHooked then
-- 		UnitFramesImproved_TargetFrameHooked = true
-- 		hooksecurefunc(TargetFrame, "Show", UnitFramesImproved_UpdateTargetName)
-- 	end
-- end

local UnitFramesImproved_UpdateTargetName = function()
	if not HM_LibTranslation then return end
	if not UnitExists("target") or UnitIsPlayer("target")  then
		return
	end
	local npcID = GetCreatureIDFromUnit("target")
	if not npcID then return end
	local success, cnName = pcall(HM_LibTranslation.GetUnitCN, HM_LibTranslation, npcID)
	if success and cnName then
		pcall(TargetFrameTextureFrameName.SetText, TargetFrameTextureFrameName, cnName)
		return
	end
	local enName = UnitName("target")
	if enName and enName ~= "" and enName ~= UNKNOWN then
		success, cnName = pcall(HM_LibTranslation.UnitToCN, HM_LibTranslation, enName)
		if success and cnName then
			pcall(TargetFrameTextureFrameName.SetText, TargetFrameTextureFrameName, cnName)
			return
		end
	end

end

-- Create the addon main instance
local UnitFramesImproved = CreateFrame('Button', 'UnitFramesImproved');

-- Defaults are copied, never shared between character settings and profiles.
local function UFI_DefaultSettings()
 return {
  FrameScale = "1.0",
  EnablePlayer = true, EnableTarget = true, EnableFocus = true,
  EnableBoss = true,
  PlayerFrameStyle = "regular", PlayerTargetFrameColor = "silver",
  HideTargetCastbar = false, HideFocusCastbar = false,
  BarTexture = "Default", FollowPortraitDragon = true, HealthBarClassColor = true,
 }
end

local function UFI_FrameEnabled(frame)
 if not frame then return false end
 local settings = characterSettings or {}
 if frame == PlayerFrame then return settings.EnablePlayer ~= false end
 if frame == TargetFrame then return settings.EnableTarget ~= false end
 if frame == FocusFrame then return settings.EnableFocus ~= false end
 for i = 1, 4 do
  if frame == _G["Boss" .. i .. "TargetFrame"] then return settings.EnableBoss ~= false end
 end
 return false
end


-- Event listener to make sure we enable the addon at the right time
function UnitFramesImproved:PLAYER_ENTERING_WORLD()

	-- 设置玩家字体大小
	PlayerName:SetFont(STANDARD_TEXT_FONT, namefontsize, "OUTLINE");
	TargetFrameTextureFrameName:SetFont(STANDARD_TEXT_FONT, namefontsize, "OUTLINE")
	-- Always ensure we have loaded the active profile's data into characterSettings
	-- BEFORE enabling styles. This fixes the case where the profile was not auto-applied
	-- on login until the options panel was opened.
	UnitFramesImproved_LoadActiveProfile()

	-- Set some default settings (only if truly missing)
	if type(characterSettings) ~= "table" then
		UnitFramesImproved_LoadDefaultSettings();
	end

	-- Ensure profile system is ready
	UnitFramesImproved_EnsureProfiles()

	-- 一次性迁移：老版本会给 TargetFrame 打上 userPlaced 标记并强制接管位置。
	-- 若用户从未拖动过目标框，这里清除该标记，让暴雪布局管理器重新接管
	-- （否则目标框会钉死在旧坐标，拖动玩家框时不再跟随）。
	if not characterSettings["TargetFrame_Moved"] and not characterSettings["_TargetUserPlacedCleared"] then
		characterSettings["_TargetUserPlacedCleared"] = true
		if not InCombatLockdown() then
			pcall(TargetFrame.SetUserPlaced, TargetFrame, false)
		end
	end

	-- Force positions from profile/settings on every login (fixes cases where placement
	-- is forgotten on reload until options panel is opened).
	UnitFramesImproved_ApplyFramePositions();

	EnableUnitFramesImproved();

end

-- Note: The zone change handlers + delayed retry in OnUpdate + re-force inside the TargetFrame hooks
-- (TargetFrame_Update and CheckClassification) now ensure that after any teleport or zone transition,
-- we keep re-applying the desired relative position (from your current profile/settings) for up to ~1.2 seconds.
-- This should catch late overrides by the game client.

-- The zone handlers below (plus the calls inside TargetFrame_* hooks) ensure we re-check
-- and re-place the frames after teleports/zone changes, using the same profile-driven position
-- as on initial load. Combined with the 0.3s delayed force in OnUpdate, this should keep
-- the layout consistent.

function UnitFramesImproved:ZONE_CHANGED_NEW_AREA()
	UnitFramesImproved_ApplyFramePositions();
end

function UnitFramesImproved:ZONE_CHANGED()
	UnitFramesImproved_ApplyFramePositions();
end

function UnitFramesImproved:ZONE_CHANGED_INDOORS()
	UnitFramesImproved_ApplyFramePositions();
end

function UnitFramesImproved:PLAYER_TARGET_CHANGED()
	-- 这里不再延长位置监控窗口：每次换目标都续期会让强制重设长期持续，
	-- 与 UIParent_ManageFramePositions 交替执行就是头像漂移的来源。
	UnitFramesImproved_UpdateTargetName();
end

-- Event listener to make sure we've loaded our settings and thta we apply them
function UnitFramesImproved:VARIABLES_LOADED()
	--dout("UnitFramesImproved 设置已加载！");

	-- Set some default settings
	if type(characterSettings) ~= "table" then
		UnitFramesImproved_LoadDefaultSettings();
	end

	-- Profile system initialization + migration from old per-character settings
	UnitFramesImproved_EnsureProfiles()

	if not characterSettings.activeProfile then
		-- Migration: first run with profiles or old character had settings
		local currentProf = globalSettings.profiles["Default"]
		for k, v in pairs(characterSettings) do
			-- Copy old keys into Default profile (skip any old anchor junk)
			if k ~= "activeProfile" and k ~= "PlayerFrameAnchor" then
				currentProf[k] = v
			end
		end
		characterSettings.activeProfile = "Default"
	end

 -- Preserve legacy character-only keys on the first profile migration.
 local profileName = characterSettings.activeProfile or "Default"
 local profile = globalSettings.profiles[profileName]
 if type(profile) == "table" and not characterSettings._ufiProfileKeysMigrated then
  for k, v in pairs(characterSettings) do
   if k ~= "activeProfile" and k ~= "_ufiProfileKeysMigrated" and profile[k] == nil then profile[k] = v end
  end
  profile._ufiProfileKeysMigrated = true
 end
	-- Load the active profile into characterSettings (so all style code sees the right values)
	UnitFramesImproved_LoadActiveProfile()

	if (not (characterSettings["PlayerFrameAnchor"] == nil)) then
		StaticPopup_Show("LAYOUT_RESETDEFAULT");
		characterSettings["PlayerFrameX"] = nil;
		characterSettings["PlayerFrameY"] = nil;
		characterSettings["PlayerFrameMoved"] = nil;
		characterSettings["PlayerFrameAnchor"] = nil;
	end

	UnitFramesImproved_ApplySettings(characterSettings);
end

function UnitFramesImproved_ApplySettings(settings)
 if InCombatLockdown() then
  UnitFramesImproved._pendingApplySettings = true
  return
 end
 UnitFramesImproved._pendingApplySettings = nil
	UnitFramesImproved_SetFrameScale(settings["FrameScale"] or "1.0");

end

-- Force the key unit frame positions (e.g. Target relative to Player) according to defaults/settings.
-- 恢复所有框架位置（登录时和切换区域后调用）
-- TargetFrame的位置修改已移至TargetFrame_Update的secure hook中，避免污染安全框架导致TargetFrameToT:Show()被阻止
function UnitFramesImproved_ApplyFramePositions()
	if not characterSettings or InCombatLockdown() then return end

	-- 恢复玩家框架位置（拖动中跳过）
	if not PlayerFrame._isDragging then
		UnitFramesImproved_LoadFramePosition(PlayerFrame, "PlayerFrame")
	end

	-- 目标框架：通过标记位延迟到TargetFrame_Update的secure hook中执行，避免直接操作安全框架导致污染
	if not TargetFrame._isDragging then
		UnitFramesImproved._pendingTargetFramePosition = true
	end

	-- 焦点框架（拖动中跳过）
	if not FocusFrame._isDragging and characterSettings["FocusFrame_Moved"] then
		UnitFramesImproved_LoadFramePosition(FocusFrame, "FocusFrame")
	end
end

-- 在secure hook中安全地设置目标框架位置（避免污染安全框架）
-- 修复：不在hook中直接操作锚点，而是标记待处理，在安全时机执行
function UnitFramesImproved_ApplyTargetFramePosition()
	if InCombatLockdown() then return end
	if not UnitFramesImproved._pendingTargetFramePosition then return end
	if TargetFrame._isDragging then
		UnitFramesImproved._pendingTargetFramePosition = nil
		return
	end

	-- 标记需要在安全时机执行位置设置，而不是立即执行
	-- 这样可以避免在secure hook中操作锚点导致污染传播到TargetFrameToT
	UnitFramesImproved._needTargetFramePosition = true
	UnitFramesImproved._pendingTargetFramePosition = nil
end

-- 实际执行TargetFrame位置设置的函数（在安全时机调用）
function UnitFramesImproved_ExecuteTargetFramePosition()
	if not characterSettings or InCombatLockdown() then return end
	if not UnitFramesImproved._needTargetFramePosition then return end
	if TargetFrame._isDragging then
		UnitFramesImproved._needTargetFramePosition = nil
		return
	end
	UnitFramesImproved._needTargetFramePosition = nil

	-- 只有用户真正拖动过目标框时才接管它的位置。
	-- 未拖动时保持暴雪默认布局：不要 ClearAllPoints / SetUserPlaced(false)，
	-- 否则会和 UIParent_ManageFramePositions 互相拉扯，造成登陆后头像来回漂移。
	if not characterSettings["TargetFrame_Moved"] then
		return
	end

	local x = characterSettings["TargetFrame_X"]
	local y = characterSettings["TargetFrame_Y"]
	if x and y then
		-- 位置已正确时不再重设
		local curX, curY = TargetFrame:GetLeft(), TargetFrame:GetTop()
		if curX and curY and math.abs(curX - x) < 0.5 and math.abs(curY - y) < 0.5 then
			return
		end
		pcall(function()
			TargetFrame:SetMovable(true)
			TargetFrame:ClearAllPoints()
			TargetFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
			TargetFrame:SetUserPlaced(true)
		end)
	end
end

function UnitFramesImproved_LoadDefaultSettings(resetProfile)
 UnitFramesImproved_EnsureProfiles()
 if resetProfile then
  globalSettings.profiles.Default = UFI_DefaultSettings()
 end
 characterSettings = { activeProfile = "Default" }
 UnitFramesImproved_LoadActiveProfile()
 UnitFramesImproved_ApplyFramePositions()
end

function EnableUnitFramesImproved()
 if InCombatLockdown() then
  UnitFramesImproved._pendingEnable = true
  return
 end
 UnitFramesImproved._pendingEnable = nil
	-- 所有 hooksecurefunc 只装一次：本函数在每次登录、切换配置、点击任何复选框时都会被调用，
	-- 重复安装会导致同一引擎函数被 hook 多层（逻辑重复执行、越点越卡）。
	if not UnitFramesImproved._hooksInstalled then
		UnitFramesImproved._hooksInstalled = true

		-- Generic status text hook
		hooksecurefunc("TextStatusBar_UpdateTextString", UnitFramesImproved_TextStatusBar_UpdateTextString);

		-- Hook PlayerFrame functions
		hooksecurefunc("PlayerFrame_ToPlayerArt", UnitFramesImproved_PlayerFrame_ToPlayerArt);
		hooksecurefunc("PlayerFrame_ToVehicleArt", UnitFramesImproved_PlayerFrame_ToVehicleArt);

		-- Hook TargetFrame functions
		-- Secure post-hooks preserve the original function, but addon callbacks remain insecure.
		hooksecurefunc("TargetFrame_Update", function(...)
		-- 还原流程中跳过图标/样式重挂，只保留位置校正
		if not UnitFramesImproved._restoring then
			UnitFramesImproved_TargetFrame_Update(...)
			UnitFramesImproved_UpdateTargetName();
		end
		UnitFramesImproved_ApplyTargetFramePosition();
		-- 延迟的安全框架属性设置（避免直接操作导致污染）
		if UnitFramesImproved._pendingTargetFrameDragSetup and not InCombatLockdown() then
			pcall(function()
				TargetFrame:SetMovable(true)
				TargetFrame:SetClampedToScreen(true)
			end)
			UnitFramesImproved._pendingTargetFrameDragSetup = nil
		end
		if UnitFramesImproved._pendingTargetFrameStyle and not InCombatLockdown() then
			-- 目标框架样式被禁用时不重挂（否则取消勾选又被盖回去）
			if not characterSettings or characterSettings["EnableTarget"] ~= false then
				pcall(UnitFramesImproved_Style_TargetFrame, TargetFrame)
			end
			UnitFramesImproved._pendingTargetFrameStyle = nil
		end
	end);
	hooksecurefunc("TargetFrame_CheckFaction", UnitFramesImproved_TargetFrame_CheckFaction);
	hooksecurefunc("TargetFrame_CheckClassification", UnitFramesImproved_TargetFrame_CheckClassification);

	-- BossFrame hooks
	hooksecurefunc("BossTargetFrame_OnLoad", UnitFramesImproved_BossTargetFrame_Style);
	end -- end hooks-once guard

	-- Force positions from profile/settings (this replaces the old conditional UserPlaced check
	-- so that the desired relative placement is always enforced on enable/login).
	UnitFramesImproved_ApplyFramePositions();

	-- if not UnitFramesImproved_CreatedTargetFrameToTHook then
	-- 	hooksecurefunc("TargetFrame_CreateTargetofTarget", function(self, unit)
	-- 		UnitFramesImproved_HookTargetFrame()
	-- 	end)
	-- 	UnitFramesImproved_CreatedTargetFrameToTHook = true
	-- end

	-- Also try hooking the frame if it was already created before this addon loaded.
	--UnitFramesImproved_HookTargetFrame();

	-- Set up some stylings (respect enable checkboxes from settings)
	local settings = characterSettings or {};
	if settings["EnablePlayer"] ~= false then
		UnitFramesImproved_Style_PlayerFrame();
	else
		UnitFramesImproved_UnstylePlayerFrame();
	end
	if settings["EnableBoss"] ~= false then
		UnitFramesImproved_BossTargetFrame_Style(Boss1TargetFrame);
		UnitFramesImproved_BossTargetFrame_Style(Boss2TargetFrame);
		UnitFramesImproved_BossTargetFrame_Style(Boss3TargetFrame);
		UnitFramesImproved_BossTargetFrame_Style(Boss4TargetFrame);
	else
		UnitFramesImproved_UnstyleTargetLikeFrame(Boss1TargetFrame);
		UnitFramesImproved_UnstyleTargetLikeFrame(Boss2TargetFrame);
		UnitFramesImproved_UnstyleTargetLikeFrame(Boss3TargetFrame);
		UnitFramesImproved_UnstyleTargetLikeFrame(Boss4TargetFrame);
	end
	if settings["EnableTarget"] ~= false then
        -- EnableUnitFramesImproved already defers all protected changes during combat.
        -- Apply now, even when the current target has not changed.
        UnitFramesImproved._pendingTargetFrameStyle = nil
        UnitFramesImproved_TargetFrame_CheckClassification(TargetFrame)
        UnitFramesImproved_Style_TargetFrame(TargetFrame)
        UnitFramesImproved_TargetFrame_Update(TargetFrame)
	else
		UnitFramesImproved_UnstyleTargetLikeFrame(TargetFrame);
	end
	if settings["EnableFocus"] ~= false then
        UnitFramesImproved_TargetFrame_CheckClassification(FocusFrame)
        UnitFramesImproved_Style_TargetFrame(FocusFrame)
        UnitFramesImproved_TargetFrame_Update(FocusFrame)
	else
		UnitFramesImproved_UnstyleTargetLikeFrame(FocusFrame);
	end

	-- Shift+左键拖拽（玩家/目标/焦点各自独立）
	-- TargetFrame的SetMovable/SetClampedToScreen延迟到secure hook中执行，避免污染
	UnitFramesImproved_EnableFrameDrag(PlayerFrame, "PlayerFrame")
	UnitFramesImproved_SetupFrameDragScripts(TargetFrame, "TargetFrame")
	UnitFramesImproved._pendingTargetFrameDragSetup = true
	UnitFramesImproved_EnableFrameDrag(FocusFrame, "FocusFrame")

	-- Apply target + focus castbar visibility toggles (for other castbar addons)
	UnitFramesImproved_ApplyCastbarVisibility();

	-- Apply custom bar textures for player + target (if not Default)
	UnitFramesImproved_ApplyBarTextures();

 if UFI_ClassHealthColors_Refresh then UFI_ClassHealthColors_Refresh() end

	-- REMOVED: UIParent_ManageFramePositions hook caused secure frame taint (TargetFrameToT:Show() blocked).
	-- Position correction is still handled by ZONE_CHANGED events and the OnUpdate monitoring loop.
end

-- Shift+左键拖拽：保存位置（使用 GetLeft/GetTop 绝对坐标）
local function UnitFramesImproved_SaveFramePosition(frame, settingKey)
	if InCombatLockdown() or not frame or not settingKey then return end
	characterSettings[settingKey .. "_X"] = frame:GetLeft()
	characterSettings[settingKey .. "_Y"] = frame:GetTop()
	characterSettings[settingKey .. "_Moved"] = true
	local profName = characterSettings.activeProfile or "Default"
	if globalSettings.profiles and globalSettings.profiles[profName] then
		globalSettings.profiles[profName][settingKey .. "_X"] = characterSettings[settingKey .. "_X"]
		globalSettings.profiles[profName][settingKey .. "_Y"] = characterSettings[settingKey .. "_Y"]
		globalSettings.profiles[profName][settingKey .. "_Moved"] = true
	end
end

-- 从保存的绝对坐标恢复位置
-- 位置已经正确时直接跳过：反复 ClearAllPoints + SetPoint 会重启布局求解，
-- 与 UIParent_ManageFramePositions 交替执行就会表现为头像来回漂移。
function UnitFramesImproved_LoadFramePosition(frame, settingKey)
	local x = characterSettings[settingKey .. "_X"]
	local y = characterSettings[settingKey .. "_Y"]
	if not (x and y) or InCombatLockdown() or not frame then return end
	-- 与 TargetFrame 相同的策略：只有用户真正拖动过（_Moved）才接管位置，
	-- 避免和 UIParent_ManageFramePositions 互相拉扯造成登陆后头像漂移。
	if not characterSettings[settingKey .. "_Moved"] then return end

	local curX, curY = frame:GetLeft(), frame:GetTop()
	if curX and curY and math.abs(curX - x) < 0.5 and math.abs(curY - y) < 0.5 then
		return
	end

	frame:SetMovable(true)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	frame:SetUserPlaced(true)
end

-- Shift+左键拖拽框架（玩家/目标/焦点各自独立）
-- 注意：SetMovable/SetClampedToScreen会污染安全框架，对于TargetFrame已移至secure hook中执行
function UnitFramesImproved_EnableFrameDrag(frame, settingKey)
	if not frame or InCombatLockdown() then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	UnitFramesImproved_SetupFrameDragScripts(frame, settingKey)
end

-- 仅设置拖拽脚本，不修改安全框架属性（用于需要在secure hook中设置属性的框架）
function UnitFramesImproved_SetupFrameDragScripts(frame, settingKey)
 if not frame or frame._ufiDragHooksInstalled then return end
 frame._ufiDragHooksInstalled = true
 frame:HookScript("OnMouseDown", function(self, button)
  if button ~= "LeftButton" or not IsShiftKeyDown() or InCombatLockdown() then return end
  if self._isDragging then return end
  self:StartMoving()
  self._isDragging = true
 end)
 frame:HookScript("OnMouseUp", function(self, button)
  if button ~= "LeftButton" or not self._isDragging then return end
  self._isDragging = nil
  if InCombatLockdown() then
   self._ufiStopDragAfterCombat = true
   return
  end
  self:StopMovingOrSizing()
  self:SetUserPlaced(true)
  UnitFramesImproved_SaveFramePosition(self, settingKey)
 end)
 frame:HookScript("OnHide", function(self)
  if not self._isDragging then return end
  self._isDragging = nil
  if InCombatLockdown() then
   self._ufiStopDragAfterCombat = true
  else
   self:StopMovingOrSizing()
   UnitFramesImproved_SaveFramePosition(self, settingKey)
  end
 end)
end

-- ============ 经典宽血条 ============
-- 根因说明：直接把引擎条改为 119x29 @ (106,-22) 本身没问题——两截颜色的真正原因是
-- UFI 老版本给条设了 lockColor=true，把引擎 Lua 层填充（上半截）的颜色冻结；
-- 而引擎 C++ 自绘填充（下半截）不理会这个锁、继续按血量正常变色 → 上下两截颜色。
-- 引擎 UnitFrameHealthBar_Update 本来每次掉血都会给整根条重新插值上色，
-- 只要 lockColor=false、插件不再强刷颜色，两层填充颜色一致，分界自然消失。
-- 因此这里只恢复几何与文字位置，颜色完全交给引擎。

-- CoA adds a tinted player-name material separate from the health fill.
-- Runtime inventory identified an anonymous Smooth texture on PlayerFrame,
-- and TargetFrame.nameBackground. Hide these, not the health statusbar.
local ufiNameBackgrounds = {}
local ufiAdjustingNameBackground = false
local function UFI_KeepNameBackgroundHidden(texture)
    local entry = ufiNameBackgrounds[texture]
    if ufiAdjustingNameBackground or not entry or UnitFramesImproved._restoring
        or not UFI_FrameEnabled(entry.frame) then return end
    ufiAdjustingNameBackground = true
    texture:SetAlpha(0)
    ufiAdjustingNameBackground = false
end
local function UFI_TrackNameBackground(texture, frame)
    if not texture or not texture.SetAlpha then return end
    if not ufiNameBackgrounds[texture] then
        ufiNameBackgrounds[texture] = {frame=frame, alpha=texture:GetAlpha()}
        -- Texture regions have no OnShow scripts; use secure method post-hooks.
        for _, method in ipairs({"Show", "SetAlpha", "SetVertexColor", "SetTexture"}) do
            if texture[method] then
                hooksecurefunc(texture, method, function(self) UFI_KeepNameBackgroundHidden(self) end)
            end
        end
    end
    UFI_KeepNameBackgroundHidden(texture)
end
function UnitFramesImproved_HideNameBackgrounds(frame)
    if not UFI_FrameEnabled(frame) or UnitFramesImproved._restoring then return end
    if frame == TargetFrame then
        UFI_TrackNameBackground(frame.nameBackground, frame)
    elseif frame == PlayerFrame and PlayerFrameHealthBar then
        local bar = PlayerFrameHealthBar
        local top, bottom = bar:GetTop(), bar:GetBottom()
        local fill = bar:GetStatusBarTexture()
        if top and bottom then
            for i=1, frame:GetNumRegions() do
                local region = select(i, frame:GetRegions())
                if region and region ~= fill and region.GetTexture and not region:GetName() then
                    local texture = region:GetTexture()
                    local layer = region:GetDrawLayer()
                    local rt, rb = region:GetTop(), region:GetBottom()
                    local rl, rr = region:GetLeft(), region:GetRight()
                    -- GetSize can report the source-image dimensions (256x32).
                    -- Actual bounds locate the separate name strip (about 118x16).
                    if type(texture)=="string" and string.find(string.lower(texture), "sharedmedia", 1, true)
                        and layer=="BACKGROUND" and rt and rb and rl and rr
                        and rr-rl >= 50 and rt-rb <= 22
                        and rt <= top+2 and rt > bottom and rb > bottom then
                        UFI_TrackNameBackground(region, frame)
                    end
                end
            end
        end
    end
end
local function UFI_RestoreNameBackgrounds(frame)
    ufiAdjustingNameBackground = true
    for texture, entry in pairs(ufiNameBackgrounds) do
        if entry.frame == frame then texture:SetAlpha(entry.alpha) end
    end
    ufiAdjustingNameBackground = false
end

function UnitFramesImproved_Style_PlayerFrame()
	UnitFramesImproved_HideNameBackgrounds(PlayerFrame)
	if not InCombatLockdown() then
		-- 绝不锁色：lockColor=true 是"上下两截颜色"的元凶
		PlayerFrameHealthBar.lockColor = false;
		PlayerFrameHealthBar.capNumericDisplay = true;
		-- 经典宽血条几何（覆盖名字行，名字与数字显示在条内）
		PlayerFrameHealthBar:SetWidth(116);
		PlayerFrameHealthBar:SetHeight(29);
		PlayerFrameHealthBar:ClearAllPoints();
        PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -22);
		PlayerFrameHealthBarText:SetPoint("CENTER", 50, 6);
	end

	local playerArt = UnitFramesImproved_GetPlayerFrameTexture();
	if playerArt then
		PlayerFrameTexture:SetTexture(playerArt);
	end
	PlayerStatusTexture:SetTexture("Interface\\Addons\\UnitFramesImproved\\Textures\\UI-Player-Status");
	--PlayerName:SetFont(STANDARD_TEXT_FONT, namefontsize, "OUTLINE");

	-- Use the separate Player/Target color setting (not the party one)
	UnitFramesImproved_ApplyPlayerTargetTint(PlayerFrameTexture, "player");

	UnitFramesImproved_ApplyBarTextures(); -- apply custom bar texture if set (player only)


end

-- Note: heal/absorb prediction bars are created in Style_PlayerFrame and Style_TargetFrame (target only)
-- and updated via the text status hook and style/update paths for live projected heals.

function UnitFramesImproved_Style_TargetFrame(self)
 if not UFI_FrameEnabled(self) then return end
	UnitFramesImproved_HideNameBackgrounds(self)
	if not InCombatLockdown() then
		self.nameBackground:Hide();
	end

	-- 经典宽血条几何（只给 TargetFrame；焦点/首领不套）。
	-- 颜色同样交给引擎（不设 lockColor、不强刷颜色），避免上下两截颜色。
	if self == TargetFrame and self.healthbar and not InCombatLockdown() then
		self.healthbar.lockColor = false;
		self.healthbar:SetWidth(119);
		self.healthbar:SetHeight(29);
		self.healthbar:ClearAllPoints();
        self.healthbar:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -22);
		if self.healthbar.TextString then
			self.healthbar.TextString:SetPoint("CENTER", -50, 6);
		end
		if self.deadText then
			self.deadText:SetPoint("CENTER", -50, 6);
		end
	end

	-- Apply separate player/target color tint to the border (class or black)
	if self.borderTexture then
		UnitFramesImproved_ApplyPlayerTargetTint(self.borderTexture, self.unit);
	end

	UnitFramesImproved_ApplyBarTextures(); -- apply custom bar texture if set (target only)

	-- Hide Blizzard's default targeting-frame art regions that can overlap our border texture.
	-- This prevents both the original and our custom textures from displaying at the same time.
	-- Only safe to do outside of combat; Hide() on secure frame children causes taint.
	if not InCombatLockdown() and self.GetNumRegions then
		local numRegions = self:GetNumRegions() or 0;
		for i = 1, numRegions do
			local region = select(i, self:GetRegions());
			if region and region.GetObjectType and region:GetObjectType() == "Texture" then
				-- Skip our configured borderTexture region
				if region ~= self.borderTexture then
					local okTex = region.GetTexture and region:GetTexture();
					if okTex and string.find(okTex, "Interface\\TargetingFrame") then
						region:Hide();
						region._ufiHidden = true; -- 打标：取消勾选还原原生时按标记恢复
					end
				end
			end
		end
	end

	-- 治疗预言/吸收条已移除（引擎自带 MoP 式预测条，避免双重叠加）


end

-- ============ 取消勾选时还原引擎原生外观 ============
-- 早期版本取消勾选只"跳过套样式"，已套的样式永远留在框上（表现为复选框"点了没效果"）。
-- 现在借用引擎自带的重置函数（PlayerFrame_ToPlayerArt / TargetFrame_Update）还原原生几何与纹理；
-- 期间置 _restoring 标志，让我们自己的 secure hook 跳过重新加样式，避免刚还原又被 hook 盖回去。

-- 恢复被 Style_TargetFrame 隐藏的原生装饰纹理 + 名字底 + 隐藏职业图标
function UnitFramesImproved_RestoreFrameDecor(frame)
	if not frame then return end
	UFI_RestoreNameBackgrounds(frame)
	if frame.nameBackground then frame.nameBackground:Show(); end
	if frame.GetNumRegions then
		local numRegions = frame:GetNumRegions() or 0;
		for i = 1, numRegions do
			local region = select(i, frame:GetRegions());
			if region and region._ufiHidden then
				region:Show();
				region._ufiHidden = nil;
			end
		end
	end
end

-- 把目标模板框架（Target/Focus/Boss）的血条几何还原为引擎 XML 原生值（119x12 @ TOPRIGHT(-106,-41)）
function UnitFramesImproved_RestoreTargetBarGeometry(frame)
	if not frame or not frame.healthbar or InCombatLockdown() then return end
	local hb = frame.healthbar;
	hb:SetWidth(119);
	hb:SetHeight(12);
	hb:ClearAllPoints();
	hb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -106, -41);
	if hb.TextString then hb.TextString:SetPoint("CENTER", -50, 3); end
	if frame.deadText then frame.deadText:SetPoint("CENTER", -50, 3); end
end

function UnitFramesImproved_UnstylePlayerFrame()
	if InCombatLockdown() then return end
	UnitFramesImproved._restoring = true
    -- Restore artwork only: the native ToPlayerArt also writes PlayerFrame.unit
    -- and secure unit attributes, which TargetofTarget_Update subsequently reads.
    local _, class = UnitClass("player")
    local dragon = UnitFramesImproved_IsPortraitDragonOn()
    local art
    if class == "HERO" then
        art = dragon and "Interface\\TargetingFrame\\UI-HeroFrame-Dragon" or "Interface\\TargetingFrame\\UI-HeroFrame"
    else
        art = dragon and "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite" or "Interface\\TargetingFrame\\UI-TargetingFrame"
    end
    if PlayerFrameTexture then
        PlayerFrameTexture:SetTexture(art)
        PlayerFrameTexture:SetVertexColor(1, 1, 1, 1)
    end
    if PlayerName then PlayerName:SetPoint("CENTER", 50, 19) end
	UnitFramesImproved._restoring = nil
	-- ToPlayerArt 只重设宽度/锚点，不重设高度和文字位置，手动补齐原生值（PlayerFrame.xml: CENTER 50,3）
	if PlayerFrameHealthBar then
		PlayerFrameHealthBar:SetHeight(12);
        PlayerFrameHealthBar:ClearAllPoints();
        PlayerFrameHealthBar:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -41);
        PlayerFrameHealthBarText:SetPoint("CENTER", 50, 3);
	end
	UnitFramesImproved_RestoreFrameDecor(PlayerFrame);
	-- 名字字体是插件设置的，与样式开关无关，重套一次
	PlayerName:SetFont(STANDARD_TEXT_FONT, namefontsize, "OUTLINE");
end

function UnitFramesImproved_UnstyleTargetLikeFrame(frame)
	if not frame or InCombatLockdown() then return end
	-- Restore visual regions only. Calling the native update from addon code
	-- also runs TargetofTarget_Update and writes native state in a tainted path.
	-- Neither pcall nor a secure post-hook grants secure execution privileges.
	if frame.borderTexture then
		local classification = frame.unit and UnitClassification(frame.unit)
		local suffix = ""
		if classification == "elite" or classification == "worldboss" then
			suffix = "-Elite"
		elseif classification == "rareelite" then
			suffix = "-Rare-Elite"
		elseif classification == "rare" then
			suffix = "-Rare"
		end
		frame.borderTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame" .. suffix)
		frame.borderTexture:SetVertexColor(1, 1, 1, 1)
	end
	UnitFramesImproved_RestoreTargetBarGeometry(frame);
	UnitFramesImproved_RestoreFrameDecor(frame);
end

function UnitFramesImproved_BossTargetFrame_Style(self)
 if not UFI_FrameEnabled(self) then return end
	if not InCombatLockdown() then
		self.borderTexture:SetTexture("Interface\\Addons\\UnitFramesImproved\\Textures\\UI-UnitFrame-Boss");
	end

	UnitFramesImproved_Style_TargetFrame(self);
	if (not (characterSettings["FrameScale"] == nil)) then
		if not InCombatLockdown() then
			self:SetScale(characterSettings["FrameScale"] * 0.9);
		end
	end
end

function UnitFramesImproved_SetFrameScale(scale)
	if not InCombatLockdown() then
		-- Scale the main frames (Player, Target, Focus, Boss).
		PlayerFrame:SetScale(scale);
		TargetFrame:SetScale(scale);
		FocusFrame:SetScale(scale);

		-- Scale sub-frames
		ComboFrame:SetScale(scale);
		--RuneFrame:SetScale(scale); -- Can't do this as it messes up the scale horribly
		RuneButtonIndividual1:SetScale(scale);
		RuneButtonIndividual2:SetScale(scale);
		RuneButtonIndividual3:SetScale(scale);
		RuneButtonIndividual4:SetScale(scale);
		RuneButtonIndividual5:SetScale(scale);
		RuneButtonIndividual6:SetScale(scale);

		-- Scale the BossFrames
		Boss1TargetFrame:SetScale(scale * 0.9);
		Boss2TargetFrame:SetScale(scale * 0.9);
		Boss3TargetFrame:SetScale(scale * 0.9);
		Boss4TargetFrame:SetScale(scale * 0.9);

		UnitFramesImproved_SetSetting("FrameScale", scale);
	end
end

-- Update projected heal (green, semi-transparent) and absorb (blue, semi-transparent) overlays
-- on top of the health bar for player and target only. These use full healthbar height.
-- Heal prediction now only shows the *effective* amount that can actually be applied
-- (it shrinks and disappears as health fills up from HoTs, even if the HoT still has duration).
function UnitFramesImproved_UpdateHealPrediction(healthBar, unit)
	-- 已停用：飞升引擎的 UnitFrame 是 MoP 结构，自带
	-- MyHealPredictionBar / OtherHealPredictionBar / TotalAbsorbBar 预测条。
	-- UFI 再画一份会与引擎层双重叠加（血条出现异常色块）。保留空函数以免调用点报错。
	return
end

-- Player frame border styles (only for the player frame, using the textures already shipped with this addon)
UnitFramesImproved.playerFrameStyles = {
	{ key = "regular", name = "普通", texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame" },
	{ key = "silver", name = "银色精英", texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite" },
	{ key = "gold", name = "金色精英", texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite" },
};

-- ============================================
-- SharedMedia bar texture support (only for Player + Target as requested)
-- ============================================

-- Returns list of available statusbar textures from LibSharedMedia + "Default"
function UnitFramesImproved_GetBarTextureList()
	if UnitFramesImproved.barTextureList then
		return UnitFramesImproved.barTextureList
	end

	local list = { "Default" }
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local media = LSM:List("statusbar") or {}
		for _, name in ipairs(media) do
			table.insert(list, name)
		end
	end
	UnitFramesImproved.barTextureList = list
	return list
end

function UnitFramesImproved_ApplyBarTextures()
    if not characterSettings or InCombatLockdown() then return end
    local name = characterSettings.BarTexture or "Default"
    if UnitFramesImproved._barTextureTestNative then name = "Default" end
    local texture = "Interface\\TargetingFrame\\UI-StatusBar"
    if name ~= "Default" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if not LSM then return end
        texture = LSM:Fetch("statusbar", name, true)
        if not texture then return end
    end
    -- Default must actively restore the native material. Do not repeatedly
    -- replace an unchanged statusbar texture during frame refreshes.
    local function Apply(bar)
        if not bar then return end
        local fill = bar:GetStatusBarTexture()
        local current = fill and fill:GetTexture()
        if type(current) ~= "string" or string.lower(current) ~= string.lower(texture) then
            bar:SetStatusBarTexture(texture)
        end
    end
    Apply(PlayerFrameHealthBar)
    Apply(PlayerFrameManaBar)
    Apply(TargetFrameHealthBar)
    Apply(TargetFrameManaBar)
end

-- 读取客户端 CVar 布尔值（飞升提供 C_CVar.GetBool，标准 3.3.5 用 GetCVar）
local function UnitFramesImproved_GetCVarBool(name)
	if type(C_CVar) == "table" and type(C_CVar.GetBool) == "function" then
		local ok, v = pcall(C_CVar.GetBool, name);
		if ok then return v == true or v == 1; end
	end
	if type(GetCVar) == "function" then
		local ok, v = pcall(GetCVar, name);
		if ok then return v == "1" or v == 1 or v == true; end
	end
	return false;
end

-- 游戏内的"头像龙框"（玩家头像精英龙框）开关是否打开
function UnitFramesImproved_IsPortraitDragonOn()
	if characterSettings and characterSettings["FollowPortraitDragon"] == false then return false; end
	return UnitFramesImproved_GetCVarBool("showPortraitDragon");
end

function UnitFramesImproved_GetPlayerFrameTexture()
	local style = (characterSettings and characterSettings["PlayerFrameStyle"]) or "regular";

	-- 跟随游戏内头像龙框：开启时改用带龙的精英边框（客户端原生逻辑同为 Rare-Elite）
	if UnitFramesImproved_IsPortraitDragonOn() then
		local _, class = UnitClass("player");
		if class == "HERO" then
			-- 英雄职业用的是客户端专属 UI-HeroFrame(-Dragon)，本插件未附带，直接沿用客户端艺术图
			return nil;
		end
		if style ~= "gold" then style = "silver"; end
	end

	for _, s in ipairs(UnitFramesImproved.playerFrameStyles or {}) do
		if s.key == style then
			return s.texture;
		end
	end
	return "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame";
end

-- Apply border tint for player/target/focus frames using the separate PlayerTargetFrameColor setting.
-- "class" = unit's class color (or reaction), "black" = dark gray.
function UnitFramesImproved_ApplyPlayerTargetTint(textureRegion, unit)
	if not textureRegion or not textureRegion.SetVertexColor then return end
	local cmode = characterSettings and characterSettings["PlayerTargetFrameColor"] or "silver";
	local r, g, b = 1, 1, 1;
	if cmode == "silver" then
		-- Standard / original look - no extra tint, shows the frame texture's native colors
		r, g, b = 1, 1, 1;
	elseif cmode == "class" then
		if unit then
			local cr, cg, cb = UnitColor(unit);
			if cr then r, g, b = cr, cg, cb; end
		end
	elseif cmode == "black" then
		r, g, b = 0.15, 0.15, 0.15;
	end
	textureRegion:SetVertexColor(r, g, b, 1);
end

-- Hide or restore Blizzard's TargetFrameSpellBar (the default target castbar).
-- When hidden, we install a simple OnShow that immediately hides it again so other
-- addons can provide their own without doubles. When shown, we clear the forcing script.
function UnitFramesImproved_ApplyCastbarVisibility()
 if InCombatLockdown() then
  UnitFramesImproved._pendingCastbarVisibility = true
  return
 end
 UnitFramesImproved._pendingCastbarVisibility = nil
 for _, entry in ipairs({ {TargetFrameSpellBar, "HideTargetCastbar"}, {FocusFrameSpellBar, "HideFocusCastbar"} }) do
  local bar, key = entry[1], entry[2]
  if bar then
   if not bar._ufiVisibilityHookInstalled then
    bar._ufiVisibilityHookInstalled = true
    local settingKey = key
    bar:HookScript("OnShow", function(self)
     if characterSettings and characterSettings[settingKey] then
      if InCombatLockdown() then
       UnitFramesImproved._pendingCastbarVisibility = true
      else
       self:Hide()
      end
     end
    end)
   end
   if characterSettings and characterSettings[key] then bar:Hide() end
  end
 end
end

-- ============================================
-- Profile System (global profiles, per-character active profile)
-- ============================================

function UnitFramesImproved_EnsureProfiles()
 if type(globalSettings) ~= "table" then globalSettings = {} end
 if type(globalSettings.profiles) ~= "table" then globalSettings.profiles = {} end
 if type(globalSettings.profiles.Default) ~= "table" then
  globalSettings.profiles.Default = UFI_DefaultSettings()
 end
end

-- Load the active profile (from globalSettings) into characterSettings so that
-- all the existing style/apply code sees the correct values.
-- This is now called explicitly on login (PLAYER_ENTERING_WORLD) and after
-- migration (VARIABLES_LOADED) so the saved profile always applies automatically
-- for every character without having to open the options panel.
function UnitFramesImproved_LoadActiveProfile()
 UnitFramesImproved_EnsureProfiles()
 local activeName = type(characterSettings) == "table" and characterSettings.activeProfile or "Default"
 if type(globalSettings.profiles[activeName]) ~= "table" then activeName = "Default" end
 local settings = UFI_DefaultSettings()
 for k, v in pairs(globalSettings.profiles[activeName]) do
  if k ~= "activeProfile" then settings[k] = v end
 end
 settings.activeProfile = activeName
 characterSettings = settings
end

function UnitFramesImproved_GetActiveProfileName()
	if characterSettings and characterSettings.activeProfile then
		return characterSettings.activeProfile
	end
	return "Default"
end

function UnitFramesImproved_GetActiveProfile()
	UnitFramesImproved_EnsureProfiles()
	local name = UnitFramesImproved_GetActiveProfileName()
	if globalSettings.profiles[name] then
		return globalSettings.profiles[name]
	end
	return globalSettings.profiles["Default"]
end

function UnitFramesImproved_SwitchToProfile(name)
 UnitFramesImproved_EnsureProfiles()
 if type(globalSettings.profiles[name]) ~= "table" then name = "Default" end
 characterSettings = { activeProfile = name }
 UnitFramesImproved_LoadActiveProfile()
 UnitFramesImproved_ApplySettings(characterSettings)
 EnableUnitFramesImproved()
 UnitFramesImproved_ApplyFramePositions()
end

function UnitFramesImproved_CreateNewProfile(suggestedName)
	UnitFramesImproved_EnsureProfiles()
	local profiles = globalSettings.profiles
	local base = suggestedName or "New Profile"
	local newName = base
	local counter = 1
	while profiles[newName] do
		counter = counter + 1
		newName = base .. " " .. counter
	end

	-- Copy current active settings
	local current = UnitFramesImproved_GetActiveProfile()
	profiles[newName] = {}
	for k, v in pairs(current) do
		profiles[newName][k] = v
	end

	UnitFramesImproved_SwitchToProfile(newName)
	return newName
end

function UnitFramesImproved_DeleteProfile(name)
	UnitFramesImproved_EnsureProfiles()
	local profiles = globalSettings.profiles
	if not profiles[name] then return false end

	-- Don't allow deleting the last profile
	local count = 0
	for _ in pairs(profiles) do count = count + 1 end
	if count <= 1 then return false end

	profiles[name] = nil

	if UnitFramesImproved_GetActiveProfileName() == name then
		UnitFramesImproved_SwitchToProfile("Default")
	end
	return true
end

function UnitFramesImproved_GetProfileNames()
	UnitFramesImproved_EnsureProfiles()
	local names = {}
	for name in pairs(globalSettings.profiles) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Helper to set a setting both in characterSettings and the active global profile
function UnitFramesImproved_SetSetting(key, value)
	if not characterSettings then characterSettings = {} end
	characterSettings[key] = value

	local prof = UnitFramesImproved_GetActiveProfile()
	prof[key] = value
end

-- ============================================
-- Create Options Panel (called early so slash command can reference it)
-- ============================================
function UnitFramesImproved_CreateOptionsPanel()
	if UnitFramesImproved.panelSettings then return; end

	local panel = CreateFrame("Frame", "UnitFramesImprovedOptionsPanel");
	panel.name = "UnitFramesImproved";
	UnitFramesImproved.panelSettings = panel;

	-- Title
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetText("UnitFramesImproved 设置");

	-- Description
	local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	desc:SetText("配置大小、边框样式、条材质等。修改会立即生效。(条材质适用于玩家和目标)");
	desc:SetWidth(550); -- allow word wrap so it doesn't overflow the panel width

	-- === Scale Section ===
	local scaleTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	scaleTitle:SetText("全局缩放 (玩家 / 目标 / 焦点 / Boss)");

	local scaleSlider = CreateFrame("Slider", "UFI_ScaleSlider", panel, "OptionsSliderTemplate");
	scaleSlider:SetWidth(300);
	scaleSlider:SetMinMaxValues(0.5, 2.0);
	scaleSlider:SetValueStep(0.05);
	-- SetObeyStepOnDrag does not exist on 3.3.5 (WotLK). Guard for compatibility.
	if scaleSlider.SetObeyStepOnDrag then
		scaleSlider:SetObeyStepOnDrag(true);
	end

	-- Slider labels
	getglobal(scaleSlider:GetName() .. "Low"):SetText("0.5");
	getglobal(scaleSlider:GetName() .. "High"):SetText("2.0");
	local scaleText = getglobal(scaleSlider:GetName() .. "Text");
	scaleText:SetText("缩放 (玩家/目标/焦点/Boss)");
	scaleText:SetWidth(300); -- wrap long scale description text so it doesn't overflow the panel

	scaleSlider:SetScript("OnValueChanged", function(self, value)
		if characterSettings then
			-- Snap to 0.05 steps (classic sliders without SetObeyStepOnDrag don't always snap cleanly)
			value = math.floor(value * 20 + 0.5) / 20;
			UnitFramesImproved_SetSetting("FrameScale", tostring(value));
			UnitFramesImproved_SetFrameScale(tostring(value));
		end
	end);

	-- === Frame Types Section ===
	local framesTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	framesTitle:SetText("启用哪些框架的样式");

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	note:SetText("玩家/目标使用宽血条；Boss缩放为主缩放的90%。");
	note:SetWidth(550);
	note:SetHeight(30);

	local function CreateEnableCheckbox(label, key)
		local cb = CreateFrame("CheckButton", "UFI_" .. key .. "CB", panel, "InterfaceOptionsCheckButtonTemplate");
		getglobal(cb:GetName() .. "Text"):SetText(label);
		cb:SetScript("OnClick", function(self)
			if characterSettings then
				-- GetChecked() 取消勾选时返回 nil（不是 false）；存 nil 会让 OnShow 的
				-- "~= false" 判断把 nil 当成"启用"，复选框就永远回弹到勾选态 —— 必须归一化。
				UnitFramesImproved_SetSetting(key, self:GetChecked() and true or false);
				EnableUnitFramesImproved();
			end
		end);
		return cb;
	end

	-- Frame toggles; all positions are assigned by the layout block below.
	local cbPlayer = CreateEnableCheckbox("玩家框架", "EnablePlayer");
	local cbBoss = CreateEnableCheckbox("Boss框架 (4)", "EnableBoss");
	local cbTarget = CreateEnableCheckbox("目标框架", "EnableTarget");
	local cbFocus = CreateEnableCheckbox("焦点框架", "EnableFocus");

	-- === Player Frame Border Style (player only) ===
	local playerBorderTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	playerBorderTitle:SetText("玩家边框与条材质");

	local playerBorderNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	playerBorderNote:SetText("(仅改变你自己的玩家框架。生命值、法力值和颜色保持不变。)");
	playerBorderNote:SetWidth(550);

	local playerBorderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	playerBorderLabel:SetText("边框:");

	local playerBorderButton = CreateFrame("Button", "UFI_PlayerBorderButton", panel, "UIPanelButtonTemplate");
	playerBorderButton:SetSize(120, 18);
	playerBorderButton:SetText("普通");

	local playerBorderDisplay = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	playerBorderDisplay:SetText("");

	-- 跟随游戏内"头像龙框"开关（showPortraitDragon）：打开后玩家框自动换成带龙的精英边框
	local cbDragon = CreateFrame("CheckButton", "UFI_FollowPortraitDragonCB", panel, "InterfaceOptionsCheckButtonTemplate");
	getglobal(cbDragon:GetName() .. "Text"):SetText("跟随游戏内头像龙框 (精英框)");
	cbDragon:SetScript("OnClick", function(self)
		if characterSettings then
			UnitFramesImproved_SetSetting("FollowPortraitDragon", self:GetChecked() and true or false);
			if characterSettings["EnablePlayer"] ~= false then
				UnitFramesImproved_Style_PlayerFrame();
			end
		end
	end);

	playerBorderButton:SetScript("OnClick", function()
		if not characterSettings or not UnitFramesImproved.playerFrameStyles then return; end
		local cur = characterSettings["PlayerFrameStyle"] or "regular";
		local idx = 1;
		for i, s in ipairs(UnitFramesImproved.playerFrameStyles) do
			if s.key == cur then
				idx = i;
				break;
			end
		end
		idx = (idx % #UnitFramesImproved.playerFrameStyles) + 1;
		local newStyle = UnitFramesImproved.playerFrameStyles[idx];
		UnitFramesImproved_SetSetting("PlayerFrameStyle", newStyle.key);
		playerBorderButton:SetText(newStyle.name);
		playerBorderDisplay:SetText(newStyle.key);

		if characterSettings["EnablePlayer"] ~= false then
			UnitFramesImproved_Style_PlayerFrame();
		end
	end);

	-- Color Tint (Player/Target) - placed right after border for compactness
	local ptColorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	ptColorLabel:SetText("颜色着色 (玩家/目标/焦点):");

	local ptColorButton = CreateFrame("Button", "UFI_PlayerTargetColorButton", panel, "UIPanelButtonTemplate");
	ptColorButton:SetSize(110, 18);
	ptColorButton:SetText("银色 (原始)");

	ptColorButton:SetScript("OnClick", function()
		if not characterSettings then return end
		local order = { "silver", "class", "black" };
		local cur = characterSettings["PlayerTargetFrameColor"] or "silver";
		local idx = 1;
		for i, v in ipairs(order) do
			if v == cur then
				idx = i; break;
			end
		end
		idx = (idx % #order) + 1;
		local nxt = order[idx];
		UnitFramesImproved_SetSetting("PlayerTargetFrameColor", nxt);

		local labels = { silver = "银色", class = "职业", black = "黑色" };
		ptColorButton:SetText(labels[nxt] or nxt);

		if characterSettings["EnablePlayer"] ~= false then
			UnitFramesImproved_Style_PlayerFrame();
		end
		if characterSettings["EnableTarget"] ~= false then
			UnitFramesImproved_TargetFrame_CheckClassification(TargetFrame);
			UnitFramesImproved_Style_TargetFrame(TargetFrame);
		end
		if characterSettings["EnableFocus"] ~= false then
			UnitFramesImproved_TargetFrame_CheckClassification(FocusFrame);
			UnitFramesImproved_Style_TargetFrame(FocusFrame);
		end
	end);

	-- Bar Texture - next
	local barTextureLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	barTextureLabel:SetText("条材质（玩家/目标）:");

	local barTextureButton = CreateFrame("Button", "UFI_BarTextureButton", panel, "UIPanelButtonTemplate");
	barTextureButton:SetSize(110, 18);
	barTextureButton:SetText("默认");

	local barTextureDisplay = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	barTextureDisplay:SetText("");

    local textureMenu = CreateFrame("Frame", "UFI_TextureSelectionMenu", panel, "UIDropDownMenuTemplate")
    barTextureButton:SetText("选择材质")
    barTextureButton:SetScript("OnClick", function()
        if InCombatLockdown() then
            DEFAULT_CHAT_FRAME:AddMessage("UFI：请脱战后调整条材质。")
            return
        end
        local list = UnitFramesImproved_GetBarTextureList()
        local current = characterSettings and characterSettings.BarTexture or "Default"
        local menu = {}
        local function Entry(name)
            return {text=name=="Default" and "默认（游戏原生）" or name,
                checked=current==name, func=function()
                    UnitFramesImproved_SetSetting("BarTexture", name)
                    UnitFramesImproved._barTextureTestNative = nil
                    barTextureButton:SetText(name=="Default" and "默认" or name)
                    barTextureDisplay:SetText("")
                    UnitFramesImproved_ApplyBarTextures()
                end}
        end
        menu[1]=Entry("Default")
        local group
        for i=2,#list do
            if #list <= 13 then
                menu[#menu+1]=Entry(list[i])
            else
                if (i-2)%12==0 then
                    group={}
                    menu[#menu+1]={text="材质 "..(i-1).."–"..math.min(i+10,#list-1),
                        hasArrow=true,notCheckable=true,menuList=group}
                end
                group[#group+1]=Entry(list[i])
            end
        end
        EasyMenu(menu, textureMenu, barTextureButton, 0, 0, "MENU")
    end)

	-- Castbar hides - compact, two small checkboxes
	local cbHideCastbar = CreateFrame("CheckButton", "UFI_HideTargetCastbarCB", panel,
		"InterfaceOptionsCheckButtonTemplate");
	getglobal(cbHideCastbar:GetName() .. "Text"):SetText("隐藏目标施法条");
	cbHideCastbar:SetScript("OnClick", function(self)
		if characterSettings then
			UnitFramesImproved_SetSetting("HideTargetCastbar", self:GetChecked() and true or false);
			UnitFramesImproved_ApplyCastbarVisibility();
		end
	end);

	local cbHideFocusCastbar = CreateFrame("CheckButton", "UFI_HideFocusCastbarCB", panel,
		"InterfaceOptionsCheckButtonTemplate");
	getglobal(cbHideFocusCastbar:GetName() .. "Text"):SetText("隐藏焦点施法条");
	cbHideFocusCastbar:SetScript("OnClick", function(self)
		if characterSettings then
			UnitFramesImproved_SetSetting("HideFocusCastbar", self:GetChecked() and true or false);
			UnitFramesImproved_ApplyCastbarVisibility();
		end
	end);

	-- Health bar class colors.
	-- Profile settings.
 local cbClassHealth = CreateFrame("CheckButton", "UFI_ClassHealthColors", panel, "InterfaceOptionsCheckButtonTemplate")
 _G[cbClassHealth:GetName() .. "Text"]:SetText("头像血条使用职业颜色")
 cbClassHealth:SetScript("OnClick", function(self)
  UnitFramesImproved_SetSetting("HealthBarClassColor", self:GetChecked() and true or false)
  -- Let the engine repaint first when disabling, then refresh our optional overlay colour.
  for _, entry in ipairs({{PlayerFrameHealthBar,"player"},{TargetFrameHealthBar,"target"},{FocusFrameHealthBar,"focus"}}) do
   if entry[1] and UnitFrameHealthBar_Update then UnitFrameHealthBar_Update(entry[1],entry[2]) end
  end
  if UFI_ClassHealthColors_Refresh then UFI_ClassHealthColors_Refresh() end
 end)
 cbClassHealth:HookScript("OnShow",function(self) self:SetChecked(characterSettings and characterSettings.HealthBarClassColor ~= false) end)

	-- Profiles.
	local profileTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	profileTitle:SetText("配置文件");

	local profileLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	profileLabel:SetText("当前:");

	local profileButton = CreateFrame("Button", "UFI_ProfileCycleButton", panel, "UIPanelButtonTemplate");
	profileButton:SetSize(90, 16);
	profileButton:SetText("Default");

	local deleteProfileButton = CreateFrame("Button", "UFI_DeleteProfileButton", panel, "UIPanelButtonTemplate");
	deleteProfileButton:SetSize(50, 16);
	deleteProfileButton:SetText("删除");

	-- Compact new profile row
	local profileNameLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	profileNameLabel:SetText("新建:");

	local profileNameEdit = CreateFrame("EditBox", "UFI_NewProfileNameEdit", panel, "InputBoxTemplate");
	profileNameEdit:SetSize(90, 16);
	profileNameEdit:SetAutoFocus(false);

	local createProfileButton;
	profileNameEdit:SetScript("OnEnterPressed", function(self)
		createProfileButton:Click();
		self:ClearFocus();
	end);

	createProfileButton = CreateFrame("Button", "UFI_CreateProfileButton", panel, "UIPanelButtonTemplate");
	createProfileButton:SetSize(40, 16);
	createProfileButton:SetText("保存");

	-- Wire the profile buttons (same logic as before, just more compact controls)
	profileButton:SetScript("OnClick", function()
		local names = UnitFramesImproved_GetProfileNames();
		if #names == 0 then return end
		local cur = UnitFramesImproved_GetActiveProfileName();
		local idx = 1;
		for i, n in ipairs(names) do
			if n == cur then
				idx = i; break;
			end
		end
		idx = (idx % #names) + 1;
		local nextName = names[idx];
		UnitFramesImproved_SwitchToProfile(nextName);
		profileButton:SetText(nextName);
		if panel:GetScript("OnShow") then
			panel:GetScript("OnShow")(panel);
		end
	end);

	createProfileButton:SetScript("OnClick", function()
		local name = profileNameEdit:GetText() or "";
		name = string.gsub(name, "^%s*(.-)%s*$", "%1");
		if name == "" then name = "New Profile"; end
		local createdName = UnitFramesImproved_CreateNewProfile(name);
		profileButton:SetText(createdName);
		profileNameEdit:SetText("");
		if panel:GetScript("OnShow") then
			panel:GetScript("OnShow")(panel);
		end
	end);

	deleteProfileButton:SetScript("OnClick", function()
		local cur = UnitFramesImproved_GetActiveProfileName();
		if UnitFramesImproved_DeleteProfile(cur) then
			local newActive = UnitFramesImproved_GetActiveProfileName();
			profileButton:SetText(newActive);
			if panel:GetScript("OnShow") then
				panel:GetScript("OnShow")(panel);
			end
		end
	end);

	-- Load current values when panel is shown
	panel:SetScript("OnShow", function(self)
		-- Profile (must be loaded first)
		local profName = UnitFramesImproved_GetActiveProfileName();
		profileButton:SetText(profName);

		local scale = tonumber(characterSettings and characterSettings["FrameScale"] or 1.0) or 1.0;
		scaleSlider:SetValue(scale);

		-- Checkboxes
		cbPlayer:SetChecked(characterSettings and characterSettings["EnablePlayer"] ~= false);
		cbTarget:SetChecked(characterSettings and characterSettings["EnableTarget"] ~= false);
		cbFocus:SetChecked(characterSettings and characterSettings["EnableFocus"] ~= false);
		cbBoss:SetChecked(characterSettings and characterSettings["EnableBoss"] ~= false);
		cbDragon:SetChecked(characterSettings and characterSettings["FollowPortraitDragon"] ~= false);

		-- Load player frame border style (only for player)
		local pstyleKey = characterSettings and characterSettings["PlayerFrameStyle"] or "regular";
		local pstyleName = "普通";
		for _, s in ipairs(UnitFramesImproved.playerFrameStyles or {}) do
			if s.key == pstyleKey then
				pstyleName = s.name;
				break;
			end
		end
		playerBorderButton:SetText(pstyleName);
		playerBorderDisplay:SetText(pstyleKey);

		-- Load player/target color tint button (separate setting: silver=original, class, black)
		local ptcolor = characterSettings and characterSettings["PlayerTargetFrameColor"] or "silver";
		local labels = { silver = "银色 (原始)", class = "职业颜色", black = "黑色" };
		ptColorButton:SetText(labels[ptcolor] or "银色 (原始)");

		-- Load bar texture for player/target (SharedMedia statusbars)
		local bt = characterSettings and characterSettings["BarTexture"] or "Default";
		barTextureButton:SetText(bt);
		if bt == "Default" then
			local hasLSM = LibStub and LibStub("LibSharedMedia-3.0", true)
			barTextureDisplay:SetText(hasLSM and "(默认)" or "(SharedMedia 未安装)");
		else
			barTextureDisplay:SetText("");
		end

		-- Load target castbar hide checkbox
		cbHideCastbar:SetChecked(characterSettings and characterSettings["HideTargetCastbar"]);

		-- Load focus castbar hide checkbox
		cbHideFocusCastbar:SetChecked(characterSettings and characterSettings["HideFocusCastbar"]);
        cbClassHealth:SetChecked(characterSettings and characterSettings.HealthBarClassColor ~= false);

		-- Force positions when the panel is shown (explains why "going into options" fixes it for the user).
		-- This ensures the layout matches the profile even if a recent teleport or other event moved things.
		UnitFramesImproved_ApplyFramePositions()
	end);

	-- Keep layout in one place. Pages prevent long labels from colliding with
	-- unrelated controls and fit the original 3.3.5 Interface Options category.
	local pages, tabs = {}, {};
	local function Place(widget, page, x, y, width, height)
		widget:SetParent(page);
		widget:ClearAllPoints();
		widget:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y);
		if width then widget:SetWidth(width); end
		if height then widget:SetHeight(height); end
	end
	local function Label(widget, page, x, y, width, height)
		Place(widget, page, x, y, width, height);
		widget:SetJustifyH("LEFT");
		widget:SetJustifyV("TOP");
	end
	local function SelectPage(index)
		for i, page in ipairs(pages) do
			if i == index then page:Show(); tabs[i]:Disable();
			else page:Hide(); tabs[i]:Enable(); end
		end
	end
	for i, caption in ipairs({ "基础设置", "外观与显示", "配置文件" }) do
		local page = CreateFrame("Frame", nil, panel);
		page:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -112);
		page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16);
		pages[i] = page;
		local tab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
		tab:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (i - 1) * 144, -72);
		tab:SetSize(136, 24);
		tab:SetText(caption);
		local pageIndex = i;
		tab:SetScript("OnClick", function() SelectPage(pageIndex); end);
		tabs[i] = tab;
	end

	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16);
	desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42);
	desc:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -42);
	desc:SetHeight(26);
	desc:SetJustifyH("LEFT");
	desc:SetJustifyV("TOP");
	desc:SetText("按分类调整框架、外观和配置文件。修改会立即生效。");

	local basic, appearance, profiles = pages[1], pages[2], pages[3];
	Label(scaleTitle, basic, 0, 0, 460, 18);
	Place(scaleSlider, basic, 8, 40, 300);
	scaleText:SetText("全局缩放");
	Label(framesTitle, basic, 0, 98, 460, 18);
	Label(note, basic, 0, 122, 480, 34);
	note:SetText("玩家、目标使用宽血条；\nBoss 缩放为全局缩放的 90%。");
	Place(cbPlayer, basic, 0, 168);
	Place(cbTarget, basic, 0, 204);
	Place(cbFocus, basic, 0, 240);
	Place(cbBoss, basic, 240, 168);

	Label(playerBorderTitle, appearance, 0, 0, 460, 18);
	playerBorderTitle:SetText("边框与条材质");
	Label(playerBorderNote, appearance, 0, 24, 480, 30);
	playerBorderNote:SetText("边框样式仅用于玩家；边框着色用于玩家、目标和焦点。\n条材质用于玩家和目标。");
	Label(playerBorderLabel, appearance, 0, 68, 140, 18);
	playerBorderLabel:SetText("玩家边框样式：");
	Place(playerBorderButton, appearance, 148, 64, 180, 22);
	-- Internal style keys (e.g. silver) are not useful settings labels.
	Place(playerBorderDisplay, appearance, 340, 68, 120, 18);
	playerBorderDisplay:Hide();
	Place(cbDragon, appearance, 0, 96);
	Label(ptColorLabel, appearance, 0, 136, 140, 18);
	ptColorLabel:SetText("边框着色：");
	Place(ptColorButton, appearance, 148, 132, 180, 22);
	Label(barTextureLabel, appearance, 0, 172, 140, 18);
	barTextureLabel:SetText("血蓝条材质：");
	Place(barTextureButton, appearance, 148, 168, 180, 22);
	Label(barTextureDisplay, appearance, 148, 196, 300, 20);
	local visibilityTitle = appearance:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	Label(visibilityTitle, appearance, 0, 232, 460, 18);
	visibilityTitle:SetText("施法条与血条颜色");
	Place(cbHideCastbar, appearance, 0, 258);
	Place(cbHideFocusCastbar, appearance, 240, 258);
	Place(cbClassHealth, appearance, 0, 298);

	Label(profileTitle, profiles, 0, 0, 460, 18);
	Label(profileLabel, profiles, 0, 36, 140, 18);
	profileLabel:SetText("当前配置：");
	Place(profileButton, profiles, 148, 32, 220, 22);
	Place(deleteProfileButton, profiles, 380, 32, 64, 22);
	Label(profileNameLabel, profiles, 0, 76, 140, 18);
	profileNameLabel:SetText("新建配置名称：");
	Place(profileNameEdit, profiles, 154, 72, 210, 22);
	Place(createProfileButton, profiles, 380, 72, 64, 22);
	profileNameEdit:SetMaxLetters(48);
	profileNameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);
	local profileHelp = profiles:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	Label(profileHelp, profiles, 0, 112, 480, 36);
	profileHelp:SetText("点击当前配置名称切换配置。\n输入新名称后点击保存，或按回车创建配置。");
	SelectPage(1);


	-- Register with Interface Options
	InterfaceOptions_AddCategory(panel);
end

-- Create the panel as soon as possible (so /ufi settings works)
-- pcall for extra safety across different classic client versions
pcall(UnitFramesImproved_CreateOptionsPanel);

-- Slashcommand stuff
-- SLASH_UNITFRAMESIMPROVED1 = "/unitframesimproved";
-- SLASH_UNITFRAMESIMPROVED2 = "/ufi";
-- SlashCmdList["UNITFRAMESIMPROVED"] = function(msg, editBox)
-- 	local tokens = tokenize(msg);
-- 	if(table.getn(tokens) > 0 and strlower(tokens[1]) == "reset") then
-- 		StaticPopup_Show("LAYOUT_RESET");
-- 	elseif(table.getn(tokens) > 0 and strlower(tokens[1]) == "settings") then
-- 		if UnitFramesImproved.panelSettings then
-- 			InterfaceOptionsFrame_OpenToCategory(UnitFramesImproved.panelSettings);
-- 		else
-- 			dout("UnitFramesImproved 设置面板不可用。");
-- 		end
-- 	elseif(table.getn(tokens) > 0 and strlower(tokens[1]) == "scale") then
-- 		if(table.getn(tokens) > 1) then
-- 			UnitFramesImproved_SetFrameScale(tokens[2]);
-- 		else
-- 			dout("请提供一个数字作为第二个参数，范围 0.0 到 10.0。");
-- 		end
-- 	else
-- 		dout("UnitFramesImproved 可用命令:");
-- 		dout("    help      (显示此帮助信息)");
-- 		dout("    scale #   (缩放玩家框架，例如 /ufi scale 1.2)");
-- 		dout("    settings  (打开设置面板)");
-- 		dout("    reset     (重置布局/缩放为默认值)");
-- 		dout("");
-- 		dout("使用设置面板调整大小和启用的框架类型。");
-- 	end
-- end

-- Setup the static popup dialog for resetting the UI
StaticPopupDialogs["LAYOUT_RESET"] = {
	text = "确定要重置缩放吗？",
	button1 = "是",
	button2 = "否",
	OnAccept = function()
		UnitFramesImproved_LoadDefaultSettings(true);
		UnitFramesImproved_ApplySettings(characterSettings);
		EnableUnitFramesImproved();
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true
}

StaticPopupDialogs["LAYOUT_RESETDEFAULT"] = {
	text = "为使 UnitFramesImproved 正常工作，\n需要重置旧的布局设置。\n这将重新加载你的界面。",
	button1 = "重置",
	button2 = "忽略",
	OnAccept = function()
		PlayerFrame:SetUserPlaced(false);
		ReloadUI();
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true
}

function UnitFramesImproved_TextStatusBar_UpdateTextString(textStatusBar)
    -- Only format our two main unit frames. Native ToT/focus/party bars are untouched.
    if not textStatusBar or not characterSettings then return end
    local playerBar = textStatusBar == PlayerFrameHealthBar or textStatusBar == PlayerFrameManaBar
    local targetBar = textStatusBar == TargetFrameHealthBar or textStatusBar == TargetFrameManaBar
    if not playerBar and not targetBar then return end
    if playerBar and characterSettings.EnablePlayer == false then return end
    if targetBar and characterSettings.EnableTarget == false then return end
	local textString = textStatusBar.TextString;
	if (textString) then
		-- Re-apply custom bar texture (SharedMedia) if set for player/target (in case Blizzard resets it)
		if characterSettings and characterSettings["BarTexture"] and characterSettings["BarTexture"] ~= "Default" then
			UnitFramesImproved_ApplyBarTextures();
		end

		local value = textStatusBar:GetValue();
		local valueMin, valueMax = textStatusBar:GetMinMaxValues();

		if ((tonumber(valueMax) ~= valueMax or valueMax > 0) and not (textStatusBar.pauseUpdates)) then

			if (value and valueMax > 0 and (GetCVarBool("statusTextPercentage") or textStatusBar.showPercentage) and not textStatusBar.showNumeric) then
				if (value == 0 and textStatusBar.zeroText) then
					textString:SetText(textStatusBar.zeroText);
					textStatusBar.isZero = 1;
					textString:Show();
					return;
				end
				value = tostring(math.ceil((value / valueMax) * 100)) .. "%";
				if (textStatusBar.prefix and (textStatusBar.alwaysPrefix or not (textStatusBar.cvar and GetCVar(textStatusBar.cvar) == "1" and textStatusBar.textLockable))) then
					textString:SetText(textStatusBar.prefix ..
					" " .. UnitFramesImproved_CapDisplayOfNumericValue(textStatusBar:GetValue()) .. " (" .. value .. ")");
				else
					textString:SetText(UnitFramesImproved_CapDisplayOfNumericValue(textStatusBar:GetValue()) ..
					" (" .. value .. ")");
				end
			elseif (value == 0 and textStatusBar.zeroText) then
				textString:SetText(textStatusBar.zeroText);
				textStatusBar.isZero = 1;
				textString:Show();
				return;
			else
				textStatusBar.isZero = nil;
				--local percent = tostring(math.ceil((value / valueMax) * 100)) .. "%";
				if (textStatusBar.capNumericDisplay) then
					value = UnitFramesImproved_CapDisplayOfNumericValue(value);
					valueMax = UnitFramesImproved_CapDisplayOfNumericValue(valueMax);
				end
				if (textStatusBar.prefix and (textStatusBar.alwaysPrefix or not (textStatusBar.cvar and GetCVar(textStatusBar.cvar) == "1" and textStatusBar.textLockable))) then
					textString:SetText(textStatusBar.prefix .. " " .. value .. "/" .. valueMax);
				else
					textString:SetText(value .. "/" .. valueMax);
				end
			end

			if ((textStatusBar.cvar and GetCVar(textStatusBar.cvar) == "1" and textStatusBar.textLockable) or textStatusBar.forceShow) then
				textString:Show();
			elseif ((textStatusBar.lockShow or 0) > 0 and (not textStatusBar.forceHideText)) then
				textString:Show();
			else
				textString:Hide();
			end
		else
			textString:Hide();
			textString:SetText("");
            -- The engine owns bar visibility and values; only change the text here.
		end
	end

	-- Update projected heal/absorb overlays for player and target health bars (live)
	if textStatusBar == PlayerFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	elseif textStatusBar == TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved_PlayerFrame_ToPlayerArt(self)
	-- 还原流程中（_restoring）或玩家样式已被禁用时，不再重新套样式
	if UnitFramesImproved._restoring then return end
	if characterSettings and characterSettings["EnablePlayer"] == false then return end
	if not InCombatLockdown() then
		UnitFramesImproved_Style_PlayerFrame();
	end
end

function UnitFramesImproved_PlayerFrame_ToVehicleArt(self)
	if not InCombatLockdown() then
		PlayerFrameHealthBar:SetHeight(12);
		PlayerFrameHealthBarText:SetPoint("CENTER", 50, 3);
	end
end

function UnitFramesImproved_TargetFrame_Update(self)
 if not self then return end
 UnitFramesImproved_HideNameBackgrounds(self)
	-- Allow status bar color updates even during combat; do not early-return on InCombatLockdown.
	-- 血条颜色完全交给引擎的插值逻辑（随血量绿→红、被攻击变灰），
	-- 这里不再 SetStatusBarColor —— 强制填充颜色会与引擎自绘层出现两种颜色。

	-- Update projected heals/absorbs (only for main target)
	if self.healthbar and self.unit == "target" then
		UnitFramesImproved_UpdateHealPrediction(self.healthbar, self.unit)
	end


end

function UnitFramesImproved_TargetFrame_CheckClassification(self, forceNormalTexture)
 if not UFI_FrameEnabled(self) or not self.borderTexture or not self.unit then return end
	-- 还原流程中（引擎重置边框纹理时）不重挂 UFI 纹理
	if UnitFramesImproved._restoring then return end
	-- Allow classification texture updates during combat; avoid returning early on InCombatLockdown.
	local texture;
	local classification = UnitClassification(self.unit);
	if (classification == "worldboss" or classification == "elite") then
		texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite";
	elseif (classification == "rareelite") then
		texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite";
	elseif (classification == "rare") then
		texture = "Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare";
	end
	if (texture and not forceNormalTexture) then
		self.borderTexture:SetTexture(texture);
	else
		self.borderTexture:SetTexture("Interface\\Addons\\UnitFramesImproved\\Textures\\UI-TargetingFrame");
	end

	-- Apply the player/target frame color tint (class/black) on top of whatever border we just chose.
	-- This only affects player/target/focus borders, separate from party tint.
	if self.borderTexture then
		UnitFramesImproved_ApplyPlayerTargetTint(self.borderTexture, self.unit);
	end
end

function UnitFramesImproved_TargetFrame_CheckFaction(self)
 UnitFramesImproved_HideNameBackgrounds(self)
 if UnitFramesImproved._restoring or not UFI_FrameEnabled(self) or not self.pvpIcon or not self.unit then return end
	if InCombatLockdown() then return end
	local factionGroup = UnitFactionGroup(self.unit);
	if not UnitIsPlayer(self.unit) then
		self.pvpIcon:Hide();
		return;
	end
	if (UnitIsPVPFreeForAll(self.unit)) then
		self.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA");
		self.pvpIcon:Show();
	elseif (factionGroup and UnitIsPVP(self.unit) and UnitIsEnemy("player", self.unit)) then
		self.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA");
		self.pvpIcon:Show();
	elseif (factionGroup) then
		self.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. factionGroup);
		self.pvpIcon:Show();
	else
		self.pvpIcon:Hide();
	end
end

-- Utility functions
function UnitColor(unit)
	local r, g, b;
	if ((not UnitIsPlayer(unit)) and ((not UnitIsConnected(unit)) or (UnitIsDeadOrGhost(unit)))) then
		--Color it gray
		r, g, b = 0.5, 0.5, 0.5;
	elseif (UnitIsPlayer(unit)) then
		--Try to color it by class.
		local localizedClass, englishClass = UnitClass(unit);
		local classColor = RAID_CLASS_COLORS[englishClass];
		if (classColor) then
			r, g, b = classColor.r, classColor.g, classColor.b;
		else
			if (UnitIsFriend("player", unit)) then
				r, g, b = 0.0, 1.0, 0.0;
			else
				r, g, b = 1.0, 0.0, 0.0;
			end
		end
	else
		r, g, b = UnitSelectionColor(unit);
	end

	return r, g, b;
end

function UnitFramesImproved_CapDisplayOfNumericValue(value)
	local strLen = strlen(value);
	local retString = value;
	if (true) then
		if (strLen >= 10) then
			retString = string.sub(value, 1, -10) .. "." .. string.sub(value, -9, -9) .. "G";
		elseif (strLen >= 7) then
			retString = string.sub(value, 1, -7) .. "." .. string.sub(value, -6, -6) .. "M";
		elseif (strLen >= 4) then
			retString = string.sub(value, 1, -4) .. "." .. string.sub(value, -3, -3) .. "k";
		end
	else
		if (strLen >= 10) then
			retString = string.sub(value, 1, -10) .. "G";
		elseif (strLen >= 7) then
			retString = string.sub(value, 1, -7) .. "M";
		elseif (strLen >= 4) then
			retString = string.sub(value, 1, -4) .. "k";
		end
	end
	return retString;
end

-- Bootstrap
function UnitFramesImproved_StartUp(self)
	self:SetScript('OnEvent', function(self, event, ...)
		if self[event] then
			self[event](self, ...)
		end
	end);
	self:RegisterEvent('PLAYER_ENTERING_WORLD');
	self:RegisterEvent('VARIABLES_LOADED');
	self:RegisterEvent('UNIT_HEALTH');
	self:RegisterEvent('UNIT_MAXHEALTH');
	self:RegisterEvent('UNIT_SPELLCAST_SENT');
	self:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED');
	self:RegisterEvent('UNIT_SPELLCAST_STOP');
	self:RegisterEvent('UNIT_SPELLCAST_FAILED');

	-- Additional events for reliable repositioning after teleports/zone changes
	self:RegisterEvent('ZONE_CHANGED_NEW_AREA');
	self:RegisterEvent('ZONE_CHANGED');
	self:RegisterEvent('ZONE_CHANGED_INDOORS');
	self:RegisterEvent('PLAYER_TARGET_CHANGED'); -- helps force position when target appears or changes post-teleport
	self:RegisterEvent('UNIT_FACTION'); -- update target color when ownership changes (tapped by other player)
	self:RegisterEvent('PLAYER_REGEN_ENABLED');
	self:RegisterEvent('PLAYER_REGEN_DISABLED');
	self:RegisterEvent('CVAR_UPDATE');  -- 游戏内"头像龙框"开关变化时重画玩家框

	-- 持续位置看护：每 0.5s 检查一次，仅当框架被引擎布局移走时才恢复保存的位置
	-- （LoadFramePosition 内部"位置已正确即跳过"，正常时为零操作）。
	-- 旧版"只监控一段时间就放弃"的做法，会让引擎的晚期布局在监控窗口结束后
	-- 把头像拉回默认位置 —— 表现为登陆后飘动数次、最后停在偏上的默认位置。
	-- 治疗预言的 0.1s 轮询已随预测条一起移除。
	-- !! 关键：此 Frame 从未 Show 过 —— 隐藏帧的 OnUpdate 不会运行，
	-- 之前的位置看护因此从未生效，登录后引擎 C++ 按 layout-local.txt 恢复的
	-- 位置（靠上）就成了最终位置（表现为：头像上下飘动数次后停在偏上位置）。
	-- Show() 一个无贴图的 Frame 不可见，但 OnUpdate 开始正常调度。
	self:Show();
	self:SetScript("OnUpdate", function(self, elapsed)
		self._monitorElapsed = (self._monitorElapsed or 0) + elapsed
		if self._monitorElapsed >= 0.2 then
			self._monitorElapsed = 0
			if not InCombatLockdown() then
                if characterSettings then
                    UnitFramesImproved_HideNameBackgrounds(PlayerFrame)
                    UnitFramesImproved_HideNameBackgrounds(TargetFrame)
                    UnitFramesImproved_ApplyFramePositions()
                    UnitFramesImproved_ApplyTargetFramePosition()
                end
			end
		end

		-- 安全时机执行TargetFrame位置设置（避免在secure hook中操作锚点导致污染）
		UnitFramesImproved_ExecuteTargetFramePosition()
	end)
end

UnitFramesImproved_StartUp(UnitFramesImproved);

-- 注意：本文件早期曾在此处重复定义 UnitFramesImproved:PLAYER_ENTERING_WORLD（只做位置校正），
-- 后者覆盖了上方第 54 行的完整登录初始化（加载档案 + EnableUnitFramesImproved），
-- 导致刚进游戏不套任何样式（窄血条），必须打开设置面板点复选框才生效 —— 已删除重复定义。


function UnitFramesImproved:PLAYER_REGEN_DISABLED()
 for _, frame in ipairs({PlayerFrame, TargetFrame, FocusFrame}) do
  if frame._isDragging then
   frame._isDragging = nil
   frame._ufiStopDragAfterCombat = true
  end
 end
end

function UnitFramesImproved:PLAYER_REGEN_ENABLED()
 for _, entry in ipairs({{PlayerFrame, "PlayerFrame"}, {TargetFrame, "TargetFrame"}, {FocusFrame, "FocusFrame"}}) do
  local frame, key = entry[1], entry[2]
  if frame and frame._ufiStopDragAfterCombat then
   frame._ufiStopDragAfterCombat = nil
   frame:StopMovingOrSizing()
   frame:SetUserPlaced(true)
   UnitFramesImproved_SaveFramePosition(frame, key)
  end
 end
 if self._pendingApplySettings then UnitFramesImproved_ApplySettings(characterSettings) end
 if self._pendingEnable then EnableUnitFramesImproved() end
 if self._pendingCastbarVisibility then UnitFramesImproved_ApplyCastbarVisibility() end
 UnitFramesImproved_ApplyFramePositions()
 UnitFramesImproved_ApplyTargetFramePosition()
 UnitFramesImproved_ExecuteTargetFramePosition()
end

function UnitFramesImproved:UNIT_HEALTH()
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved:UNIT_FACTION(unit)
	if unit and (unit == "target" or unit == "focus") then
		local frame = (unit == "target") and TargetFrame or FocusFrame
		if frame and frame.healthbar then
			UnitFramesImproved_TargetFrame_Update(frame)
		end
	end
end

-- 游戏内"头像龙框"开关变化时（showPortraitDragon）立即重画玩家框
function UnitFramesImproved:CVAR_UPDATE(cvar, value)
	if cvar ~= "showPortraitDragon" then return end
	if characterSettings and characterSettings["EnablePlayer"] == false then return end
	UnitFramesImproved_Style_PlayerFrame()
end

function UnitFramesImproved:UNIT_MAXHEALTH()
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved:UNIT_SPELLCAST_SENT(unit, spellName, rank, target)
	-- Force prediction update as soon as a cast is sent (so green bar shows during the cast / in-flight)
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved:UNIT_SPELLCAST_SUCCEEDED(unit, spellName, rank, target)
	-- Force again on success (prediction should be active here)
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved:UNIT_SPELLCAST_STOP(unit, spellName, rank, target)
	-- Update on stop (catches cancels or end of channel)
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

function UnitFramesImproved:UNIT_SPELLCAST_FAILED(unit, spellName, rank, target)
	-- Clear prediction on fail
	UnitFramesImproved_UpdateHealPrediction(PlayerFrameHealthBar, "player")
	if TargetFrameHealthBar then
		UnitFramesImproved_UpdateHealPrediction(TargetFrameHealthBar, "target")
	end
end

-- Table Dump Functions -- http://lua-users.org/wiki/TableSerialization
function print_r(t, indent, done)
	done = done or {}
	indent = indent or ''
	local nextIndent -- Storage for next indentation value
	for key, value in pairs(t) do
		if type(value) == "table" and not done[value] then
			nextIndent = nextIndent or
				(indent .. string.rep(' ', string.len(tostring(key)) + 2))
			-- Shortcut conditional allocation
			done[value] = true
			print(indent .. "[" .. tostring(key) .. "] => Table {");
			print(nextIndent .. "{");
			print_r(value, nextIndent .. string.rep(' ', 2), done)
			print(nextIndent .. "}");
		else
			print(indent .. "[" .. tostring(key) .. "] => " .. tostring(value) .. "")
		end
	end
end

-- Portraits are managed by the game or CoAPortrait.
