local mod = dmhub.GetModLoading()

--- The Combat tab: one compact card per hero, with stamina, the movement and
--- recovery numbers, and their conditions.
--- @class HACombatTab: GameType
HACombatTab = RegisterGameType("HACombatTab")

--- A small glyph beside a number.
--- @param icon string Image path.
--- @return Panel
local function StatIcon(icon)
    return gui.Panel{
        classes = {"ha-stat-icon", "bgInverse"},
        bgimage = icon,
    }
end

--- @param text string The value to print.
--- @return Panel
local function StatValue(text)
    return gui.Label{
        classes = {"ha-stat-value", "sizeXs"},
        text = text,
    }
end

--- One stat: its glyph, its value, and a tooltip naming it. The row is icons
--- and bare numbers, so the tooltip is the only thing that says which is which.
--- @param tooltip string What this stat is called.
--- @param children Panel[] The glyph and value panels, in order.
--- @return Panel
local function StatGroup(tooltip, children)
    return gui.Panel{
        classes = {"ha-stat-group"},
        linger = function(element)
            gui.Tooltip{
                text = tooltip,
                fontSize = HAConstants.tooltipFontSize,
            }(element)
        end,
        children = children,
    }
end

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

--- The compact stamina bar. Rebuilt rather than reusing TacPanel.HealthBar,
--- which is fixed at 90% width with its own hover-reveal adjust controls.
---
--- A Director gets a minus and a plus tucked into the ends of the bar; either
--- opens a box over the reading that applies damage or healing on enter or on
--- clicking away. `setEntryOpen` tells the card to hold off rebuilding while
--- that box is up, or a token update would delete it under the caret.
--- @param token token The hero's token.
--- @param health table As produced by HAHeroData.Health.
--- @param setEntryOpen fun(open: boolean) Reports whether an edit is in progress.
--- @return Panel
local function BuildHealthBar(token, health, setEntryOpen)
    local stateClass = nil
    local borderClass = "borderSuccess"
    if health.dying or health.dead then
        stateClass = "ha-dying"
        borderClass = "borderDanger"
    elseif health.winded then
        stateClass = "ha-winded"
        borderClass = "borderWarning"
    end

    --"fg", like the character panel's reading: the fill already carries the
    --status colour, so anything drawn over it stays neutral.
    local label = gui.Label{
        classes = {"ha-health-label", "sizeXxs", "bold", "fg"},
        floating = true,
        text = health.text,
    }

    local children = {
        gui.Panel{
            classes = {"fillBarFill", "ha-health-fill", stateClass},
            width = string.format("%f%%-2", health.ratio * 100),
            cornerRadius = 0,
        },
        label,
    }

    if dmhub.isDM then
        local m_mode = nil
        local m_focused = false
        local entryInput

        local function CloseEntry()
            if m_mode == nil then
                return
            end
            m_mode = nil
            setEntryOpen(false)
            entryInput:SetClass("collapsed", true)
            label:SetClass("collapsed", false)
        end

        local function ApplyValue(mode, text)
            local amount = tonum(text, 0)
            if mode == nil or amount <= 0 then
                return
            end
            if not token.valid or token.properties == nil then
                return
            end

            if mode == "harm" then
                token:ModifyProperties{
                    description = "Apply Damage",
                    execute = function()
                        --The string, not the number: TakeDamage takes a formula.
                        token.properties:TakeDamage(text)
                    end,
                }
            else
                token:ModifyProperties{
                    description = "Apply Healing",
                    execute = function()
                        token.properties:Heal(amount)
                    end,
                }
            end
        end

        local function OpenEntry(mode)
            m_mode = mode
            setEntryOpen(true)
            entryInput.text = ""
            entryInput:SetClass("collapsed", false)
            label:SetClass("collapsed", true)

            --A frame later: the field is still collapsed as far as the engine
            --is concerned right now, so focusing it here does not stick.
            m_focused = false
            dmhub.Schedule(0.01, function()
                if mod.unloaded then return end
                if m_mode ~= nil and entryInput.valid then
                    gui.SetFocus(entryInput)
                end
            end)
        end

        entryInput = gui.Input{
            classes = {"ha-health-entry", "sizeXxs", "collapsed"},
            text = "",
            --Blank, not the default "Enter text...", which is far wider than
            --the field and would spill across the bar.
            placeholderText = "",
            characterLimit = 5,
            selectAllOnFocus = true,
            hoverCursor = "text",
            floating = true,
            escapePriority = EscapePriority.EXIT_DIALOG,

            escape = function()
                CloseEntry()
                gui.SetFocus(nil)
            end,

            focus = function()
                m_focused = true
            end,

            defocus = function()
                --Only a real focus loss closes the box: the defocus that fires
                --while it is still opening would shut it again immediately.
                if not m_focused then return end
                m_focused = false

                --Deferred a frame, because clicking INSIDE the box to move the
                --caret defocuses and refocuses, which would close it out from
                --under the pointer.
                dmhub.Schedule(0.01, function()
                    if mod.unloaded then return end
                    if not entryInput.valid then return end
                    if m_focused or m_mode == nil then return end
                    CloseEntry()
                end)
            end,

            change = function(element)
                --Read before closing: change fires on focus loss too, and
                --closing clears the mode the value needs.
                local mode = m_mode
                local text = element.text
                CloseEntry()
                ApplyValue(mode, text)
            end,
        }

        --Neither is offered where it would do nothing: no damage to a hero who
        --is already dead, no healing for one already whole. Built only when
        --wanted, not built and then withheld -- an unparented panel warns.
        if not health.dead then
            children[#children + 1] = gui.Button{
                classes = {"ha-health-adjust", "ha-health-left", "sizeXxs", "ha-tint-fg"},
                icon = HAConstants.iconHarm,
                floating = true,
                press = function()
                    OpenEntry("harm")
                end,
                linger = function(element)
                    gui.Tooltip{
                        text = "Apply Damage",
                        fontSize = HAConstants.tooltipFontSize,
                    }(element)
                end,
            }
        end

        if health.current < health.max then
            children[#children + 1] = gui.Button{
                classes = {"ha-health-adjust", "ha-health-right", "sizeXxs", "ha-tint-fg"},
                icon = HAConstants.iconHeal,
                floating = true,
                press = function()
                    OpenEntry("heal")
                end,
                linger = function(element)
                    gui.Tooltip{
                        text = "Apply Healing",
                        fontSize = HAConstants.tooltipFontSize,
                    }(element)
                end,
            }
        end

        children[#children + 1] = entryInput
    end

    return gui.Panel{
        classes = {"ha-health", "bordered", borderClass},
        --The frame is the border; a filled surface behind the bar would hide
        --where the fill ends.
        bgcolor = "clear",
        --Inline, on both the frame and the fill: the active theme rounds panels
        --by default, and a rule of ours only ties with it.
        cornerRadius = 0,
        children = children,
    }
end

--- Pull one hero into a fight already in progress. Director-only, and only for
--- a hero currently sitting it out.
---
--- The engine's rollinitiative command takes no token and acts on the current
--- selection, so the only way to aim it at one hero is to select them. The
--- Director's own selection is saved and put back afterwards, on a scheduled
--- event rather than inline: the command may not read the selection until the
--- frame settles, and restoring too early would aim it at nobody.
---
--- Visibility is polled rather than rebuilt with the card: `_tmp_initiativeStatus`
--- is not something the token monitor reports, so joining or leaving a fight
--- leaves the card untouched and the sword would sit there having already
--- worked. "danger", not "bgDanger" -- the latter sets bgimage and swallows
--- the icon.
--- @param token token The hero's token.
--- @return Panel
local function BuildAddToCombatButton(token)
    return gui.Button{
        classes = {"ha-addcombat", "sizeXs", "ha-tint-danger", "withDanger", "collapsed"},
        icon = HAConstants.iconAddToCombat,

        thinkTime = 0.5,
        think = function(element)
            element:SetClass("collapsed", not HAHeroData.CanAddToCombat(token.properties))
        end,
        create = function(element)
            element:FireEvent("think")
        end,

        linger = function(element)
            gui.Tooltip{
                text = "Add to Combat",
                fontSize = HAConstants.tooltipFontSize,
            }(element)
        end,
        press = function(element)
            local restore = {}
            for _, selected in ipairs(dmhub.selectedTokens) do
                restore[#restore + 1] = selected
            end
            element.data.restoreSelection = restore

            dmhub.selectedTokens = {token}
            Commands.rollinitiative()

            element:ScheduleEvent("restoreSelection", 0.1)
        end,
        restoreSelection = function(element)
            dmhub.selectedTokens = element.data.restoreSelection or {}
            element.data.restoreSelection = nil
        end,
    }
end

--- Point a caster-tracking condition at whoever inflicted it, by running the
--- standard SetConditionCaster ability so the Director picks the creature on
--- the map. The invoking latch mirrors the character panel's: the ability is
--- a prompt, and a second press while the first is still resolving would stack
--- two pickers on one condition.
--- @param token token The hero carrying the condition.
--- @param condid string The condition to set a caster on.
--- @return Panel
local function BuildSetCasterButton(token, condid)
    return gui.Button{
        classes = {"ha-chip-setcaster", "sizeXxs"},
        icon = HAConstants.iconSetCaster,
        data = { invoking = false, invokeReady = false },

        press = function(element)
            if element.data.invoking or gamehud.actionBarPanel.data.IsCastingSpell() then
                return
            end
            element.data.invoking = true
            element.thinkTime = 0.1

            local ability = DeepCopy(MCDMUtils.GetStandardAbility("SetConditionCaster"))
            ability.behaviors[1].condid = condid
            ability.OnFinishCast = function()
                element.data.invoking = false
                element.thinkTime = nil
            end
            ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, ability, token, "prompt", {}, {})
        end,

        think = function(element)
            if element.data.invoking and element.data.invokeReady then
                if not gamehud.actionBarPanel.data.IsCastingSpell()
                    and not gamehud.rollDialog.data.IsShown() then
                    element.data.invoking = false
                    element.data.invokeReady = false
                    element.thinkTime = nil
                end
            elseif element.data.invoking then
                element.data.invokeReady = true
            end
        end,

        linger = function(element)
            gui.Tooltip{
                text = "Set Caster",
                fontSize = HAConstants.tooltipFontSize,
            }(element)
        end,
    }
end

--- Weaknesses then immunities as chips, tinted to tell the two apart. The whole
--- row collapses when the hero has neither.
--- @param hero character The hero to read.
--- @return Panel
local function BuildResistancesRow(hero)
    local entries = HAHeroData.Resistances(hero)

    local chips = {}
    for _, resistance in ipairs(entries) do
        chips[#chips + 1] = HADockPanel.Chip{
            label = resistance.label,
            --Outlined rather than filled: a row of solid blocks shouts louder
            --than the conditions beneath it, which matter more.
            extraClasses = resistance.weakness
                and {"borderWarning"}
                or {"borderSuccess"},
        }
    end

    return gui.Panel{
        classes = {"ha-chips", #chips == 0 and "collapsed" or nil},
        wrap = true,
        children = chips,
    }
end

--- The conditions strip: an add button for Directors, then one chip each.
--- Players see the chips without the add button or the remove glyphs.
--- @param token token The hero's token.
--- @return Panel
local function BuildConditionsRow(token)
    local isDirector = dmhub.isDM

    local children = {}

    if isDirector then
        children[#children + 1] = gui.Button{
            classes = {"addButton", "sizeXs", "ha-chip-add"},
            press = function(element)
                TacPanel.AddConditionMenu{
                    tokens = {token},
                    button = element,
                }
            end,
            linger = function(element)
                gui.Tooltip("Add a condition")(element)
            end,
        }
    end

    for _, cond in ipairs(HAHeroData.Conditions(token.properties)) do
        local onRemove = nil
        if isDirector then
            onRemove = function()
                token:ModifyProperties{
                    description = "Remove Condition",
                    execute = function()
                        if cond.kind == "custom" then
                            local customConditions = token.properties:get_or_add("customConditions", {})
                            customConditions[cond.key] = nil
                        else
                            token.properties:InflictCondition(cond.key, {purge = true})
                        end
                    end,
                }
            end
        end

        local extraChildren = nil
        if isDirector and cond.canSetCaster then
            extraChildren = {BuildSetCasterButton(token, cond.key)}
        end

        children[#children + 1] = HADockPanel.Chip{
            label = cond.label,
            tooltip = cond.tooltip,
            icon = cond.icon,
            iconColor = cond.iconColor,
            iconHueshift = cond.iconHueshift,
            onRemove = onRemove,
            extraChildren = extraChildren,
        }
    end

    --Only the add button present, so this hero has nothing on them.
    if #children == (isDirector and 1 or 0) then
        children[#children + 1] = gui.Label{
            classes = {"ha-chip-label", "sizeXxs", "fgMuted"},
            italics = true,
            text = "No conditions",
        }
    end

    return gui.Panel{
        classes = {"ha-chips"},
        wrap = true,
        children = children,
    }
end

--- Build one hero's card.
--- @param entry table { token=token, hero=character, name=string }
--- @param index number 1-based position, which picks the zebra stripe.
--- @return Panel
function HACombatTab.BuildCard(entry, index)
    local token = entry.token

    --Set while a damage or heal box is up, so a token update does not rebuild
    --the card and delete the field under the caret.
    local m_entryOpen = false
    local function SetEntryOpen(open)
        m_entryOpen = open
    end

    --- The card's three rows, read fresh. Rebuilt whole rather than bound
    --- field by field: they are short, and every value is read together.
    --- @return Panel[] rows
    local function BuildRows()
        local hero = token.properties

        local health = HAHeroData.Health(hero)
        local recoveryAmount, recoveriesLeft, recoveriesMax = HAHeroData.Recoveries(hero)
        local speed, restricted, currentSpeed = HAHeroData.Speed(hero)
        local moveType, altitude = HAHeroData.Movement(token)
        local heroicIcon, heroicName, heroicValue = HAHeroData.HeroicResource(hero)

        local statChildren = {
            StatGroup("Recoveries", {
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
                StatValue(string.format("+%d", recoveryAmount)),
                StatValue(string.format(" %d/%d", recoveriesLeft, recoveriesMax)),
            }),
            StatGroup("Surges", {
                StatIcon(HAConstants.iconSurges),
                StatValue(HAHeroData.Surges(hero)),
            }),
            StatGroup(heroicName, {
                StatIcon(heroicIcon),
                StatValue(heroicValue),
            }),
            StatGroup("Speed", {
                StatIcon(HAConstants.iconSpeed),
                StatValue(restricted and string.format("%d (%d)", speed, currentSpeed) or tostring(speed)),
            }),
            StatGroup("Disengage", {
                StatIcon(HAConstants.iconDisengage),
                StatValue(tostring(HAHeroData.Disengage(hero))),
            }),
            StatGroup("Stability", {
                StatIcon(HAConstants.iconStability),
                StatValue(tostring(HAHeroData.Stability(hero))),
            }),
        }

        --Altitude only; which mode it is comes through the glyph and its tooltip.
        if moveType ~= nil then
            statChildren[#statChildren + 1] = StatGroup(moveType.label, {
                StatIcon(moveType.icon),
                StatValue(tostring(altitude)),
            })
        end

        return {
            gui.Panel{
                classes = {"ha-card-row"},
                gui.Panel{
                    classes = {"ha-card-identity"},
                    gui.CreateTokenImage(token, {
                        classes = {"ha-card-token"},
                        halign = "left",
                        valign = "center",
                    }),
                    gui.Label{
                        classes = {"ha-card-name", "bold", "sizeXs"},
                        text = HAHeroData.TruncateName(token.name),
                    },
                },
                BuildHealthBar(token, health, SetEntryOpen),
                dmhub.isDM and BuildAddToCombatButton(token) or nil,
            },

            BuildResistancesRow(hero),

            gui.Panel{
                classes = {"ha-card-row"},
                children = statChildren,
            },

            BuildConditionsRow(token),
        }
    end

    local stripe = index % 2 == 0 and "ha-card-even" or "ha-card-odd"

    return gui.Panel{
        classes = {"ha-card", stripe},
        --Inline: the active theme rounds panels by default, which would bow the
        --hairline the cards are separated by.
        cornerRadius = 0,

        --Each card watches its own hero the way the character panel watches the
        --selected token, so stamina and conditions land here on their own
        --rather than waiting for the whole panel to be rebuilt.
        monitorGame = token.monitorPath,
        refreshGame = function(element)
            --Holding off mid-edit: rebuilding would destroy the damage or heal
            --box the Director is typing into. The commit refreshes anyway.
            if token.valid and not m_entryOpen then
                element.children = BuildRows()
            end
        end,

        children = BuildRows(),
    }
end

--- Every hero card, alphabetical.
--- @return Panel[] cards
function HACombatTab.BuildCards()
    local entries = HAHeroData.CollectHeroes()

    if #entries == 0 then
        return {
            gui.Label{
                classes = {"ha-empty", "sizeS", "fgMuted"},
                text = "No player-assigned heroes found.",
            },
        }
    end

    local cards = {}
    for i, entry in ipairs(entries) do
        cards[#cards + 1] = HACombatTab.BuildCard(entry, i)
    end
    return cards
end
