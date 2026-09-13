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
--- A stat value the Director presses to set, through the card's form. Reads
--- as a plain value otherwise, and for players.
--- @param token token The hero the card is for, which keys the card's form.
--- @param text string The value as printed.
--- @param editable boolean Whether setting it makes sense right now.
--- @param entry {label: string, initial: string, apply: fun(text: string)} What the form opens with.
--- @return Panel
local function EditableStat(token, text, editable, entry)
    editable = editable and dmhub.isDM
    return gui.Label{
        classes = {"thc-stat-value", "sizeXs"},
        text = text,
        hoverCursor = editable and "pressbutton" or nil,
        linger = editable and THCWidgets.Tooltip("Set " .. entry.label) or nil,
        press = editable and function(element)
            local host = element:FindParentWithClass(THCWidgets.overlayHostClass)
            if host ~= nil then
                host:FireEventTree("openOverlay", token, entry)
            end
        end or nil,
    }
end

--- Pooled rather than rebuilt because the card owns a text field: the Director
--- typing a damage amount is holding a panel that a rebuild would delete under
--- the caret. A card that outlives its refresh makes that structural rather
--- than something the refresh has to tiptoe around.
--- @return Panel
function HACombatTab.CreateCard()
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
    --- @param token token The creature to read.
    --- @param isSummon boolean Drops the add-to-combat button.
    --- @return Panel[] rows
    local function BuildCreatureRows(token, isSummon)
        local creatureProps = token.properties
        local health = THCUtils.Health(creatureProps)

        local statChildren = {}

        --A summon has none of the three: no recoveries, no surges, and its
        --heroic resource is its summoner's rather than its own.
        if not isSummon then
            local recoveryAmount, recoveriesLeft, recoveriesMax = HAHeroData.Recoveries(creatureProps)
            local heroicIcon, heroicName, heroicValue = HAHeroData.HeroicResource(token)
            local inCombat = THCUtils.InCombat()

            statChildren = {
                THCWidgets.StatGroup("Recoveries", {
                    gui.Button{
                        classes = {
                            "ha-stat-button",
                            "sizeXs",
                            HAHeroData.RecoveryStatus(recoveriesLeft, recoveriesMax),
                        },
                        icon = HAConstants.iconRecoveries,
                        press = function(element)
                            if not dmhub.isDM then
                                return
                            end
                            SpendRecovery(element, token)
                        end,
                    },
                    THCWidgets.StatValue(string.format("+%d", recoveryAmount)),
                    EditableStat(token, string.format(" %d/%d", recoveriesLeft, recoveriesMax), true, {
                        label = "# Recoveries",
                        initial = string.format("%d", recoveriesLeft),
                        apply = function(text)
                            HAHeroData.SetRecoveries(token, tonum(text, -1))
                        end,
                    }),
                }),
                THCWidgets.StatGroup("Surges", {
                    THCWidgets.StatIcon(HAConstants.iconSurges),
                    EditableStat(token, HAHeroData.Surges(creatureProps), inCombat, {
                        label = "Surges",
                        initial = inCombat and HAHeroData.Surges(creatureProps) or "",
                        apply = function(text)
                            HAHeroData.SetSurges(token, tonum(text, -1))
                        end,
                    }),
                }),
                THCWidgets.StatGroup(heroicName, {
                    THCWidgets.StatIcon(heroicIcon),
                    EditableStat(token, heroicValue, inCombat, {
                        label = heroicName,
                        initial = inCombat and heroicValue or "",
                        apply = function(text)
                            local n = tonum(text, nil)
                            if n ~= nil then
                                HAHeroData.SetHeroicResource(token, n)
                            end
                        end,
                    }),
                }),
            }
        end

        --Speed, disengage, stability and altitude read the same for anything
        --with a token, so they come whole from THCWidgets.
        for _, group in ipairs(THCWidgets.MovementStats(token)) do
            statChildren[#statChildren + 1] = group
        end

        return {
            gui.Panel{
                classes = {"thc-card-row"},
                gui.Panel{
                    classes = {"thc-card-identity"},
                    gui.CreateTokenImage(token, {
                        classes = {"thc-card-token"},
                        halign = "left",
                        valign = "center",
                    }),
                    gui.Label{
                        classes = {"thc-card-name", "bold", "sizeXs"},
                        text = THCUtils.TruncateName(token.name),
                    },
                },
                THCWidgets.HealthBar(token, health),
                (dmhub.isDM and not isSummon) and THCWidgets.AddToCombatButton(token) or nil,
            },

            THCWidgets.ResistancesRow(creatureProps),

            THCWidgets.CharacteristicsRow(creatureProps),

            gui.Panel{
                classes = {"thc-card-row"},
                children = statChildren,
            },

            THCWidgets.ConditionsRow(token),
        }
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
