local mod = dmhub.GetModLoading()

--- The reads the Hero Audit panels share: which heroes to show, and the
--- per-hero values the combat and exploration tabs print. Kept apart from the
--- panels so the launchable window and the dock panel agree on both.
--- @class HAHeroData: GameType
HAHeroData = RegisterGameType("HAHeroData")

--- Collect every player-assigned hero token in the game, sorted A→Z.
--- @return table entries Array of { token=token, hero=character, name=string }, alphabetical.
function HAHeroData.CollectHeroes()
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

--- Every hero on the map or in the running fight, sorted A→Z. The two sets
--- genuinely differ: a hero can be in the initiative queue without being placed,
--- and standing on the map without having joined the fight.
---
--- Drawn from the global character list rather than `dmhub.allTokens`, which is
--- map-scoped and can never see an unplaced combatant.
--- @return table entries Array of { token=token, hero=character, name=string }, alphabetical.
function HAHeroData.CollectCombatHeroes()
    local onMap = {}
    for _, token in ipairs(dmhub.allTokens) do
        onMap[token.charid] = true
    end

    --Only while a fight is actually running: a hidden queue still holds the
    --entries from the last one.
    local combatants = nil
    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        combatants = queue.entries
    end

    local entries = {}
    for _, token in ipairs(table.values(game.GetGameGlobalCharacters())) do
        if token.properties ~= nil and token.properties:IsHero() then
            local include = onMap[token.charid] == true
            if not include and combatants ~= nil then
                include = combatants[InitiativeQueue.GetInitiativeId(token)] ~= nil
            end

            if include then
                entries[#entries + 1] = {
                    token = token,
                    hero = token.properties,
                    name = token.name or "Unknown",
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return entries
end

--- The player party's name, for the filter that reads from it.
--- @return string name Falls back to "Player" when the party will not resolve.
function HAHeroData.PartyName()
    local party = (dmhub.GetTable(Party.tableName) or {})[GetDefaultPartyID()]
    if party == nil or party.name == nil or party.name == "" then
        return "Player"
    end
    return party.name
end

--- The player party's roster, as tokens. Placed or not: party membership is
--- roster data, so it sees heroes the map never will.
--- @return table tokens
local function PartyTokens()
    local tokens = {}
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

--- Heroes under one of the Exploration tab's filters, sorted A→Z.
--- @param filterId string One of the HAConstants.filter* ids.
--- @return table entries Array of { token=token, hero=character, name=string }, alphabetical.
function HAHeroData.CollectByFilter(filterId)
    local tokens
    if filterId == HAConstants.filterMap then
        tokens = dmhub.allTokens
    elseif filterId == HAConstants.filterParty then
        tokens = PartyTokens()
    else
        tokens = table.values(game.GetGameGlobalCharacters())
    end

    local entries = {}
    for _, token in ipairs(tokens) do
        if token ~= nil and token.properties ~= nil and token.properties:IsHero() then
            --"PARTY" is the shared-ownership marker, not a player.
            local owner = token.ownerId
            local include = filterId ~= HAConstants.filterAssigned
                or (owner ~= nil and owner ~= "" and owner ~= "PARTY")

            if include then
                entries[#entries + 1] = {
                    token = token,
                    hero = token.properties,
                    name = token.name or "Unknown",
                }
            end
        end
    end

    table.sort(entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return entries
end

--- Shorten a hero name for a narrow card, with an ASCII ellipsis.
--- @param name string|nil The hero name.
--- @param maxChars number|nil Cap, defaulting to HAConstants.nameMaxChars.
--- @return string truncated
function HAHeroData.TruncateName(name, maxChars)
    maxChars = maxChars or HAConstants.nameMaxChars
    if name == nil then
        return ""
    end
    if #name <= maxChars then
        return name
    end
    return string.sub(name, 1, maxChars - 3) .. "..."
end

--- Read a hero's stamina into everything the compact bar needs to draw itself.
--- Past zero a dying hero's bar reads down toward the value that kills them, so
--- both the ratio and the denominator change rather than just the fill.
--- @param hero character The hero to read.
--- @return table health { current, max, deathAt, dying, dead, winded, text, ratio }
function HAHeroData.Health(hero)
    local current = hero:CurrentHitpoints()
    local maxStamina = hero:MaxHitpoints()
    local windedVal = math.floor(maxStamina / 2)
    local dying = hero:IsDying()
    local dead = hero:IsDead()

    local text
    local ratio
    if dead then
        text = "DEAD"
        ratio = 0
    elseif dying then
        text = string.format("%d/-%d", current, windedVal)
        ratio = windedVal > 0 and 1 - (-current / windedVal) or 0
    else
        text = string.format("%d/%d", current, maxStamina)
        ratio = maxStamina > 0 and current / maxStamina or 0
    end

    return {
        current = current,
        max = maxStamina,
        deathAt = -windedVal,
        dying = dying,
        dead = dead,
        winded = current <= hero:BloodiedThreshold(),
        text = text,
        ratio = math.max(0, math.min(1, ratio)),
    }
end

--- Recovery is found by name in the user-editable resource table, so every
--- caller has to cope with it being absent.
--- @return string|nil recoveryid
--- @return table|nil recoveryInfo
function HAHeroData.RecoveryResource()
    local resourcesTable = dmhub.GetTableVisible(CharacterResource.tableName)
    for k, v in pairs(resourcesTable) do
        if v.name == "Recovery" then
            return k, v
        end
    end
    return nil, nil
end

--- A hero's recent stamina changes, as rows ready to print.
---
--- The engine records absolute values, not deltas, so the direction of each
--- change is the difference from the one before it -- which is what lets a row
--- be coloured as damage or healing. Only the latest refresh group is kept, the
--- way the engine's own history tooltip does it.
--- @param hero character The hero to read.
--- @return table[] rows { text, status }, oldest first; status is a tint class or nil.
function HAHeroData.StaminaHistory(hero)
    local history = hero:GetStatHistory("stamina"):GetHistory()

    local entries = {}
    local refreshid = nil
    for _, entry in ipairs(history) do
        if entry.refreshid ~= refreshid then
            entries = {}
        end
        entries[#entries + 1] = entry
        refreshid = entry.refreshid
    end

    local rows = {}
    local previous = nil
    for _, entry in ipairs(entries) do
        local value = tonumber(entry.value)

        local status = nil
        local prefix = ""
        if value ~= nil and previous ~= nil and value ~= previous then
            local delta = value - previous
            status = delta < 0 and "danger" or "success"
            prefix = string.format("%+d  ", delta)
        end
        if value ~= nil then
            previous = value
        end

        local note = ""
        if entry.note ~= nil and entry.note ~= "" then
            note = string.format(" (%s)", entry.note)
        end

        rows[#rows + 1] = {
            text = string.format("%sSet to %s by %s %s%s",
                prefix, tostring(entry.value), tostring(entry.who), tostring(entry.when), note),
            status = status,
        }
    end

    return rows
end

--- Read a hero's recovery value and how many they have left.
--- Recovery is found by name in the user-editable resource table, so it can be
--- absent; zeroes stand in rather than the row disappearing.
--- @param hero character The hero to read.
--- @return number amount The stamina one recovery restores.
--- @return number current Recoveries remaining.
--- @return number maxRecoveries Recoveries at full.
function HAHeroData.Recoveries(hero)
    local recoveryid, recoveryInfo = HAHeroData.RecoveryResource()

    if recoveryInfo == nil then
        return 0, 0, 0
    end

    local usage = hero:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
    local maxRecoveries = hero:GetResources()[recoveryid] or 0
    return hero:RecoveryAmount(), maxRecoveries - usage, maxRecoveries
end

--- How urgent a hero's remaining recoveries are, as one of the panel's icon
--- tint classes. The last two are called out absolutely rather than by share:
--- one recovery left is dire whether the hero started with three or ten.
--- @param current number Recoveries remaining.
--- @param maxRecoveries number Recoveries at full.
--- @return string tintClass An ha-tint-* class.
function HAHeroData.RecoveryStatus(current, maxRecoveries)
    if current <= 1 then
        return "ha-tint-danger"
    end
    if maxRecoveries > 0 and current / maxRecoveries >= 0.5 then
        return "ha-tint-success"
    end
    return "ha-tint-warning"
end

--- Read a hero's speed the way the character panel does: the headline number is
--- the higher of base and current, and being under base is what "restricted"
--- means.
--- @param hero character The hero to read.
--- @return number display The number to print.
--- @return boolean restricted True when current movement is below base.
--- @return number current The current movement speed.
function HAHeroData.Speed(hero)
    local base = hero:GetBaseSpeed()
    local current = hero:CurrentMovementSpeed()
    return current >= base and current or base, current < base, current
end

--- Surges and heroic resources are combat-only, and the initiative queue is
--- what says whether combat is running.
--- @return boolean inCombat
function HAHeroData.InCombat()
    local queue = dmhub.initiativeQueue
    return queue ~= nil and not queue.hidden
end

--- Whether this hero is sitting out a fight that is already running.
--- @param hero character The hero to read.
--- @return boolean canAdd
function HAHeroData.CanAddToCombat(hero)
    if not HAHeroData.InCombat() then
        return false
    end
    return hero:try_get("_tmp_initiativeStatus") == "NonCombatant"
end

--- @param hero character The hero to read.
--- @return string surges The count, or HAConstants.notInCombat out of combat.
function HAHeroData.Surges(hero)
    if not HAHeroData.InCombat() then
        return HAConstants.notInCombat
    end
    return tostring(hero:GetAvailableSurges())
end

--- The hero's class heroic resource: what it looks like, what it is called, and
--- how much they have.
--- @param hero character The hero to read.
--- @return string icon The class's heroic resource glyph.
--- @return string name What the class calls it.
--- @return string value The amount, or HAConstants.notInCombat out of combat.
function HAHeroData.HeroicResource(hero)
    local classInfo = hero:IsHero() and hero:GetClass() or nil
    local icon = HAConstants.iconPlaceholder
    if classInfo ~= nil and classInfo ~= false then
        icon = classInfo:try_get("heroicResourceIcon", HAConstants.iconPlaceholder)
    end

    local value = HAConstants.notInCombat
    if HAHeroData.InCombat() then
        value = tostring(hero:GetHeroicOrMaliceResources())
    end

    return icon, hero:GetHeroicResourceName(), value
end

--- The hero's weaknesses then immunities, alphabetical within each group.
--- Condition immunities arrive as a sentence rather than a typed entry, so they
--- join the immunities with no number of their own.
--- @param hero character The hero to read.
--- @return table[] entries { label, weakness }, weaknesses first.
function HAHeroData.Resistances(hero)
    local weaknesses = {}
    local immunities = {}

    for _, resistance in ipairs(hero:ResistanceEntries()) do
        local dr = resistance.entry:try_get("dr", 0)
        local label = string.format("%s %d",
            TacPanel.CleanResistanceText(resistance.text), math.abs(dr))
        if dr < 0 then
            weaknesses[#weaknesses + 1] = label
        else
            immunities[#immunities + 1] = label
        end
    end

    local conditionImmunity = hero:ConditionImmunityDescription()
    if conditionImmunity ~= "" then
        immunities[#immunities + 1] = TacPanel.CleanResistanceText(conditionImmunity)
    end

    local byName = function(a, b) return string.lower(a) < string.lower(b) end
    table.sort(weaknesses, byName)
    table.sort(immunities, byName)

    local result = {}
    for _, label in ipairs(weaknesses) do
        result[#result + 1] = { label = label, weakness = true }
    end
    for _, label in ipairs(immunities) do
        result[#result + 1] = { label = label, weakness = false }
    end
    return result
end

--- @param hero character The hero to read.
--- @return number disengage
function HAHeroData.Disengage(hero)
    local attr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
    if attr == nil then
        return 0
    end
    return hero:GetCustomAttribute(attr)
end

--- @param hero character The hero to read.
--- @return number stability
function HAHeroData.Stability(hero)
    return hero:Stability()
end

--- The hero's movement mode, but only while they are off the ground.
--- @param token token The hero's token.
--- @return table|nil moveType The HAConstants.moveTypes entry; nil on the ground.
--- @return number altitude The token's floor altitude.
function HAHeroData.Movement(token)
    local moveType = HAConstants.moveTypes[token.properties:CurrentMoveType()]
    if moveType == nil then
        return nil, 0
    end
    return moveType, token.floorAltitude
end

--- Gather a hero's conditions as plain data, ready for our own chips. Auras and
--- status effects are deliberately left out. The label and tooltip come from the
--- character panel's own text builders so durations and riders read identically.
--- @param hero character The hero to read.
--- @return table[] entries { kind, key, label, tooltip, icon, iconColor, iconHueshift, canSetCaster }, alphabetical.
function HAHeroData.Conditions(hero)
    local result = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

    for condid, cond in pairs(hero:try_get("inflictedConditions", {})) do
        local info = conditionsTable[condid]
        local display = info ~= nil and info.display or {}
        result[#result + 1] = {
            kind = "condition",
            key = condid,
            label = TacPanel.ConditionChipText(condid, cond, hero),
            tooltip = TacPanel.ConditionTooltipText(condid, cond, hero),
            icon = info ~= nil and info.iconid or nil,
            iconColor = display.bgcolor,
            iconHueshift = display.hueshift,
            --Only conditions that track a caster, and only until one is known.
            canSetCaster = info ~= nil and info.trackCaster == true
                and cond.casterInfo == nil,
        }
    end

    for key, entry in pairs(hero:try_get("customConditions", {})) do
        result[#result + 1] = {
            kind = "custom",
            key = key,
            label = entry.text,
            tooltip = entry.text,
        }
    end

    table.sort(result, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)

    return result
end

--- The hero's proficient skills, alphabetical.
--- @param hero character The hero to read.
--- @return string[] names
function HAHeroData.GetSkillNames(hero)
    local names = {}
    local catSkills = hero:GetCategorizedSkills() or {}
    for _, cat in ipairs(catSkills) do
        for _, skill in ipairs(cat.skills or {}) do
            if skill.name then
                names[#names + 1] = skill.name
            end
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--- The hero's known languages, alphabetical.
--- @param hero character The hero to read.
--- @param includeSpeakers boolean|nil Append the "(who speaks it)" parenthetical.
--- @return string[] names
function HAHeroData.GetLanguageNames(hero, includeSpeakers)
    local names = {}
    local langs = hero:LanguagesKnown() or {}
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    for guid, _ in pairs(langs) do
        local lang = langTable[guid]
        if lang and lang.name then
            local speakers = ""
            if includeSpeakers and lang.speakers and #lang.speakers > 0 then
                speakers = string.format(" (%s)", lang.speakers)
            end
            names[#names + 1] = lang.name .. speakers
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return names
end

--- The skill table's id for a skill name, which is what a roll request wants.
--- @param name string The skill's display name.
--- @return string|nil skillid
function HAHeroData.SkillIdByName(name)
    for skillid, skill in pairs(dmhub.GetTable(Skill.tableName) or {}) do
        if skill.name == name then
            return skillid
        end
    end
    return nil
end

--- Roll a per-hero list up into one entry per distinct value, counting heroes.
--- @param entries table[] Hero entries as produced by CollectHeroes.
--- @param listFn fun(hero: character): string[] Produces one hero's values.
--- @return table[] aggregated { name, count, members }, alphabetical; members are
--- { name, token } and alphabetical too.
function HAHeroData.Aggregate(entries, listFn)
    local byName = {}
    for _, entry in ipairs(entries) do
        for _, name in ipairs(listFn(entry.hero)) do
            local bucket = byName[name]
            if bucket == nil then
                bucket = { name = name, count = 0, members = {} }
                byName[name] = bucket
            end
            bucket.count = bucket.count + 1
            --Name and token together, so sorting cannot desync them.
            bucket.members[#bucket.members + 1] = {
                name = entry.name,
                token = entry.token,
            }
        end
    end

    local result = {}
    for _, bucket in pairs(byName) do
        table.sort(bucket.members, function(a, b)
            return string.lower(a.name) < string.lower(b.name)
        end)
        result[#result + 1] = bucket
    end
    table.sort(result, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
    return result
end
