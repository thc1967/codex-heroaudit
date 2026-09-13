local mod = dmhub.GetModLoading()

--- The dockable Hero Audit panel: a tab bar over the Combat and Exploration
--- tabs.
--- @class HADockPanel: GameType
HADockPanel = RegisterGameType("HADockPanel")

--- Which heroes the combat tab is showing, as a comparable string, so it is
--- only rebuilt when that set changes rather than on every object update. It
--- tracks placement and combat membership, neither of which is an object change
--- any monitor path reports.
--- @return string signature
local function RosterSignature()
    local ids = {}
    for _, entry in ipairs(HAHeroData.CollectCombatHeroes()) do
        ids[#ids + 1] = entry.token.charid
        --Summons too, or one being placed or dismissed would not bring the
        --card list back.
        for _, summon in ipairs(HAHeroData.SummonsFor(entry.token)) do
            ids[#ids + 1] = summon.charid
        end
    end
    return table.concat(ids, ",")
end

--- Build the panel handed to DockablePanel.
--- @return Panel root
function HADockPanel.Build()
    local m_tab = HAConstants.tabCombat
    local m_roster = RosterSignature()
    local m_dirty = false

    --The cards are assembled from THCWidgets, so their geometry rides in from
    --there and is spliced ahead of ours.
    local styles = THCWidgets.Styles(
        THCWidgets.chipStyles,
        THCWidgets.statStyles,
        THCWidgets.healthStyles,
        THCWidgets.headerStyles,
        THCWidgets.cardStyles,
        HAConstants.styles)

    --Both tabs are built whole by their own file: the combat tab owns the card
    --pool, and the exploration tab the filter its sections are read under.
    local combatBody = HACombatTab.Build()
    local explorationBody = HAExplorationTab.Build()

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
        styles = ThemeEngine.MergeStyles(styles),

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
                    element.styles = ThemeEngine.MergeStyles(styles)
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
