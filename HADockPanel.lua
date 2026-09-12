local mod = dmhub.GetModLoading()

--- The dockable Hero Audit panel: a tab bar over the Combat and Exploration
--- tabs, and the chip both tabs are built from.
--- @class HADockPanel: GameType
HADockPanel = RegisterGameType("HADockPanel")

--- A small bordered pill: optional icon, a label, and a remove glyph when the
--- caller supplies a handler. Shared by conditions, languages and skills so all
--- three read as one control.
--- @param args table { label, tooltip?, icon?, iconColor?, iconHueshift?, onRemove?, extraClasses?, extraChildren? }
--- @return Panel
function HADockPanel.Chip(args)
    local children = {}

    if args.icon ~= nil then
        children[#children + 1] = gui.Panel{
            classes = {"ha-chip-icon"},
            bgimage = args.icon,
            bgcolor = args.iconColor or "white",
            hueshift = args.iconHueshift or 0,
        }
    end

    children[#children + 1] = gui.Label{
        classes = {"ha-chip-label", "sizeXxs"},
        text = args.label,
    }

    --Between the label and the remove glyph, so removing stays the rightmost
    --thing on every chip.
    for _, child in ipairs(args.extraChildren or {}) do
        children[#children + 1] = child
    end

    if args.onRemove ~= nil then
        children[#children + 1] = gui.Panel{
            classes = {"ha-chip-remove"},
            hoverCursor = "pressbutton",
            press = function()
                args.onRemove()
            end,
            linger = function(element)
                gui.Tooltip{
                    text = "Remove",
                    fontSize = HAConstants.tooltipFontSize,
                }(element)
            end,

            gui.Label{
                classes = {"ha-chip-remove-x", "sizeXxs"},
                text = "X",
            },
        }
    end

    local classes = {"ha-chip", "bordered"}
    for _, class in ipairs(args.extraClasses or {}) do
        classes[#classes + 1] = class
    end

    return gui.Panel{
        classes = classes,
        --Inline: the active theme rounds panels by default, and a rule of ours
        --only ties with it.
        cornerRadius = 0,
        --Every chip tooltip is the small one: a condition's description is the
        --longest text on the panel and at body size it swamps the window.
        linger = args.tooltip ~= nil and function(element)
            gui.Tooltip{
                text = args.tooltip,
                fontSize = HAConstants.tooltipFontSize,
            }(element)
        end or nil,
        children = children,
    }
end

--- Which heroes are on show, as a comparable string, so the combat tab is only
--- rebuilt when the party itself changes rather than on every object update.
--- @return string signature
local function RosterSignature()
    local ids = {}
    for _, entry in ipairs(HAHeroData.CollectHeroes()) do
        ids[#ids + 1] = entry.token.charid
    end
    return table.concat(ids, ",")
end

--- Build the panel handed to DockablePanel.
--- @return Panel root
function HADockPanel.Build()
    local m_tab = HAConstants.tabCombat
    local m_roster = RosterSignature()
    local m_dirty = false

    local combatBody = gui.Panel{
        classes = {"ha-tabbody"},
        vscroll = true,
        refreshData = function(element)
            element.children = HACombatTab.BuildCards()
        end,
        children = HACombatTab.BuildCards(),
    }

    local explorationBody = gui.Panel{
        classes = {"ha-tabbody"},
        vscroll = true,
        refreshData = function(element)
            element.children = HAExplorationTab.BuildSections()
        end,
        children = HAExplorationTab.BuildSections(),
    }

    --Assigned below; the press handlers close over them and only run later.
    local combatTab
    local explorationTab

    local function ApplyTab()
        combatTab:SetClass("selected", m_tab == HAConstants.tabCombat)
        explorationTab:SetClass("selected", m_tab == HAConstants.tabExploration)
        combatBody:SetClass("collapsed", m_tab ~= HAConstants.tabCombat)
        explorationBody:SetClass("collapsed", m_tab ~= HAConstants.tabExploration)

        --Catches up whatever it missed while hidden.
        if m_tab == HAConstants.tabExploration then
            explorationBody:FireEvent("refreshData")
        end
    end

    --A themed {tab} is a label, not a button, and carries its own full size
    --(130x40 at fontSize 18). Shrinking it has to be inline: a rule of ours
    --would tie with the theme's rather than beat it.
    --- @param text string Tab caption.
    --- @param id string The HAConstants tab id this selects.
    --- @return Panel
    local function MakeTab(text, id)
        return gui.Label{
            classes = {"tab"},
            text = text,
            width = HAConstants.tabWidth,
            height = HAConstants.tabHeight,
            fontSize = HAConstants.tabFontSize,
            --{tab} sets no alignment, so in a horizontal flow the pair would
            --centre itself in the bar.
            halign = "left",
            hoverCursor = "pressbutton",
            press = function()
                m_tab = id
                ApplyTab()
            end,
        }
    end

    combatTab = MakeTab("Combat", HAConstants.tabCombat)
    explorationTab = MakeTab("Exploration", HAConstants.tabExploration)

    local themeSub

    return gui.Panel{
        classes = {"ha-root"},
        styles = ThemeEngine.MergeStyles(HAConstants.styles),

        --Stamina and conditions arrive through each card's own token monitor.
        --This one is for the aggregates, which no single token owns. Debounced,
        --because an object burst would otherwise rebuild a tab several times in
        --one frame.
        monitorGame = dmhub.activeObjectsPath,
        refreshGame = function(element)
            if not m_dirty then
                m_dirty = true
                element:ScheduleEvent("rebuildTabs", 0.3)
            end
        end,

        rebuildTabs = function(element)
            m_dirty = false
            --Skipped while hidden; switching to the tab rebuilds it anyway.
            if m_tab == HAConstants.tabExploration then
                explorationBody:FireEvent("refreshData")
            end
        end,

        --Who counts as a hero is not an object change any one path reports:
        --assigning a token to a player rewrites its owner, and the active-object
        --monitor above never fires. Polling the roster is cheap -- a handful of
        --tokens, once a second -- and catches every way the party can change.
        thinkTime = 1,
        think = function(element)
            local roster = RosterSignature()
            if roster == m_roster then
                return
            end

            m_roster = roster
            combatBody:FireEvent("refreshData")
            if m_tab == HAConstants.tabExploration then
                explorationBody:FireEvent("refreshData")
            end
        end,

        create = function(element)
            themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(HAConstants.styles)
                end
            end)
            ApplyTab()
        end,

        destroy = function()
            if themeSub ~= nil then
                themeSub:Deregister()
                themeSub = nil
            end
        end,

        --{tabBar} centres itself and sizes to its tabs; the dock wants the row
        --full-width and left-aligned, which is inline for the same reason.
        gui.Panel{
            classes = {"tabBar"},
            width = "100%",
            halign = "left",
            combatTab,
            explorationTab,
        },

        combatBody,
        explorationBody,
    }
end

--Reads HAConstants at file scope, which is safe only because the mod loads it
--first; keep this file last if the file order is ever changed.
DockablePanel.Register{
    name = HAConstants.panelName,
    icon = HAConstants.icon,
    minHeight = 120,
    maxHeight = 800,
    content = function()
        return HADockPanel.Build()
    end,
}
