-- Class colours for the native portrait health bars; never lock engine colours.
-- Fallback palette extracted from the client's SharedConstants.lua.
local fallback = {
 HUNTER = {0.67, 0.83, 0.45},
 WARLOCK = {0.58, 0.51, 0.79},
 PRIEST = {1.0, 1.0, 1.0},
 PALADIN = {0.96, 0.55, 0.73},
 MAGE = {0.41, 0.8, 0.94},
 ROGUE = {1.0, 0.96, 0.41},
 DRUID = {1.0, 0.49, 0.04},
 SHAMAN = {0.0, 0.44, 0.87},
 WARRIOR = {0.78, 0.61, 0.43},
 DEATHKNIGHT = {0.77, 0.12, 0.23},
 HERO = {1, 0.84, 0.14},
 BARBARIAN = {0.54, 0.20, 0.01},
 WITCHDOCTOR = {0.96, 0.00, 1.00},
 DEMONHUNTER = {0.46, 0.98, 0.00},
 WITCHHUNTER = {0.33, 0.20, 0.81},
 STORMBRINGER = {0.00, 0.49, 0.93},
 FLESHWARDEN = {0.99, 0.00, 0.02},
 GUARDIAN = {0.61, 0.58, 0.51},
 MONK = {1.00, 0.98, 0.70},
 SONOFARUGAL = {0.64, 0.00, 0.00},
 RANGER = {0.75, 0.94, 0.42},
 PROPHET = {0.42, 0.65, 0.00},
 PYROMANCER = {1.00, 0.38, 0.07},
 CULTIST = {0.61, 0.27, 0.95},
 NECROMANCER = {0.27, 0.86, 0.61},
 SUNCLERIC = {1.00, 0.70, 0.25},
 TINKER = {0.85, 0.85, 0.85},
 REAPER = {0.04, 0.53, 0.42},
 WILDWALKER = {0.89, 0.55, 0.35},
 STARCALLER = {0.56, 1.00, 1.00},
 SPIRITMAGE = {0.25, 0.78, 0.92},
 CHRONOMANCER = {1.00, 0.93, 0.29},
}
local aliases = {FELSWORN="DEMONHUNTER",TEMPLAR="MONK",BLOODMAGE="SONOFARUGAL",
 KNIGHTOFXOROTH="FLESHWARDEN",PRIMALIST="WILDWALKER",RUNEMASTER="SPIRITMAGE",VENOMANCER="PROPHET"}
local tracked = {}
local painting = false
local function RGB(c)
 if type(c) ~= "table" then return end
 if type(c.GetRGB) == "function" then return c:GetRGB() end
 return c.r or c[1], c.g or c[2], c.b or c[3]
end
local function Enabled(key)
 return characterSettings and characterSettings.HealthBarClassColor ~= false and characterSettings[key] ~= false
end
local function Paint(bar)
 local entry = tracked[bar]
 if painting or not entry or not Enabled(entry.key) then return end
 local unit = entry.frame.unit or entry.unit
 if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
 local r,g,b
 if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
  r,g,b = .5,.5,.5
 else
  local _, class = UnitClass(unit)
  if not class then return end
  local canonical = aliases[class] or class
  r,g,b = RGB(CUSTOM_CLASS_COLORS and (CUSTOM_CLASS_COLORS[class] or CUSTOM_CLASS_COLORS[canonical]))
  if not r or not g or not b then r,g,b = RGB(RAID_CLASS_COLORS and (RAID_CLASS_COLORS[class] or RAID_CLASS_COLORS[canonical])) end
  if not r or not g or not b then r,g,b = RGB(fallback[canonical]) end
 end
 if not r or not g or not b then return end
 painting = true
 local ok, err = pcall(bar.SetStatusBarColor, bar, r,g,b)
 painting = false
 if not ok and geterrorhandler then geterrorhandler()(err) end
end
local function Track(frame, unit, key, namedBar)
 if not frame then return end
 local bar = frame.healthbar or namedBar
 if not bar or type(bar.SetStatusBarColor) ~= "function" then return end
 if not tracked[bar] then
  tracked[bar] = {frame=frame,unit=unit,key=key}
  hooksecurefunc(bar, "SetStatusBarColor", function(self) Paint(self) end)
  if bar.HookScript then bar:HookScript("OnValueChanged", function(self) Paint(self) end) end
 end
 Paint(bar)
end
function UFI_ClassHealthColors_Refresh()
 Track(PlayerFrame,"player","EnablePlayer",PlayerFrameHealthBar)
 Track(TargetFrame,"target","EnableTarget",TargetFrameHealthBar)
 Track(FocusFrame,"focus","EnableFocus",FocusFrameHealthBar)
 for i=1,4 do
  Track(_G["Boss"..i.."TargetFrame"],"boss"..i,"EnableBoss")
 end
end
local events=CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED",
 "PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE","UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_CONNECTION","UNIT_FACTION"}) do
 events:RegisterEvent(event)
end
events:SetScript("OnEvent",function(self,event,unit)
 if string.sub(event,1,5)=="UNIT_" then
  for bar,entry in pairs(tracked) do if (entry.frame.unit or entry.unit)==unit then Paint(bar) end end
 else
  UFI_ClassHealthColors_Refresh()
 end
end)
