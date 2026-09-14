local mod = dmhub.GetModLoading()

--- The Combat tab: one compact card per hero, with stamina, the movement and
--- recovery numbers, and their conditions.
--- @class HACombatTab: GameType
HACombatTab = RegisterGameType("HACombatTab")

--- Out of their own recoveries and short of hero tokens, a hero can draw on a
--- bonded ally's. Both writes share one groupid, so healing here and spending
--- there undo as a single step.
--- @param element Panel The pressed button, which hosts the popup.
--- @param token token The hero recovering.
--- @param recoveryid string The Recovery resource id.
--- @param recoveryInfo table The Recovery resource definition.
local function ShowSharedRecoveryMenu(element, token, recoveryid, recoveryInfo)
    local sharing = token.properties:ShareRecoveriesWith()
    if sharing == nil then
        return
    end

    local entries = {}
    for _, sourceToken in ipairs(sharing) do
        if sourceToken.charid ~= token.charid then
            local usage = sourceToken.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
            local sharedMax = sourceToken.properties:GetResources()[recoveryid] or 0
            local available = sharedMax - usage

            if available > 0 then
                entries[#entries + 1] = {
                    text = string.format("Spend %s's Recovery (%d/%d)",
                        sourceToken.name, available, sharedMax),
                    click = function()
                        element.popup = nil
                        if token.properties:CurrentHitpoints() >= token.properties:MaxHitpoints() then
                            return
                        end

                        local groupid = dmhub.GenerateGuid()
                        token:ModifyProperties{
                            description = "Use Recovery",
                            groupid = groupid,
                            execute = function()
                                token.properties:Heal(token.properties:RecoveryAmount(), "Use Recovery")
                            end,
                        }
                        sourceToken:ModifyProperties{
                            description = string.format("%s's Recovery used by %s",
                                sourceToken.name, token.name),
                            groupid = groupid,
                            execute = function()
                                sourceToken.properties:ConsumeResource(
                                    recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                            end,
                        }
                    end,
                }
            end
        end
    end

    if #entries == 0 then
        return
    end

    --A context menu re-roots out of this panel's tree, so it carries its own
    --cascade rather than inheriting ours.
    element.popup = gui.ContextMenu{
        styles = ThemeEngine.GetStyles(),
        entries = entries,
    }
end

--- Spend a recovery, by the character panel's rules: own recoveries first, then
--- two hero tokens, then a bonded ally's. Refused outright at full stamina,
--- where the recovery would buy nothing.
--- @param element Panel The pressed button.
--- @param token token The hero recovering.
local function SpendRecovery(element, token)
    local recoveryid, recoveryInfo = HAHeroData.RecoveryResource()
    if recoveryInfo == nil or not token.valid or token.properties == nil then
        return
    end

    local remaining = math.max(0,
        (token.properties:GetResources()[recoveryid] or 0)
        - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))

    local useHeroTokens = false
    if remaining <= 0 then
        if not token.properties:IsHero() or token.properties:GetHeroTokens() < 2 then
            ShowSharedRecoveryMenu(element, token, recoveryid, recoveryInfo)
            return
        end
        useHeroTokens = true
    end

    if token.properties:CurrentHitpoints() >= token.properties:MaxHitpoints() then
        return
    end

    token:ModifyProperties{
        description = "Use Recovery",
        execute = function()
            token.properties:Heal(token.properties:RecoveryAmount(), "Use Recovery")
            if useHeroTokens then
                token.properties:SetHeroTokens(token.properties:GetHeroTokens() - 2, "Used to Recover")
            else
                token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
            end
        end,
    }
end

--- Which heroes have their summons folded away, keyed by the summoner's charid.
--- Kept off the card, which outlives the hero bound to it. Absent means
--- expanded.
local m_summonsCollapsed = {}

--- @param token token|nil The summoner.
--- @return boolean
function HACombatTab.SummonsCollapsed(token)
    return token ~= nil and m_summonsCollapsed[token.charid] == true
end

--- @param token token|nil The summoner.
function HACombatTab.ToggleSummons(token)
    if token == nil then
        return
    end
    m_summonsCollapsed[token.charid] = not m_summonsCollapsed[token.charid]
end

--- One hero card, built with no hero in it. The list hands it one through the
--- "bindHero" event and hands it nil when there are more cards than heroes, at
--- which point it parks itself rather than being destroyed.
---
--- A hero's summons are built INSIDE their card rather than beside it, so the
--- hairline that separates cards falls below the whole group and the summons
--- read as belonging to the hero rather than merely following them.
---
--- Open Request Rolls for one hero with one characteristic already chosen.
--- The dialog seeds its token pool from the map selection and takes
--- characteristics as a set keyed by id, so pre-selecting means setting the
--- selection and passing that set. No skill: the dialog leaves it unset.
--- @param token token The hero to request the roll from.
--- @param attrId string The characteristic's id in creature.attributesInfo.
local function RequestCharacteristicRoll(token, attrId)
    dmhub.selectedTokens = {token}
    LaunchablePanel.LaunchPanelByName("Request Rolls", { characteristics = { [attrId] = true } })
end

--- Opens the card's form on a value, from any control inside the card.
--- @param element Panel The pressed control.
--- @param token token The creature the card is for, which keys the form.
--- @param entry {label: string, initial: string, apply: fun(text: string)} What the form opens with.
local function OpenEditor(element, token, entry)
    local host = element:FindParentWithClass(THCWidgets.overlayHostClass)
    if host ~= nil then
        host:FireEventTree("openOverlay", token, entry)
    end
end

--- A stat value pressed to set it, through the card's form, for a group
--- whose glyph has a press of its own. Reads as a plain value when it
--- cannot be set.
--- @param token token The hero the card is for, which keys the card's form.
--- @param text string The value as printed.
--- @param editable boolean Whether this viewer may set it right now.
--- @param entry {label: string, initial: string, apply: fun(text: string)} What the form opens with.
--- @return Panel
local function EditableStat(token, text, editable, entry)
    return gui.Label{
        classes = {"thc-stat-value", "sizeXs"},
        text = text,
        hoverCursor = editable and "pressbutton" or nil,
        linger = editable and THCWidgets.Tooltip("Set " .. entry.label) or nil,
        press = editable and function(element)
            OpenEditor(element, token, entry)
        end or nil,
    }
end

--- A whole stat group pressed to set its value, glyph or number, for a stat
--- whose glyph has no press of its own. The group is the hit target and its
--- children are not, so the cursor, hover and press land on it anywhere;
--- the children brighten off its hover. Reads as a plain group when it
--- cannot be set.
--- @param tooltip string What the stat is called.
--- @param icon string The stat's glyph.
--- @param token token The creature the card is for, which keys the card's form.
--- @param text string The value as printed.
--- @param editable boolean Whether this viewer may set it right now.
--- @param entry {label: string, initial: string, apply: fun(text: string)} What the form opens with.
--- @return Panel
local function EditableGroup(tooltip, icon, token, text, editable, entry)
    local hot = editable and "thc-hot" or nil
    return gui.Panel{
        classes = {"thc-stat-group"},
        linger = THCWidgets.Tooltip(editable and ("Set " .. entry.label) or tooltip),
        hoverCursor = editable and "pressbutton" or nil,
        press = editable and function(element)
            OpenEditor(element, token, entry)
        end or nil,
        gui.Panel{
            classes = {"thc-stat-icon", "bgInverse", hot},
            bgimage = icon,
            interactable = false,
        },
        gui.Label{
            classes = {"thc-stat-value", "sizeXs", hot},
            text = text,
            interactable = false,
        },
    }
end

--- Reset hero tokens for the session, by the character panel's rules: when
--- the encounter builder, the map and the party agree on how many heroes
--- there are, straight to that count; when they differ, a menu offers each
--- distinct count.
--- @param element Panel The pressed button, which the menu hangs off.
--- @param token token A hero's token; the pool is the party's.
local function RefreshHeroTokens(element, token)
    local encounterCount, mapCount, partyCount = HAHeroData.HeroTokenRefreshCounts()
    if encounterCount == mapCount and mapCount == partyCount then
        HAHeroData.RefreshHeroTokens(token, encounterCount)
        return
    end

    local seen = {}
    local entries = {}
    for _, n in ipairs({encounterCount, mapCount, partyCount}) do
        if seen[n] == nil then
            seen[n] = true
            entries[#entries + 1] = {
                text = string.format("Refresh Hero Tokens (%d)", n),
                click = function()
                    element.popup = nil
                    HAHeroData.RefreshHeroTokens(token, n)
                end,
            }
        end
    end

    element.popup = gui.ContextMenu{
        styles = ThemeEngine.GetStyles(),
        entries = entries,
    }
end

--- The party's hero tokens, as the character panel's box has them: the
--- coin is its session reset, the count is set by pressing it, the tooltip
--- says what they buy and what changed. The pool is the party's rather than
--- the hero's, so the group watches the shared resource document itself:
--- the card's own monitor never sees it move.
--- @param token token The hero the card is for.
--- @param editable boolean Whether this viewer may change the pool.
--- @return Panel
local function HeroTokensGroup(token, editable)
    local entry = {
        label = "Hero Tokens",
        initial = "",
        apply = function(text)
            HAHeroData.SetHeroTokens(token, tonum(text, -1))
        end,
    }
    local value = EditableStat(token, "", editable, entry)

    --- @param element Panel
    local function Refresh(element)
        if not token.valid or token.properties == nil then
            return
        end
        local text = tostring(token.properties:GetHeroTokens())
        value.text = text
        entry.initial = text
    end

    return gui.Panel{
        classes = {"thc-stat-group"},
        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = Refresh,
        create = Refresh,
        linger = function(element)
            if token.valid and token.properties ~= nil then
                THCWidgets.Tooltip(HAHeroData.HeroTokenTooltip(token.properties))(element)
            end
        end,

        gui.Button{
            classes = {"ha-stat-button", "sizeXs", "thc-tint-fg"},
            icon = HAConstants.iconHeroTokens,
            linger = function(element)
                local encounterCount, mapCount, partyCount = HAHeroData.HeroTokenRefreshCounts()
                local text = "Reset Hero Tokens"
                if encounterCount == mapCount and mapCount == partyCount then
                    text = string.format("Reset Hero Tokens For Session (%d heroes)", encounterCount)
                end
                THCWidgets.Tooltip(text)(element)
            end,
            press = function(element)
                if not editable then
                    return
                end
                RefreshHeroTokens(element, token)
            end,
        },
        value,
    }
end

--- Whether the look-up eye is offered for this creature right now, and how
--- many floors it can look up through: the character panel's own rules.
--- Never for a Director not seeing as a token, never when the game's
--- look-up setting forbids it, and only with floors above, counting those
--- with an opening when the setting says so.
--- @param token token
--- @return boolean offered
--- @return number maxLookup
local function LookupOffer(token)
    if not token.valid then
        return false, 0
    end
    local canLookup = dmhub.GetSettingValue("canlookup")
    if (dmhub.isDM and dmhub.tokenVision == nil)
        or canLookup == "never"
        or (canLookup == "opening" and token.countFloorsWithVisionAbove <= 0)
        or (canLookup == "always" and token.countFloorsAbove <= 0) then
        return false, 0
    end

    local maxLookup
    if canLookup == "always" then
        maxLookup = token.countFloorsAbove
    else
        maxLookup = token.countFloorsWithVisionAbove
    end
    local maxSetting = dmhub.GetSettingValue("maxlookup")
    if maxSetting >= 0 then
        maxLookup = math.min(maxLookup, maxSetting)
    end
    return true, maxLookup
end

--- The look-up eye, as the character panel's. Lit while looking up. A
--- press toggles between forward and up; with more than one floor to look
--- up through it offers each as a menu. Whether it is offered is a matter
--- of settings and of whose eyes a Director is using, none of which is a
--- change to the creature, so it is polled: the button hides and shows
--- itself as the offer comes and goes.
--- @param token token
--- @return Panel
local function LookupButton(token)
    local offered, maxLookup = LookupOffer(token)

    local lookingUp = dmhub.GetSettingValue("lookup") >= 1
    return gui.Button{
        classes = {"ha-tool-button", "sizeXs", lookingUp and "thc-tint-strong" or "thc-tint-muted", (not offered) and "collapsed" or nil},
        icon = HAConstants.iconLookup,
        monitor = "lookup",
        events = {
            monitor = function(element)
                local up = dmhub.GetSettingValue("lookup") >= 1
                element:SetClass("thc-tint-strong", up)
                element:SetClass("thc-tint-muted", not up)
            end,
        },
        thinkTime = 1,
        think = function(element)
            local nowOffered, nowMax = LookupOffer(token)
            maxLookup = nowMax
            element:SetClass("collapsed", not nowOffered)
        end,
        linger = function(element)
            local cur = dmhub.GetSettingValue("lookup")
            local text
            if cur <= 0 then
                text = "Look up"
            elseif maxLookup <= 1 then
                text = "Look forward"
            else
                text = string.format("Up %d / %d (click to cycle)", cur, maxLookup)
            end
            THCWidgets.Tooltip(text)(element)
        end,
        press = function(element)
            local cur = dmhub.GetSettingValue("lookup")
            if maxLookup <= 1 then
                dmhub.SetSettingValue("lookup", (cur >= 1) and 0 or 1)
                return
            end
            if element.popup ~= nil then
                element.popup = nil
                return
            end
            local items = {
                {
                    text = "Forward",
                    click = function()
                        dmhub.SetSettingValue("lookup", 0)
                        element.popup = nil
                    end,
                },
            }
            for i = 1, maxLookup do
                items[#items + 1] = {
                    text = "Up " .. tostring(i),
                    click = function()
                        dmhub.SetSettingValue("lookup", i)
                        element.popup = nil
                    end,
                }
            end
            element.popup = gui.ContextMenu{
                styles = ThemeEngine.GetStyles(),
                entries = items,
            }
        end,
    }
end

--- The card's tool row, as the character panel's portrait column has them:
--- the light toggle, lit in the strong tone while the creature's light is
--- on; the look-up eye when it is offered; the character sheet; and for a
--- Director on a monster, the summoner.
--- @param token token The creature the card is for.
--- @param editable boolean Whether this viewer may act on the creature.
--- @param extra fun(token: token, editable: boolean): Panel[]|nil The host's own buttons, after these.
--- @return Panel[]
local function ToolButtons(token, editable, extra)
    local lightOn = token.properties.selectedLoadout == 1
    local buttons = {
        gui.Button{
            classes = {"ha-tool-button", "sizeXs", lightOn and "thc-tint-strong" or "thc-tint-muted"},
            icon = lightOn and HAConstants.iconLightOn or HAConstants.iconLightOff,
            linger = THCWidgets.Tooltip("Toggle Light"),
            press = function()
                if not editable or not token.valid then
                    return
                end
                creature.ToggleLightSourceOnToken(token)
                game.Refresh{
                    tokens = {token.charid},
                }
            end,
        },
    }

    buttons[#buttons + 1] = LookupButton(token)

    buttons[#buttons + 1] = gui.Button{
        classes = {"ha-tool-button", "sizeXs", "thc-tint-muted"},
        icon = HAConstants.iconCharacterSheet,
        linger = THCWidgets.Tooltip("Open Character Sheet"),
        press = function()
            if not editable or not token.valid then
                return
            end
            token:ShowSheet()
        end,
    }

    --A Director names a monster's summoner, as on the character panel: lit
    --while one is set. The press enters map targeting over every other
    --creature on the map; picking the current summoner clears the link.
    if dmhub.isDM and not token.properties:IsHero() then
        local hasSummoner = token.summonerid ~= nil
        buttons[#buttons + 1] = gui.Button{
            classes = {"ha-tool-button", "sizeXs", hasSummoner and "thc-tint-strong" or "thc-tint-muted"},
            icon = THCWidgets.iconSetCaster,
            linger = function(element)
                local text = "Assign Summoner"
                if token.valid and token.summonerid ~= nil then
                    local summoner = dmhub.GetTokenById(token.summonerid)
                    if summoner ~= nil and summoner.valid then
                        text = string.format("Summoner: %s\nClick to change", summoner.description)
                    end
                end
                THCWidgets.Tooltip(text)(element)
            end,
            press = function(element)
                if not token.valid then
                    return
                end
                local candidates = {}
                for _, tok in ipairs(dmhub.allTokens) do
                    if tok.valid and tok.properties ~= nil and tok.charid ~= token.charid then
                        candidates[#candidates + 1] = tok
                    end
                end
                if #candidates == 0 then
                    THCWidgets.Tooltip("No other creatures on this map to assign as summoner.")(element)
                    return
                end

                local prompt = "Choose this monster's summoner"
                if token.summonerid ~= nil then
                    prompt = "Choose this monster's summoner (pick the current summoner to clear)"
                end
                gamehud.actionBarPanel:FireEventTree("chooseTargetToken", {
                    sourceToken = token,
                    targets = candidates,
                    prompt = prompt,
                    choose = function(summoner)
                        if not token.valid or summoner == nil or not summoner.valid then
                            return
                        end
                        if summoner.charid == token.summonerid then
                            DrawSteelMinion.SetSummoner(token, nil)
                        else
                            DrawSteelMinion.SetSummoner(token, summoner)
                        end
                    end,
                    cancel = function() end,
                })
            end,
        }
    end

    if extra ~= nil then
        for _, button in ipairs(extra(token, editable) or {}) do
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

--- Pooled rather than rebuilt because the card owns a text field: the Director
--- typing a damage amount is holding a panel that a rebuild would delete under
--- the caret. A card that outlives its refresh makes that structural rather
--- than something the refresh has to tiptoe around.
--- @param options {victories: boolean, heroTokens: boolean, tools: boolean, extraTools: fun(token: token, editable: boolean): Panel[], conditions: boolean, canEdit: fun(token: token): boolean}|nil What a host adds to or leaves off the reading, and who may edit; a number, from a pooled list, means the defaults. Without `canEdit`, only a Director edits; `conditions = false` leaves the conditions row off the creature the card is for, its summons keeping theirs.
--- @return Panel
function HACombatTab.CreateCard(options)
    if type(options) ~= "table" then
        options = {}
    end
    local canEdit = options.canEdit or function()
        return dmhub.isDM
    end
    local m_token = nil
    local m_summons = {}

    --Set while a damage or heal box is up, on the hero's bar or a summon's, so
    --a token update does not rebuild the rows and delete the field under the
    --caret. Shared across the group because they rebuild together.
    local m_entryOpen = false
    local function SetEntryOpen(open)
        m_entryOpen = open
    end

    --- The rows that make up one creature's reading, hero or summon alike.
    --- A companion reads as its beastheart does, recoveries, surges and
    --- heroic resource included, since it draws on the beastheart's; any
    --- other summon has none of the three.
    --- @param token token The creature to read.
    --- @param isSummon boolean Drops the add-to-combat button.
    --- @return Panel[] rows
    local function BuildCreatureRows(token, isSummon)
        local creatureProps = token.properties
        local health = THCUtils.Health(creatureProps)
        --Heroes and companions get the hero reading: resources, and
        --movement on a row of its own. A monster, summoned or selected on
        --its own, gets the compact one.
        local heroLike = creatureProps:IsHero() or creatureProps:IsCompanion()
        local editable = canEdit(token) == true

        local resources = nil
        if heroLike then
            local recoveryAmount, recoveriesLeft, recoveriesMax = HAHeroData.Recoveries(creatureProps)
            local heroicIcon, heroicName, heroicValue = HAHeroData.HeroicResource(token)
            local inCombat = THCUtils.InCombat()

            resources = {
                THCWidgets.StatGroup("Recoveries", {
                    gui.Button{
                        classes = {
                            "ha-stat-button",
                            "sizeXs",
                            HAHeroData.RecoveryStatus(recoveriesLeft, recoveriesMax),
                        },
                        icon = HAConstants.iconRecoveries,
                        linger = THCWidgets.Tooltip("Use a recovery"),
                        press = function(element)
                            if not editable then
                                return
                            end
                            SpendRecovery(element, token)
                        end,
                    },
                    THCWidgets.StatValue(string.format("+%d", recoveryAmount)),
                    EditableStat(token, string.format(" %d/%d", recoveriesLeft, recoveriesMax), editable, {
                        label = "# Recoveries",
                        initial = string.format("%d", recoveriesLeft),
                        apply = function(text)
                            HAHeroData.SetRecoveries(token, tonum(text, -1))
                        end,
                    }),
                }),
                EditableGroup("Surges", HAConstants.iconSurges, token, HAHeroData.Surges(creatureProps), editable and inCombat, {
                    label = "Surges",
                    initial = inCombat and HAHeroData.Surges(creatureProps) or "",
                    apply = function(text)
                        HAHeroData.SetSurges(token, tonum(text, -1))
                    end,
                }),
                EditableGroup(heroicName, heroicIcon, token, heroicValue, editable and inCombat, {
                    label = heroicName,
                    initial = inCombat and heroicValue or "",
                    apply = function(text)
                        local n = tonum(text, nil)
                        if n ~= nil then
                            HAHeroData.SetHeroicResource(token, n)
                        end
                    end,
                }),
            }

            --Victories and hero tokens are only for a host that asks. Hero
            --tokens belong to the party, not the hero, and only a hero
            --proper gets them.
        end

        --Speed, disengage, stability and altitude read the same for anything
        --with a token, so they come whole from THCWidgets. A summon has no
        --stat row of its own, so its movement runs on after the
        --characteristics instead. Victories and hero tokens, for a host that
        --asks, lead a hero's movement row; hero tokens belong to the party,
        --not the hero, and only a hero proper gets them.
        --A monster's free strike is a fixed number: read as the character
        --panel's identity strip reads it, and shown only where there is one.
        --On the hero reading it leads the movement row; on the compact one
        --it ends the characteristics row, packed right.
        local freeStrike = nil
        if creatureProps:IsMonster() then
            pcall(function() freeStrike = creatureProps:OpportunityAttack() end)
        end
        local freeStrikeGroup = nil
        if freeStrike ~= nil then
            freeStrikeGroup = THCWidgets.StatGroup("Free Strike", {
                THCWidgets.StatIcon(HAConstants.iconFreeStrike),
                THCWidgets.StatValue(tostring(freeStrike)),
            })
        end

        local movement = {}
        if heroLike and freeStrikeGroup ~= nil then
            movement[#movement + 1] = freeStrikeGroup
        end
        if creatureProps:IsHero() and options.victories then
            local victories = tostring(creatureProps:GetVictories())
            movement[#movement + 1] = EditableGroup("Victories", HAConstants.iconVictories, token, victories, editable, {
                label = "Victories",
                initial = victories,
                apply = function(text)
                    HAHeroData.SetVictories(token, tonum(text, -1))
                end,
            })
        end
        if heroLike and options.heroTokens and creatureProps:IsHero() then
            movement[#movement + 1] = HeroTokensGroup(token, editable)
        end
        for _, group in ipairs(THCWidgets.MovementStats(token, editable)) do
            movement[#movement + 1] = group
        end

        local characteristics = THCWidgets.CharacteristicsRow(creatureProps, (not heroLike) and movement or nil, editable and function(attrId)
            RequestCharacteristicRoll(token, attrId)
        end or nil)

        local rows = {
            gui.Panel{
                classes = {"thc-card-row"},
                THCWidgets.Identity(token),
                THCWidgets.HealthBar(token, health, editable),
                (dmhub.isDM and not isSummon) and THCWidgets.AddToCombatButton(token) or nil,
            },
        }

        --A hero's characteristics share their row with the resources, centered
        --in its right half; then movement has a row of its own.
        if not heroLike then
            if freeStrikeGroup ~= nil then
                rows[#rows + 1] = gui.Panel{
                    classes = {"thc-card-row"},
                    characteristics,
                    gui.Panel{
                        classes = {"ha-row-right"},
                        freeStrikeGroup,
                    },
                }
            else
                rows[#rows + 1] = characteristics
            end
        else
            rows[#rows + 1] = gui.Panel{
                classes = {"thc-card-row"},
                characteristics,
                gui.Panel{
                    classes = {"ha-stat-half"},
                    gui.Panel{
                        classes = {"ha-stat-center"},
                        children = resources,
                    },
                },
            }
            rows[#rows + 1] = gui.Panel{
                classes = {"thc-card-row"},
                children = movement,
            }
        end

        rows[#rows + 1] = THCWidgets.ResistancesRow(creatureProps)
        if isSummon or options.conditions ~= false then
            rows[#rows + 1] = THCWidgets.ConditionsRow(token, editable)
        end

        --For a host that asks, the tool buttons close the card as a row of
        --their own, packed left.
        if (not isSummon) and options.tools then
            rows[#rows + 1] = gui.Panel{
                classes = {"thc-card-row"},
                gui.Panel{
                    classes = {"ha-row-left"},
                    children = ToolButtons(token, editable, options.extraTools),
                },
            }
        end
        return rows
    end

    --- @param summon token
    --- @return Panel[]
    local function BuildSummonRows(summon)
        local rows = BuildCreatureRows(summon, true)
        rows[#rows + 1] = THCWidgets.DamageForm(summon, SetEntryOpen)
        return rows
    end

    --- One summon's block inside its summoner's card. Carries its own monitor,
    --- so its stamina and conditions land without the summoner changing, and
    --- its own form, so the curtain covers the summon rather than the hero.
    --- @param summon token
    --- @return Panel
    local function BuildSummonCard(summon)
        return gui.Panel{
            classes = {"ha-summon-card", THCWidgets.overlayHostClass},

            monitorGame = summon.monitorPath,
            refreshGame = function(element)
                if summon.valid and not m_entryOpen then
                    element.children = BuildSummonRows(summon)
                end
            end,

            children = BuildSummonRows(summon),
        }
    end

    --- The summons block: the arrow in the gutter, and what it folds.
    ---
    --- Horizontal, with the arrow topped rather than centred, so it sits
    --- immediately left of the first summon card and level with it.
    ---
    --- Collapses entirely for a hero with no summons, so every card carries the
    --- block and none has to be built conditionally.
    --- @return Panel
    local function BuildSummons()
        local folded = HACombatTab.SummonsCollapsed(m_token)

        --Read fresh rather than trusting what was bound: changing map takes the
        --summons away before the card is rebound, and a token on its way out
        --answers to `valid` while its properties have already gone.
        local summons = {}
        for _, summon in ipairs(m_summons) do
            if summon ~= nil and summon.valid and summon.properties ~= nil then
                summons[#summons + 1] = summon
            end
        end

        --A lone beastheart companion is a character the Director knows by
        --name; anything else is a crowd.
        local label = "Summons"
        if #summons == 1 and summons[1].properties:IsCompanion() then
            label = THCUtils.TruncateName(summons[1].name)
        end

        local labelPanel = gui.Label{
            classes = {"ha-summons-label", "sizeXxs", "fgMuted", not folded and "collapsed" or nil},
            italics = true,
            text = label,
        }

        local cards = {}
        for _, summon in ipairs(summons) do
            cards[#cards + 1] = BuildSummonCard(summon)
        end

        local cardsPanel = gui.Panel{
            classes = {"ha-summons-cards", folded and "collapsed" or nil},
            children = cards,
        }

        --No classes key of our own when folded: an empty list wipes
        --ExpandoArrow's own theme classes, and with them the glyph's colour and
        --hover. `click`, as the library panels use.
        local arrowArgs = {
            width = HAConstants.summonsArrowSize,
            height = HAConstants.summonsArrowSize,
            halign = "center",
            valign = "center",
            hmargin = 0,
            click = function(element)
                HACombatTab.ToggleSummons(m_token)

                local nowFolded = HACombatTab.SummonsCollapsed(m_token)
                element:SetClass("expanded", not nowFolded)
                labelPanel:SetClass("collapsed", not nowFolded)
                cardsPanel:SetClass("collapsed", nowFolded)
            end,
        }
        if not folded then
            arrowArgs.classes = { "expanded" }
        end

        return gui.Panel{
            classes = {"ha-summons", #summons == 0 and "collapsed" or nil},

            gui.Panel{
                classes = {"ha-summons-gutter"},
                gui.ExpandoArrow(arrowArgs),
            },

            gui.Panel{
                classes = {"ha-summons-body"},
                labelPanel,
                cardsPanel,
            },
        }
    end

    --- The card's rows, read fresh. Rebuilt whole rather than bound field by
    --- field: they are short, and every value is read together.
    --- @return Panel[] rows
    local function BuildRows()
        --The hero's own reading is wrapped so the curtain covers the hero and
        --not the summons hanging beneath them.
        local heroRows = BuildCreatureRows(m_token, false)
        heroRows[#heroRows + 1] = THCWidgets.DamageForm(m_token, SetEntryOpen)

        return {
            gui.Panel{
                classes = {"ha-hero-block", THCWidgets.overlayHostClass},
                children = heroRows,
            },
            BuildSummons(),
        }
    end

    return gui.Panel{
        classes = {"thc-card", "collapsed"},
        --Inline: the active theme rounds panels by default, which would bow the
        --hairline the cards are separated by.
        cornerRadius = 0,

        --Each card watches its own hero the way the character panel watches the
        --selected token, so stamina and conditions land here on their own
        --rather than waiting for the whole list to be rebuilt. Repointed on
        --every bind, because the card outlives the hero in it.
        refreshGame = function(element)
            --Holding off mid-edit: rebuilding would destroy the damage or heal
            --box the Director is typing into. The commit refreshes anyway.
            if m_token ~= nil and m_token.valid and not m_entryOpen then
                element.children = BuildRows()
            end
        end,

        --Folding the summons changes only what is inside this card, so it never
        --reaches the list.
        rebuildRows = function(element)
            if m_token ~= nil and m_token.valid then
                element.children = BuildRows()
            end
        end,

        bindHero = function(element, entry)
            if entry == nil then
                --Parked past the end of the list. The monitor goes with the
                --hero, or a card holding nobody would still wake on their
                --changes, and the rows go too rather than holding a token.
                m_token = nil
                m_summons = {}
                m_entryOpen = false
                element.monitorGame = nil
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            m_token = entry.token
            m_summons = entry.summons or {}
            m_entryOpen = false

            element:SetClass("collapsed", false)
            element:SetClass("thc-card-even", entry.even)
            element:SetClass("thc-card-odd", not entry.even)

            element.monitorGame = m_token.monitorPath
            element.children = BuildRows()
        end,
    }
end


--- Every hero on the board and the summons under them, flattened into the one
--- list the card pool binds against.
---
--- One entry per hero. A summon is not an entry of its own: it is drawn inside
--- its summoner's card, so the pool only ever binds heroes and the zebra never
--- restarts mid-group.
--- @return table[] entries { token, even, summons }
function HACombatTab.CardEntries()
    local entries = {}

    for i, entry in ipairs(HAHeroData.CollectCombatHeroes()) do
        entries[#entries + 1] = {
            token = entry.token,
            even = i % 2 == 0,
            summons = HAHeroData.SummonsFor(entry.token),
        }
    end

    return entries
end

--- The Combat tab: the card list, and the line that stands in for it when there
--- is nobody to show.
--- @return Panel
function HACombatTab.Build()
    local emptyLabel = gui.Label{
        classes = {"thc-empty", "sizeS", "fgMuted", "collapsed"},
        text = "No player-assigned heroes found.",
    }

    local cardList = gui.Panel{
        classes = {"thc-cardlist"},
    }

    return gui.Panel{
        classes = {"ha-tabbody"},
        vscroll = true,

        refreshData = function()
            local entries = HACombatTab.CardEntries()
            emptyLabel:SetClass("collapsed", #entries > 0)
            THCWidgets.BindList(cardList, entries, HACombatTab.CreateCard, "bindHero")
        end,

        create = function(element)
            element:FireEvent("refreshData")
        end,

        emptyLabel,
        cardList,
    }
end
