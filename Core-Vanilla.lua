local RepByZone = LibStub("AceAddon-3.0"):NewAddon("RepByZone", "AceEvent-3.0", "LibAboutPanel-2.0", "AceConsole-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("RepByZone")
local Dialog = LibStub("AceConfigDialog-3.0")

-- Local variables
local db
local isOnTaxi
local instancesAndFactions
local zonesAndFactions
local subZonesAndFactions

-- Table to localize subzones that Blizzard does not provide areaIDs
local CitySubZonesAndFactions = CitySubZonesAndFactions or {
	-- ["Subzone"] = factionID
    ["Deeprun Tram"] = 72, -- Stormwind
	["Dwarven District"] = 47, -- Ironforge
	["The Salty Sailor Tavern"] = 21, -- Booty Bay
	["Tinker Town"] = 54, -- Gnomeregan Exiles
	["Valley of Spirits"] = 530, -- Darkspear Trolls
	["Valley of Wisdom"] = 81, -- Thunder Bluff
}

-- Get the character's racial factionID and factionName
function RepByZone:GetRacialRep()
     -- Catch possible errors during initialization
     local useClassRep
     if self.db == nil then
         useClassRep = true
     elseif self.db.profile.useClassRep == nil then
         useClassRep = true
     else
         useClassRep = self.db.profile.useClassRep
     end
     local whichID, whichName

    local _, playerRace = UnitRace("player")
    local racialRepID = playerRace == "Dwarf" and 47 -- Ironforge
    or playerRace == "Gnome" and 54 -- Gnomeregan
    or playerRace == "Human" and 72 -- Stormwind
    or playerRace == "NightElf" and 69 -- Darnassus
    or playerRace == "Orc" and 76 -- Orgrimmar
    or playerRace == "Tauren" and 81 -- Thunder Bluff
    or playerRace == "Troll" and 530 -- Darkspear Trolls
    or playerRace == "Scourge" and 68 -- Undercity

    -- Classes have factions
    local _, classFileName = UnitClass("player")
    local classRepID = classFileName == "ROGUE" and 349 -- Ravenholdt
    or classFileName == "DRUID" and 609 -- Cenarion Circle

    self:OpenAllFactionHeaders()

    -- Check if the player has discovered the race faction
    local function CheckRace()
        for i = 1, GetNumFactions() do
            local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if name and not isHeader then
                if factionID == racialRepID then
                    return factionID, name
                end
            end
        end
    end
    whichID, whichName = CheckRace()

    -- Check if the player has discoverd the class faction
    local function CheckClassRep()
        for i = 1, GetNumFactions() do
            local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if name and not isHeader then
                if factionID == classRepID then
                    return factionID, name
                end
            end
        end
    end
    if useClassRep then
        whichID, whichName = CheckClassRep()
    end

    if not whichID then
        whichID, whichName = CheckRace()
    end

    self:CloseAllFactionHeaders()

    self.racialRepID = useClassRep and classRepID or racialRepID
    self.racialRepName = GetFactionInfoByID(self.racialRepID)
    return whichID, whichName
end

-- Return a table of defaul SV values
local defaults = {
    profile = {
        enabled = true,
        watchSubZones = true,
        verbose = true,
        watchOnTaxi = true,
        useClassRep = true,
    }
}

function RepByZone:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("RepByZoneDB", defaults)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    db = self.db.profile
    
    self:SetEnabledState(db.enabled)

    local options = self:GetOptions() -- Options.lua
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

    -- Support for LibAboutPanel-2.0
    options.args.aboutTab = self:AboutOptionsTable("RepByZone")
    options.args.aboutTab.order = -1 -- -1 means "put it last"

    -- Register your options with AceConfigRegistry
    LibStub("AceConfig-3.0"):RegisterOptionsTable("RepByZone", options)

    -- Add options to Interface/AddOns
    self.optionsFrame = Dialog:AddToBlizOptions("RepByZone", "RepByZone")

    -- Create slash commands
    self:RegisterChatCommand("repbyzone", "SlashHandler")
    self:RegisterChatCommand("rbz", "SlashHandler")

    local defaultRepID, defaultRepName = self:GetRacialRep()
    db.watchedRepID = db.watchedRepID or defaultRepID
    db.watchedRepName = db.watchedRepName or defaultRepName
end

function RepByZone:OnEnable()
    -- Populate variables
    isOnTaxi = UnitOnTaxi("player")
    self:GetRacialRep()

    -- Cache instance, zone, and subzone data; factionIDs may not be available earlier in OnInitialize()?
    instancesAndFactions = instancesAndFactions or self:InstancesAndFactionList()
    zonesAndFactions = zonesAndFactions or self:ZoneAndFactionList()
    subZonesAndFactions = subZonesAndFactions or self:SubZonesAndFactions()

    -- All events that deal with entering a new zone or subzone are handled with the same function
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "SwitchedZones")
    self:RegisterEvent("ZONE_CHANGED", "SwitchedZones")
    self:RegisterEvent("ZONE_CHANGED_INDOORS", "SwitchedZones")

    -- If player is in combat, close options panel and exit out of command line
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "InCombat")

    -- If the player loses or gains control of the character, it is one of the signs of taxi use
    self:RegisterEvent("PLAYER_CONTROL_LOST", "CheckTaxi")
    self:RegisterEvent("PLAYER_CONTROL_GAINED", "CheckTaxi")

    -- Set watched faction when the player first loads into the game
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "LoginReload")
end

function RepByZone:OnDisable()
    -- Stop watching most events if RBZ is disabled
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UnregisterEvent("ZONE_CHANGED")
    self:UnregisterEvent("ZONE_CHANGED_INDOORS")
    self:UnregisterEvent("PLAYER_CONTROL_LOST")
    self:UnregisterEvent("PLAYER_CONTROL_GAINED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- Wipe variables when RBZ is disabled
    isOnTaxi = nil
end

function RepByZone:SlashHandler()
    -- Check if player is in combat, exit out and close options panels if that's the case
    self:InCombat()

    -- Close option panel if opened, otherwise open option panel
    if Dialog.OpenFrames["RepByZone"] then
        Dialog:Close("RepByZone")
    else
        Dialog:Open("RepByZone")
    end
end

function RepByZone:RefreshConfig(event, database, ...)
    db = self.db.profile
    db.watchedRepID, db.watchedRepName = self:GetRacialRep()
end

------------------- Event handlers starts here --------------------
function RepByZone:InCombat()
    if UnitAffectingCombat("player") then
        if Dialog.OpenFrames["RepByZone"] then
            Dialog:Close("RepByZone")
        end
        return
    end
end

function RepByZone:CheckTaxi()
    isOnTaxi = UnitOnTaxi("player")
end

function RepByZone:LoginReload(event, isInitialLogin, isReloadingUi)
    instancesAndFactions = instancesAndFactions or self:InstancesAndFactionList()
    zonesAndFactions = zonesAndFactions or self:ZoneAndFactionList()
    subZonesAndFactions = subZonesAndFactions or self:SubZonesAndFactions()

    self:GetRacialRep()
    self:SwitchedZones()
end

-------------------- Reputation code starts here --------------------
local repsCollapsed = {} -- Obey user's settings about headers opened or closed
-- Open all faction headers
function RepByZone:OpenAllFactionHeaders()
    local numFactions = GetNumFactions()
    local factionIndex = 1

	while factionIndex <= numFactions do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(factionIndex)
		if isHeader and isCollapsed then
            repsCollapsed[name] = repsCollapsed[name] or isCollapsed
            ExpandFactionHeader(factionIndex)
            numFactions = GetNumFactions()
        end
        factionIndex = factionIndex + 1
	end
end

-- Close all faction headers
function RepByZone:CloseAllFactionHeaders()
    local numFactions = GetNumFactions()
    local factionIndex = 1

	while factionIndex <= numFactions do
		local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(factionIndex)
		if isHeader then
			if isCollapsed and not repsCollapsed[name] then
				ExpandFactionHeader(factionIndex)
                numFactions = GetNumFactions()
			elseif repsCollapsed[name] and not isCollapsed then
				CollapseFactionHeader(factionIndex)
                numFactions = GetNumFactions()
			end
		end
        factionIndex = factionIndex + 1
	end
	wipe(repsCollapsed)
end

function RepByZone:GetAllFactions()
    -- Will not return factions the user has marked as inactive
    self:OpenAllFactionHeaders()
    local factionList = {}

    for factionIndex = 1, GetNumFactions() do
        local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(factionIndex)
        if name then
            if not isHeader and name ~= FACTION_INACTIVE then
                factionList[factionID] = name
            end
        end
    end
    factionList["0-none"] = NONE

    self:CloseAllFactionHeaders()
    return factionList
end

-------------------- Watched faction code starts here --------------------
-- Player switched zones, subzones, or instances, set watched faction
function RepByZone:SwitchedZones()
    local UImapID = C_Map.GetBestMapForUnit("player")
    if not UImapID then return end -- Possible zoning issues, exit out unless we have valid map data
    
    if isOnTaxi then
        if not db.watchOnTaxi then
            -- On taxi but don't switch
            return
        end
    end

    local faction, _, factionName, isWatched
    local inInstance = IsInInstance() and select(8, GetInstanceInfo())
    local subZone = GetMinimapZoneText()

    if inInstance then
        for instanceID, factionID in pairs(instancesAndFactions) do
            if instanceID == inInstance then
                faction = factionID
                break
            end
        end
    else
        -- Apply world zone data
        for zoneID, factionID in pairs(zonesAndFactions) do
            if zoneID == UImapID then
                faction = factionID
                break
            end
        end
    end

    if db.watchSubZones then
        -- Blizzard provided areaIDs
        for areaID, factionID in pairs(subZonesAndFactions) do
            if C_Map.GetAreaInfo(areaID) == subZone then
                faction = factionID
                break
            end
        end
        -- Our localized missing Blizzard areaIDs
        for areaName, factionID in pairs(CitySubZonesAndFactions) do
            if L[areaName] == subZone then
                faction = factionID
                break
            end
        end
    end

    if not faction then
        faction = (db.watchedRepID == nil and self.racialRepID ~= nil) or (self.racialRepID == nil and db.watchedRepID ~= nil)
    end

    -- Set the watched factionID
    if type(faction) == "number" then
        factionName, _, _, _, _, _, _, _, _, _, _, isWatched = GetFactionInfoByID(faction)

        if factionName and not isWatched then
            C_Reputation.SetWatchedFaction(faction)
            if db.verbose then
                self:Print(L["Now watching %s"]:format(factionName))
            end
        elseif db.watchedRepID == "0-none" then
            C_Reputation.SetWatchedFaction(0) -- Clear watched faction
        end
    end
end