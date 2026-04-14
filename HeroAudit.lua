local mod = dmhub.GetModLoading()

--[[
    HeroAudit

    A Tools-menu popup that summarizes every player-assigned character's
    Builder-tab selection state (ancestry, culture, career, class, kits,
    complications, titles) in a horizontally-scrolling column layout.

    Each hero becomes a column. Columns are sorted alphabetically and laid
    out right-to-left so that "A" appears on the far right.

    Data is snapshotted when the window opens; close and re-open to refresh.
]]

local HeroAudit = {}

-- Substrings stripped from subclass names for display. Longer variants must
-- precede their shorter prefixes (e.g. "College of the " before "College of ").
local SUBCLASS_NAME_STRIP = {
    " Domain",
    "Disciple of the ",
    "College of the ",
    "College of ",
    "Circle of ",
}

--[[
    Color palette (matches TacPanel UI)
]]
local PANEL_BG   = "#0b0f0d"
local CARD_BG    = "#040807"
local GOLD       = "#966D4B"
local GOLD_LIGHT = "#C49A5A"
local GOLD_BORDER = "#5C3D10"
local CREAM      = "#FFFEF8"
local MUTED      = "#8A8474"
local WHITE      = "#FFFFFF"
local DARK_RED   = "#6B2020"
local MED_GREEN  = "#2D6A4F"

--[[
    Style table — attached once to the root dialog panel. No inline gui.Style{}.
]]
local heroAuditStyles = {
    {
        selectors = {"heroaudit-dialog"},
        width = 1100,
        height = 640,
        fontFace = "Berling",
        flow = "vertical",
        halign = "center",
        valign = "center",
        bgcolor = PANEL_BG,
    },
    {
        selectors = {"heroaudit-header"},
        width = "80%",
        height = 40,
        flow = "vertical",
        halign = "center",
        valign = "top",
    },
    {
        selectors = {"heroaudit-header-label"},
        width = "auto",
        height = 30,
        fontFace = "Berling",
        fontSize = 24,
        bold = true,
        color = GOLD,
        textAlignment = "center",
        halign = "center",
        valign = "top",
    },
    {
        selectors = {"heroaudit-empty"},
        width = "auto",
        height = "auto",
        fontFace = "Berling",
        fontSize = 18,
        color = MUTED,
        textAlignment = "center",
        halign = "center",
        valign = "center",
    },
    {
        selectors = {"heroaudit-cards"},
        flow = "vertical",
        width = "100%-32",
        height = "100%-60",
        halign = "center",
        valign = "top",
    },
    {
        selectors = {"heroaudit-card"},
        flow = "horizontal",
        width = "100%-36",
        height = "auto",
        halign = "left",
        valign = "top",
        bgimage = true,
        bgcolor = CARD_BG,
        border = {x1 = 1, x2 = 1, y1 = 1, y2 = 1},
        borderColor = GOLD_BORDER,
        vmargin = 4,
        hpad = 12,
        vpad = 10,
    },
    {
        selectors = {"heroaudit-info-col"},
        flow = "vertical",
        width = "100%-120",
        height = "auto",
        hmargin = 12,
        halign = "left",
        valign = "center",
    },
    {
        selectors = {"heroaudit-cardname"},
        width = "auto",
        height = "auto",
        fontFace = "Berling",
        fontSize = 18,
        bold = true,
        color = GOLD_LIGHT,
        textAlignment = "left",
        halign = "left",
        hmargin = 4,
    },
    {
        selectors = {"heroaudit-level"},
        width = "auto",
        height = "auto",
        fontFace = "Berling",
        fontSize = 14,
        color = CREAM,
        textAlignment = "left",
        halign = "left",
        valign = "bottom",
        hmargin = 4,
    },
    {
        selectors = {"heroaudit-name-row"},
        width = "auto",
        height = "auto",
        vmargin = 2,
        flow = "horizontal",
        halign = "left",
        valign = "bottom",
    },
    {
        selectors = {"heroaudit-detail-cols"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 2,
    },
    {
        selectors = {"heroaudit-detail-col"},
        width = "33%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"heroaudit-row"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        hmargin = 6,
        vmargin = 1,
    },
    {
        selectors = {"heroaudit-row-text"},
        width = "100%-24",
        height = "auto",
        fontFace = "Inter",
        fontSize = 14,
        color = CREAM,
        textAlignment = "left",
        halign = "left",
        valign = "center",
        textWrap = true,
    },
    {
        selectors = {"heroaudit-row-indicator"},
        width = 16,
        height = 16,
        halign = "left",
        valign = "top",
        bgimage = "drawsteel/StatBlockIcons/T_UI_ICON_FLAT_STATBLOCK_TRIGGER.png",
        bgcolor = DARK_RED,
        hmargin = 4,
    },
    {
        selectors = {"heroaudit-row-indicator", "complete"},
        bgimage = "icons/icon_common/icon_common_29.png",
        bgcolor = MED_GREEN,
    },
    {
        selectors = {"heroaudit-row-modicon"},
        width = 16,
        height = 16,
        halign = "left",
        valign = "top",
        hmargin = 4,
        bgimage = "game-icons/bookmarklet.png",
        bgcolor = MUTED,
    },
    {
        selectors = {"heroaudit-row-gearicon"},
        width = 16,
        height = 16,
        halign = "left",
        valign = "top",
        hmargin = 4,
        bgimage = "ui-icons/inventory.png",
        bgcolor = MUTED,
    },
    {
        selectors = {"heroaudit-names-list"},
        width = "100%-24",
        height = "auto",
        fontFace = "Inter",
        fontSize = 12,
        color = CREAM,
        textAlignment = "left",
        halign = "left",
        lmargin = 22,
        rmargin = 6,
        bmargin = 4,
        textWrap = true,
    },
    {
        selectors = {"heroaudit-builder-btn"},
        width = 18,
        height = 18,
        halign = "left",
        valign = "center",
        bgimage = "ui-icons/character-sheet.png",
        bgcolor = WHITE,
        cornerRadius = 3,
        hmargin = 4,
    },
    {
        selectors = {"heroaudit-builder-btn", "hover"},
        brightness = 1.3,
        transitionTime = 0.1,
    },
    {
        selectors = {"heroaudit-builder-btn", "press"},
        brightness = 0.8,
    },
}

--[[
    Data helpers
]]

--- Format a hero's level for display, handling the Level-1 encounter cases.
--- @param hero character The hero whose level to format.
--- @return string displayText Human-readable level text (e.g. "Level 3" or "Second Encounter").
function HeroAudit.FormatLevel(hero)
    local level = hero:CharacterLevel()
    if level == 1 then
        local extra = hero:ExtraLevelInfo()
        if type(extra) == "table" and type(extra.encounter) == "number" then
            local encounterNames = {
                "First Encounter",
                "Second Encounter",
                "Third Encounter",
                "Fourth Encounter",
            }
            return encounterNames[extra.encounter] or "Level 1"
        end
    end
    return "Level " .. tostring(level)
end

--- Collect every player-assigned hero token in the game, sorted A→Z.
--- @return table entries Array of { token=token, hero=character, name=string }, alphabetical.
function HeroAudit.CollectHeroes()
    local entries = {}
    local allTokens = table.values(game.GetGameGlobalCharacters())
    for _, token in ipairs(allTokens) do
        local owner = token.ownerId
        if owner and owner ~= "PARTY" and token.properties and token.properties:IsHero() then
            entries[#entries + 1] = {
                token = token,
                hero = token.properties,
                name = token.name or "Unknown",
            }
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return entries
end

--[[
    Per-category selection-status builders.

    Each builder mirrors the cache construction inside the Character Builder's
    MainPanel.lua so the X/Y counts match exactly. A nil featureCache produces
    a selection status whose GetStatusSummary() returns 0/1 when suppressRow1
    is false, which is exactly the "none chosen" fallback.
]]

--- Build the selection status for a hero's ancestry.
--- @param hero character The hero to audit.
--- @return CBSelectionStatus status Selection status with correct X/Y counts.
--- @return string displayName The ancestry name, or "none chosen".
function HeroAudit.BuildAncestryStatus(hero)
    local ancestryId = hero:try_get("raceid")
    local ancestryItem = ancestryId and dmhub.GetTableVisible(Race.tableName)[ancestryId]

    if ancestryItem == nil then
        local status = CBSelectionStatus.CreateNew{
            featureCache = nil,
            selectorName = "ancestry",
            visible = true,
            suppressRow1 = false,
            displayName = "Ancestry",
        }
        return status, "none chosen"
    end

    local levelChoices = hero:GetLevelChoices() or {}
    local featureDetails = {}
    ancestryItem:FillFeatureDetails(nil, levelChoices, featureDetails)

    local featureCache = CBFeatureCache.CreateNew(hero, ancestryId, ancestryItem.name, featureDetails)
    local status = CBSelectionStatus.CreateNew{
        featureCache = featureCache,
        selectorName = "ancestry",
        visible = true,
        suppressRow1 = false,
        displayName = "Ancestry",
    }
    return status, ancestryItem.name
end

--- Build the selection status for a hero's culture selections.
--- @param hero character The hero to audit.
--- @return CBSelectionStatus status Selection status with correct X/Y counts.
function HeroAudit.BuildCultureStatus(hero)
    local levelChoices = hero:GetLevelChoices() or {}

    local cultureFeatures = {}
    local cultureItem = hero:GetCulture()
    if cultureItem ~= nil then
        cultureItem:FillFeatureDetails(levelChoices, cultureFeatures)
    end

    local aspectFeatures = CharacterAspectChoice.CreateAll(hero)
    if aspectFeatures then
        cultureFeatures = table.append_arrays(aspectFeatures, cultureFeatures)
    end

    local cultureAggregates = CharacterCultureAggregateChoice.CreateAll(hero)
    if cultureAggregates then
        cultureFeatures = table.append_arrays(cultureAggregates, cultureFeatures)
    end

    local featureCache = CBFeatureCache.CreateNew(hero, "culture", "Culture", cultureFeatures)
    return CBSelectionStatus.CreateNew{
        featureCache = featureCache,
        selectorName = "culture",
        visible = true,
        suppressRow1 = true,
        displayName = "Culture",
    }
end

--- Build the selection status for a hero's career (background).
--- Replicates the inciting-incident special case from MainPanel.selectCareer.
--- @param hero character The hero to audit.
--- @return CBSelectionStatus status Selection status with correct X/Y counts.
--- @return string displayName The career name, or "none chosen".
function HeroAudit.BuildCareerStatus(hero)
    local careerId = hero:try_get("backgroundid")
    local careerItem = careerId and dmhub.GetTableVisible(Background.tableName)[careerId]

    if careerItem == nil then
        local status = CBSelectionStatus.CreateNew{
            featureCache = nil,
            selectorName = "career",
            visible = true,
            suppressRow1 = false,
            displayName = "Career",
        }
        return status, "none chosen"
    end

    local levelChoices = hero:GetLevelChoices() or {}
    local featureDetails = {}
    careerItem:FillFeatureDetails(levelChoices, featureDetails)

    -- Special case: inciting incidents behave like feature choices.
    for _, item in ipairs(careerItem:try_get("characteristics", {})) do
        local feature = CharacterIncidentChoice.CreateNew(item)
        if feature then
            featureDetails[#featureDetails + 1] = {
                feature = feature,
                background = careerItem,
            }
            local levelChoice = {}
            local notes = hero:GetNotesForTable(feature.guid)
            if notes and #notes > 0 then
                for _, note in ipairs(notes) do
                    levelChoice[#levelChoice + 1] = note.rowid
                end
            end
            levelChoices[feature.guid] = levelChoice
        end
    end

    local featureCache = CBFeatureCache.CreateNew(hero, careerId, careerItem.name, featureDetails)
    local status = CBSelectionStatus.CreateNew{
        featureCache = featureCache,
        selectorName = "career",
        visible = true,
        suppressRow1 = false,
        displayName = "Career",
    }
    return status, careerItem.name
end

--- Build the selection status for a hero's class (and its subclasses).
--- Replicates the base-characteristic and subclass handling from MainPanel.selectClass.
--- @param hero character The hero to audit.
--- @return CBSelectionStatus status Selection status with correct X/Y counts.
--- @return string displayName The class name, or "none chosen".
function HeroAudit.BuildClassStatus(hero)
    local classItem = hero:GetClass()
    if classItem == nil then
        local status = CBSelectionStatus.CreateNew{
            featureCache = nil,
            selectorName = "class",
            visible = true,
            suppressRow1 = false,
            displayName = "Class",
        }
        return status, "none chosen"
    end

    local classId = classItem.id
    local levelChoices = hero:GetLevelChoices() or {}
    local extraLevelInfo = hero:ExtraLevelInfo()
    local classAndSubClasses = hero:GetClassesAndSubClasses() or {}

    local classFill = {}

    -- Special case: base characteristics behave like a feature choice.
    local charFeature = CharacterCharacteristicChoice.CreateNew(classItem)
    if charFeature then
        classFill[#classFill + 1] = {
            feature = charFeature,
            class = classItem,
        }
    end

    if #classAndSubClasses > 0 then
        for i, entry in ipairs(classAndSubClasses) do
            entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, extraLevelInfo, i ~= 1, classFill)
        end
    else
        classItem:FillFeatureDetailsForLevel(levelChoices, 1, extraLevelInfo, "nonprimary", classFill)
    end

    local featureCache = CBFeatureCache.CreateNew(hero, classId, classItem.name, classFill)
    local status = CBSelectionStatus.CreateNew{
        featureCache = featureCache,
        selectorName = "class",
        visible = true,
        suppressRow1 = false,
        displayName = "Class",
    }
    return status, classItem.name
end

--- Return the alphabetically-sorted names of every subclass currently
--- assigned to the hero. Uses the same primary-vs-subclass convention as
--- the Character Builder: entry 1 of GetClassesAndSubClasses is the primary
--- class, entries 2+ are subclasses.
--- @param hero character The hero to audit.
--- @return table names Array of subclass names; empty when the hero has no class or no subclasses.
function HeroAudit.GetSubclassNames(hero)
    local names = {}
    if hero:GetClass() == nil then return names end

    local entries = hero:GetClassesAndSubClasses() or {}
    for i, entry in ipairs(entries) do
        if i ~= 1 and entry.class then
            local cleaned = entry.class.name
            for _, pattern in ipairs(SUBCLASS_NAME_STRIP) do
                cleaned = string.gsub(cleaned, pattern, "")
            end
            names[#names + 1] = cleaned
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--- Return how many kits the hero's class grants and the names of any kits selected.
--- @param hero character The hero to audit.
--- @return number numKits Number of kit slots (0 when the class grants none or the hero cannot have kits).
--- @return table kitNames Array of kit names currently assigned; may be shorter than numKits when slots are empty.
function HeroAudit.GetKitInfo(hero)
    if not hero:CanHaveKits() then return 0, {} end

    local numKits = hero:GetNumberOfKits() or 0
    if numKits == 0 then return 0, {} end

    local kits = dmhub.GetTableVisible(Kit.tableName)
    local names = {}
    local kitid = hero:try_get("kitid")
    if kitid and kits[kitid] then
        names[#names + 1] = kits[kitid].name
    end
    local kitid2 = hero:try_get("kitid2")
    if kitid2 and kits[kitid2] then
        names[#names + 1] = kits[kitid2].name
    end
    return numKits, names
end

--- Look up display names for every value in a keyed "id → anything" table, sort A→Z.
--- @param ids table Keyed table whose keys are item GUIDs.
--- @param tableName string Name of the dmhub table to look items up in.
--- @return table names Alphabetically sorted array of display names.
function HeroAudit.ResolveNamesFromKeyedIds(ids, tableName)
    local items = dmhub.GetTableVisible(tableName)
    local names = {}
    for id, _ in pairs(ids) do
        local item = items[id]
        if item then
            names[#names + 1] = item.name
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--- Return the alphabetically-sorted names of every complication on the hero.
--- @param hero character The hero to audit.
--- @return table names Array of complication names, possibly empty.
function HeroAudit.GetComplicationNames(hero)
    return HeroAudit.ResolveNamesFromKeyedIds(
        hero:try_get("complications", {}),
        CharacterComplication.tableName
    )
end

--- Return the alphabetically-sorted names of every title on the hero.
--- @param hero character The hero to audit.
--- @return table names Array of title names, possibly empty.
function HeroAudit.GetTitleNames(hero)
    return HeroAudit.ResolveNamesFromKeyedIds(
        hero:try_get("titles", {}),
        Title.tableName
    )
end

--- Tally the hero's downtime projects by status bucket.
--- Buckets: complete (status COMPLETE), active (status ACTIVE), needAttention
--- (any other status — PAUSED, MILESTONE, or unknown).
--- @param hero character The hero to audit.
--- @return table counts `{ total, complete, active, needAttention }`.
function HeroAudit.GetDowntimeProjectCounts(hero)
    local counts = { total = 0, complete = 0, active = 0, needAttention = 0 }
    local dti = hero:GetDowntimeInfo()
    if dti == nil then return counts end

    local projects = dti:GetProjects()
    for _, project in pairs(projects or {}) do
        counts.total = counts.total + 1
        local status = project:GetStatus()
        if status == "COMPLETE" then
            counts.complete = counts.complete + 1
        elseif status == "ACTIVE" then
            counts.active = counts.active + 1
        else
            counts.needAttention = counts.needAttention + 1
        end
    end

    return counts
end

--- Return the alphabetically-sorted names of every selected culture aspect on
--- the hero. Aspects live on the culture object as `{ [category]=aspectId }`,
--- so unlike complications/titles the IDs are values rather than keys.
--- @param hero character The hero to audit.
--- @return table names Array of aspect names, possibly empty.
function HeroAudit.GetAspectNames(hero)
    local names = {}
    local culture = hero:GetCulture()
    if culture == nil then return names end

    local aspects = culture:try_get("aspects", {})
    local items = dmhub.GetTableVisible(CultureAspect.tableName)
    for _, aspectId in pairs(aspects) do
        if aspectId and aspectId ~= "" then
            local item = items[aspectId]
            if item then
                names[#names + 1] = item.name
            end
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--- Return the alphabetically-sorted names of every piece of gear the hero
--- currently has equipped. Equipment lives on the character as a keyed table
--- `equipment = { [slotName] = gearGuid, ... }`, with a `_luaTable` marker
--- that must be skipped. Each GUID resolves through the caller-provided gear
--- table so the dmhub lookup only happens once per dialog.
--- @param hero character The hero to audit.
--- @param gearTable table The cached `tbl_Gear` table (guid → gear item).
--- @return table names Array of gear names, possibly empty.
function HeroAudit.GetEquippedGearNames(hero, gearTable)
    local names = {}
    local equipment = hero:try_get("equipment", {})
    for slot, guid in pairs(equipment) do
        if slot ~= "_luaTable" and type(guid) == "string" and guid ~= "" then
            local item = gearTable[guid]
            if item then
                names[#names + 1] = item.name
            end
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--[[
    UI builders
]]

--- Build a simple label-and-value row with no status indicator and no X/Y.
--- Used for categories where "none chosen" is an acceptable state (Complication, Title).
--- When `iconClass` is provided, a small empty panel with that style class is
--- prepended at the left edge of the row so the style can supply a bgimage.
--- @param label string The category label shown in front of the colon.
--- @param value string The plain value text shown after the colon.
--- @param iconClass string|nil Optional style class name for a 16x16 icon to the left of the label.
--- @return Panel row A horizontal gui.Panel wrapping the markdown label and optional icon.
function HeroAudit.BuildPlainRow(label, value, iconClass)
    ---@type Panel[]
    local children = {}
    if iconClass ~= nil then
        children[#children + 1] = gui.Panel{
            classes = {iconClass},
        }
    end
    children[#children + 1] = gui.Label{
        classes = {"heroaudit-row-text"},
        markdown = true,
        text = string.format("**<color=%s>%s:</color>** %s", MUTED, label, value),
    }
    return gui.Panel{
        classes = {"heroaudit-row"},
        children = children,
    }
end

--- Build a labelled row in the MCDMCharacterPanel markdown style — bold+muted
--- label, default-color value. Shape depends on completeness:
---   - Complete, with name:       `"Ancestry: Dwarf"` + check-mark image
---   - Complete, no name:         `"Culture:"` + check-mark image
---   - Not complete, with name:   `"Ancestry (3/7): Dwarf"` (no check)
---   - Not complete, no name:     `"Culture (2/4):"` (no check)
---   - Missing, with name:        `"Ancestry: none chosen"` (no check)
--- The X/Y count is parenthesized between the label and the colon when not
--- complete, and replaced by the trailing check-mark image when complete.
--- @param label string The category label shown in front of the colon.
--- @param name string|nil Optional chosen-item name slot. Pass nil for categories without a name slot.
--- @param status CBSelectionStatus The selection status to read counts from.
--- @param isMissing boolean When true the row omits X/Y and is tagged with the "missing" class (visual indicator TBD).
--- @return Panel row A horizontal gui.Panel wrapping the label text and an optional check image.
function HeroAudit.BuildInfoRow(label, name, status, isMissing)
    local isComplete = (not isMissing) and status:AllComplete()

    -- Build the bold label prefix, optionally with (X/Y) appended.
    local labelPrefix
    if isMissing or isComplete then
        labelPrefix = label
    else
        local sel, avail = status:GetStatusSummary()
        labelPrefix = string.format("%s (%d/%d)", label, sel, avail)
    end

    -- Build the plain value that follows the colon.
    local text
    if name ~= nil then
        text = string.format("**<color=%s>%s:</color>** %s", MUTED, labelPrefix, name)
    else
        text = string.format("**<color=%s>%s:</color>**", MUTED, labelPrefix)
    end

    local rowClasses = {"heroaudit-row"}
    if isMissing then
        rowClasses[#rowClasses + 1] = "missing"
    end

    local indicatorClasses = {"heroaudit-row-indicator"}
    if isComplete then
        indicatorClasses[#indicatorClasses + 1] = "complete"
    end

    return gui.Panel{
        classes = rowClasses,
        gui.Panel{
            classes = indicatorClasses,
        },
        gui.Label{
            classes = {"heroaudit-row-text"},
            markdown = true,
            text = text,
        },
    }
end

--- Build one hero's card: portrait on the left, info stacked to its right.
--- The first row of the info column is a small builder-sheet icon button
--- followed by the character name and level.
--- @param entry table { token=token, hero=character, name=string } as produced by CollectHeroes.
--- @param gearTable table The cached `tbl_Gear` table (guid → gear item), shared across all cards.
--- @return Panel card The horizontal gui.Panel representing this hero.
function HeroAudit.BuildHeroCard(entry, gearTable)
    local token = entry.token
    local hero = entry.hero

    -- Collect all selection statuses up front.
    local ancestryStatus, ancestryName = HeroAudit.BuildAncestryStatus(hero)
    local cultureStatus = HeroAudit.BuildCultureStatus(hero)
    local careerStatus, careerName = HeroAudit.BuildCareerStatus(hero)
    local classStatus, className = HeroAudit.BuildClassStatus(hero)
    local numKits, kitNames = HeroAudit.GetKitInfo(hero)

    -- Row 1: builder-sheet button + name + level
    local nameRow = gui.Panel{
        classes = {"heroaudit-name-row"},
        gui.Panel{
            classes = {"heroaudit-builder-btn"},
            press = function()
                token:ShowSheet("Builder")
            end,
        },
        gui.Label{
            classes = {"heroaudit-cardname"},
            text = entry.name,
        },
        gui.Label{
            classes = {"heroaudit-level"},
            text = HeroAudit.FormatLevel(hero),
        },
    }

    -- Column 1: Ancestry, Class, Kit
    local col1Children = {}
    col1Children[#col1Children + 1] = HeroAudit.BuildInfoRow(
        "Ancestry", ancestryName, ancestryStatus, ancestryName == "none chosen"
    )
    local classDisplayName = className
    if className ~= "none chosen" then
        local subclassNames = HeroAudit.GetSubclassNames(hero)
        if #subclassNames == 0 then
            classDisplayName = className .. " (no subclass)"
        else
            classDisplayName = className .. " (" .. table.concat(subclassNames, ", ") .. ")"
        end
    end
    col1Children[#col1Children + 1] = HeroAudit.BuildInfoRow(
        "Class", classDisplayName, classStatus, className == "none chosen"
    )
    if numKits > 0 then
        local parts = {}
        local anyMissing = false
        for i = 1, numKits do
            if kitNames[i] then
                parts[#parts + 1] = kitNames[i]
            else
                parts[#parts + 1] = "none chosen"
                anyMissing = true
            end
        end
        table.sort(parts, function(a, b) return string.lower(a) < string.lower(b) end)
        local rowClasses = {"heroaudit-row"}
        if anyMissing then
            rowClasses[#rowClasses + 1] = "missing"
        end
        local indicatorClasses = {"heroaudit-row-indicator"}
        if not anyMissing then
            indicatorClasses[#indicatorClasses + 1] = "complete"
        end
        col1Children[#col1Children + 1] = gui.Panel{
            classes = rowClasses,
            gui.Panel{
                classes = indicatorClasses,
            },
            gui.Label{
                classes = {"heroaudit-row-text"},
                markdown = true,
                text = string.format("**<color=%s>Kit:</color>** %s", MUTED, table.concat(parts, ", ")),
            },
        }
    end
    local col1 = gui.Panel{
        classes = {"heroaudit-detail-col"},
        children = col1Children,
    }

    -- Column 2: Career, Culture
    local aspectNames = HeroAudit.GetAspectNames(hero)
    local cultureName, cultureMissing
    if #aspectNames == 0 then
        cultureName = "none chosen"
        cultureMissing = true
    else
        cultureName = table.concat(aspectNames, ", ")
        cultureMissing = false
    end

    local col2Children = {}
    col2Children[#col2Children + 1] = HeroAudit.BuildInfoRow(
        "Career", careerName, careerStatus, careerName == "none chosen"
    )
    col2Children[#col2Children + 1] = HeroAudit.BuildInfoRow(
        "Culture", cultureName, cultureStatus, cultureMissing
    )
    local col2 = gui.Panel{
        classes = {"heroaudit-detail-col"},
        children = col2Children,
    }

    -- Column 3: Complication, Title (plain rows, "none chosen" is fine)
    local complicationNames = HeroAudit.GetComplicationNames(hero)
    local complicationValue = #complicationNames > 0
        and table.concat(complicationNames, ", ")
        or "none chosen"

    local titleNames = HeroAudit.GetTitleNames(hero)
    local titleValue = #titleNames > 0
        and table.concat(titleNames, ", ")
        or "none chosen"

    local col3 = gui.Panel{
        classes = {"heroaudit-detail-col"},
        HeroAudit.BuildPlainRow("Complication", complicationValue),
        HeroAudit.BuildPlainRow("Title", titleValue),
    }

    -- Three-column container holding the detail columns.
    local detailCols = gui.Panel{
        classes = {"heroaudit-detail-cols"},
        col1,
        col2,
        col3,
    }

    -- Downtime projects row — full width of the info column, below detailCols.
    local dtCounts = HeroAudit.GetDowntimeProjectCounts(hero)
    local dtValue
    if dtCounts.total == 0 then
        dtValue = "none found"
    else
        local parts = {}
        if dtCounts.complete > 0 then
            parts[#parts + 1] = string.format("%d Complete", dtCounts.complete)
        end
        if dtCounts.active > 0 then
            parts[#parts + 1] = string.format("%d Active", dtCounts.active)
        end
        if dtCounts.needAttention > 0 then
            parts[#parts + 1] = string.format("%d Need Attention", dtCounts.needAttention)
        end
        dtValue = table.concat(parts, ", ")
    end
    local downtimeRow = HeroAudit.BuildPlainRow(
        "Downtime Projects",
        dtValue,
        "heroaudit-row-modicon"
    )

    -- Equipped gear row — full width of the info column, above downtime.
    local gearNames = HeroAudit.GetEquippedGearNames(hero, gearTable)
    local gearValue = #gearNames > 0 and table.concat(gearNames, ", ") or "none found"
    local gearRow = HeroAudit.BuildPlainRow(
        "Equipped Gear",
        gearValue,
        "heroaudit-row-gearicon"
    )

    -- Vertical info column to the right of the token image.
    local infoCol = gui.Panel{
        classes = {"heroaudit-info-col"},
        nameRow,
        detailCols,
        gearRow,
        downtimeRow,
    }

    -- Full card: token image + info column in a horizontal flow.
    return gui.Panel{
        classes = {"heroaudit-card"},
        gui.CreateTokenImage(token, {
            width = 80,
            height = 80,
            halign = "left",
            valign = "top",
        }),
        infoCol,
    }
end

--- Build the top-level audit dialog panel returned to LaunchablePanel.
--- @return Panel dialog The root gui.Panel for the popup.
function HeroAudit.BuildDialog()
    local entries = HeroAudit.CollectHeroes()
    local gearTable = dmhub.GetTable("tbl_Gear") or {}

    local header = gui.Panel{
        classes = {"heroaudit-header"},
        gui.Label{
            classes = {"heroaudit-header-label"},
            text = "Hero Audit",
        },
    }

    local body
    if #entries == 0 then
        body = gui.Label{
            classes = {"heroaudit-empty"},
            text = "No player-assigned heroes found.",
        }
    else
        local cards = {}
        for _, entry in ipairs(entries) do
            cards[#cards + 1] = HeroAudit.BuildHeroCard(entry, gearTable)
        end
        body = gui.Panel{
            classes = {"heroaudit-cards"},
            vscroll = true,
            children = cards,
        }
    end

    return gui.Panel{
        styles = heroAuditStyles,
        classes = {"heroaudit-dialog"},
        header,
        body,
    }
end

if dmhub.isDM then
LaunchablePanel.Register{
    name = "Hero Audit",
    menu = "tools",
    icon = "icons/icon_app/icon_app_16.png",
    halign = "center",
    valign = "center",
    draggable = true,
    content = function()
        return HeroAudit.BuildDialog()
    end,
}
end
