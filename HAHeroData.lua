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

--- The creatures a hero has summoned, alphabetical. Map-scoped: a summon that
--- is not placed is not in play.
--- @param token token The summoner's token.
--- @return table tokens
function HAHeroData.SummonsFor(token)
    local result = {}
    for _, other in ipairs(dmhub.allTokens) do
        if other.summonerid == token.charid then
            result[#result + 1] = other
        end
    end

    table.sort(result, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    return result
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

--- Set how many recoveries a hero has left, the way the character panel's
--- count box does: capped at their most, and applied as a refresh or a
--- spend of the difference so the resource's own history records it.
--- Nothing below zero, and nothing when the number is already right.
--- @param token token The hero's token.
--- @param wanted number Recoveries to have left.
function HAHeroData.SetRecoveries(token, wanted)
    local recoveryid, recoveryInfo = HAHeroData.RecoveryResource()
    if recoveryInfo == nil or wanted < 0 or not token.valid or token.properties == nil then
        return
    end

    local props = token.properties
    local most = props:GetResources()[recoveryid] or 0
    wanted = math.min(wanted, most)
    local usage = props:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
    local delta = wanted - (most - usage)
    if delta == 0 then
        return
    end

    token:ModifyProperties{
        description = "Set Recoveries",
        execute = function()
            if delta > 0 then
                props:RefreshResource(recoveryid, recoveryInfo.usageLimit, delta, "Set Recoveries")
            else
                props:ConsumeResource(recoveryid, recoveryInfo.usageLimit, -delta, "Set Recoveries")
            end
        end,
    }
end

--- Set a hero's surges, the way the character panel's box does: the
--- difference is consumed, negative when gaining, so the surge history
--- records it. Nothing below zero, nothing when already right.
--- @param token token The hero's token.
--- @param wanted number Surges to have.
function HAHeroData.SetSurges(token, wanted)
    if wanted < 0 or not token.valid or token.properties == nil then
        return
    end

    local props = token.properties
    local diff = wanted - props:GetAvailableSurges()
    if diff == 0 then
        return
    end

    token:ModifyProperties{
        description = "Change Surges",
        execute = function()
            props:ConsumeSurges(-diff, "Manually Set")
        end,
    }
end

--- Set a hero's heroic resource, the way the character panel's box does:
--- clamped by the resource's own rule, then the difference refreshed or
--- consumed so its history records it. Nothing when already right.
--- @param token token The hero's token.
--- @param wanted number Heroic resource to have.
function HAHeroData.SetHeroicResource(token, wanted)
    if not token.valid or token.properties == nil then
        return
    end

    local props = token.properties
    local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]
    if resource == nil then
        return
    end

    wanted = resource:ClampQuantity(props, wanted)
    local diff = wanted - props:GetHeroicOrMaliceResources()
    if diff == 0 then
        return
    end

    token:ModifyProperties{
        description = "Change Heroic Resource",
        execute = function()
            if diff > 0 then
                props:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
            else
                props:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
            end
        end,
    }
end

--- The character panel's hero token tooltip: what they buy, then the pool's
--- recent changes.
--- @param hero character A hero; the pool is the party's.
--- @return string markdown
function HAHeroData.HeroTokenTooltip(hero)
    local text = [[**Hero Tokens**
* You can spend a hero token to gain two surges.
* You can spend a hero token when you fail a saving throw to succeed instead.
* You can reroll the result of a test. You must use the new result.
* You can spend 2 hero tokens to regain Stamina equal to your Recovery value without spending a Recovery.
]]
    local history = hero:GetHeroTokenHistory()
    if history ~= nil and #history > 0 then
        text = text .. "\n**Recent Changes:**"
        for _, entry in ipairs(history) do
            text = string.format("%s\n%s: %d by %s %s", text, entry.note, entry.value, entry.who, entry.when)
        end
    end
    return text
end

--- Set a hero's victories, as the character panel's box does. Nothing below
--- zero, nothing when already right; the game raises its own event when the
--- count goes up.
--- @param token token The hero's token.
--- @param wanted number Victories to have.
function HAHeroData.SetVictories(token, wanted)
    if wanted < 0 or not token.valid or token.properties == nil then
        return
    end

    local props = token.properties
    if wanted == props:GetVictories() then
        return
    end

    token:ModifyProperties{
        description = "Set Victories",
        execute = function()
            props:SetVictories(wanted)
        end,
    }
end

--- Set the party's hero tokens by hand, as the character panel's box does.
--- Nothing below zero, nothing when already right.
--- @param token token A hero's token; the pool is the party's.
--- @param wanted number Hero tokens to have.
function HAHeroData.SetHeroTokens(token, wanted)
    if wanted < 0 or not token.valid or token.properties == nil then
        return
    end

    local props = token.properties
    if wanted == props:GetHeroTokens() then
        return
    end

    token:ModifyProperties{
        description = "Set Hero Tokens",
        execute = function()
            props:SetHeroTokens(wanted, "Set manually")
        end,
    }
end

--- The three counts a session reset of hero tokens could go to, as the
--- character panel reckons them: the encounter builder's hero count, heroes
--- on the map, and heroes in the player party.
--- @return number encounterCount
--- @return number mapCount
--- @return number partyCount
function HAHeroData.HeroTokenRefreshCounts()
    local encounterCount = dmhub.GetSettingValue("numheroes")

    local mapCount = 0
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.properties ~= nil and tok.properties:IsHero() then
            mapCount = mapCount + 1
        end
    end

    local partyCount = 0
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil and tok.properties ~= nil and tok.properties:IsHero() then
            partyCount = partyCount + 1
        end
    end

    return encounterCount, mapCount, partyCount
end

--- Reset the party's hero tokens for the session, as the character panel's
--- refresh button does.
--- @param token token A hero's token; the pool is the party's.
--- @param n number Hero tokens to reset to.
function HAHeroData.RefreshHeroTokens(token, n)
    if not token.valid or token.properties == nil then
        return
    end

    token:ModifyProperties{
        description = "Reset Hero Tokens",
        execute = function()
            token.properties:SetHeroTokens(n, "Session Reset")
        end,
    }
end

--- How urgent a hero's remaining recoveries are, as one of the panel's icon
--- tint classes. The last two are called out absolutely rather than by share:
--- one recovery left is dire whether the hero started with three or ten.
--- @param current number Recoveries remaining.
--- @param maxRecoveries number Recoveries at full.
--- @return string tintClass A thc-tint-* class.
function HAHeroData.RecoveryStatus(current, maxRecoveries)
    if current <= 1 then
        return "thc-tint-danger"
    end
    if maxRecoveries > 0 and current / maxRecoveries >= 0.5 then
        return "thc-tint-success"
    end
    return "thc-tint-warning"
end

--- @param hero character The hero to read.
--- @return string surges The count, or HAConstants.notInCombat out of combat.
function HAHeroData.Surges(hero)
    if not THCUtils.InCombat() then
        return HAConstants.notInCombat
    end
    return tostring(hero:GetAvailableSurges())
end

--- The heroic resource: what it looks like, what it is called, and how much
--- they have.
---
--- The glyph comes off a class, and a summon has no class of its own, so it
--- takes its summoner's. The name and the amount are still the summon's own --
--- it already reports the summoner's resource by name.
--- @param token token The token to read.
--- @return string icon The heroic resource glyph.
--- @return string name What the class calls it.
--- @return string value The amount, or HAConstants.notInCombat out of combat.
function HAHeroData.HeroicResource(token)
    local hero = token.properties

    local iconSource = hero
    if not hero:IsHero() and token.summonerid ~= nil then
        local summoner = dmhub.GetTokenById(token.summonerid)
        if summoner ~= nil and summoner.properties ~= nil then
            iconSource = summoner.properties
        end
    end

    local classInfo = iconSource:IsHero() and iconSource:GetClass() or nil
    local icon = HAConstants.iconPlaceholder
    if classInfo ~= nil and classInfo ~= false then
        icon = classInfo:try_get("heroicResourceIcon", HAConstants.iconPlaceholder)
    end

    local value = HAConstants.notInCombat
    if THCUtils.InCombat() then
        value = tostring(hero:GetHeroicOrMaliceResources())
    end

    return icon, hero:GetHeroicResourceName(), value
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

--- The hero's known languages with who speaks them, alphabetical by name.
--- @param hero character The hero to read.
--- @return {name: string, speakers: string}[] languages Speakers is "" when the table has none.
function HAHeroData.GetLanguages(hero)
    local result = {}
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    for guid, _ in pairs(hero:LanguagesKnown() or {}) do
        local lang = langTable[guid]
        if lang and lang.name then
            result[#result + 1] = {
                name = lang.name,
                speakers = lang.speakers or "",
            }
        end
    end
    table.sort(result, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return result
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
