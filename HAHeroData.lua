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

--- Every hero of the players' on the map or in the running fight, sorted
--- A→Z: a character-sheet creature that a player controls directly or
--- that the player party lists. A party of the Director's own characters
--- stays out, however it is built. The two placement sets genuinely
--- differ: a hero can be in the initiative queue without being placed,
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

    local inParty = {}
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        inParty[charid] = true
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
            --Shared party control counts a token as player controlled too,
            --so the direct test is the one that means a named owner.
            local theirs = token.playerControlledNotShared or inParty[token.charid] == true
            local include = theirs and onMap[token.charid] == true
            if theirs and not include and combatants ~= nil then
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

--- The retainers a hero mentors, alphabetical: the followers the hero lists
--- that are retainers. Map-scoped, as the summons are: a retainer that is
--- not placed is not in play.
--- @param token token The mentor's token.
--- @return table tokens
function HAHeroData.RetainersFor(token)
    local followers = token.properties:GetFollowers() or {}
    local result = {}
    for _, other in ipairs(dmhub.allTokens) do
        if followers[other.charid] and other.properties ~= nil and other.properties:IsRetainer() then
            result[#result + 1] = other
        end
    end

    table.sort(result, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    return result
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
