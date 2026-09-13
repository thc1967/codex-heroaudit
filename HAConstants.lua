local mod = dmhub.GetModLoading()

--- Sizing, icon paths and the geometry styles shared by the Hero Audit dock
--- panel and its two tabs.
--- @class HAConstants: GameType
HAConstants = RegisterGameType("HAConstants")

HAConstants.panelName = "Hero Audit"
HAConstants.icon = "phosphor/list-magnifying-glass.png"

--- Stands in wherever the intended icon has not been identified yet.
HAConstants.iconPlaceholder = "phosphor/seal-question-light.png"

HAConstants.iconRecoveries = "phosphor/heartbeat-light.png"
HAConstants.iconSurges = "phosphor/lightning-light.png"

--- The indent a hero's summons sit in, and the arrow that folds them away. The
--- arrow is sized here rather than in the builder because the themed {triangle}
--- carries its own size and has to be overridden inline at construction.
HAConstants.summonsGutterWidth = 14
HAConstants.summonsArrowSize = 10

--- The band at the top of the summons block that the arrow and the folded
--- label each centre themselves in, so the two sit level with each other.
HAConstants.summonsRowHeight = 16

HAConstants.tabCombat = "combat"
HAConstants.tabExploration = "exploration"

--- The themed {tab} class is sized for a full-page tab bar; these shrink it.
HAConstants.tabWidth = 80
HAConstants.tabHeight = 20
HAConstants.tabFontSize = 12

--- Surges and heroic resources only exist in combat; this stands in otherwise.
HAConstants.notInCombat = "-"

HAConstants.iconFilter = "phosphor/funnel-fill.png"

--- Which heroes the Exploration tab aggregates over. The order here is the
--- order of the menu, and the first is the opening default.
HAConstants.filterAssigned = "assigned"
HAConstants.filterParty = "party"
HAConstants.filterMap = "map"
HAConstants.filterAll = "all"

HAConstants.explorationFilters = {
    {
        id = HAConstants.filterAssigned,
        text = "Heroes assigned to players",
    },
    --textFormat, not text: the party's own name is filled in at display time,
    --so renaming it renames the filter.
    {
        id = HAConstants.filterParty,
        textFormat = "Heroes in the %s party",
    },
    {
        id = HAConstants.filterMap,
        text = "Heroes on the map",
    },
    {
        id = HAConstants.filterAll,
        text = "All Heroes",
        dmOnly = true,
    },
}

--- A context menu of ours is a short list of short phrases, so it does not want
--- the full-size menu type. `priority` rather than a fourth selector: the
--- theme's own rule is {label, contextMenuLabel} and a copy would only tie.
HAConstants.menuStyles = {
    {
        selectors = {"label", "contextMenuLabel"},
        priority = 100,
        fontSize = 11,
    },
}

--[[
    Geometry-only layout table, merged with ThemeEngine.GetStyles() at the dock
    root. Appearance comes from theme classes; this table carries only positions
    and sizes. `floating` is never set here -- it has to be inlined at the
    construction site.
]]
HAConstants.styles = {
    {
        selectors = {"ha-root"},
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    --No ha-tabbar/ha-tab rules: {tabBar} and {tab} are complete themed styles,
    --and a rule of ours would collide with them at equal specificity. The tabs
    --are shrunk inline at the construction site instead.
    {
        selectors = {"ha-tabbody"},
        width = "100%",
        height = "100%-26",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },

    --The summons block sits inside the summoner's card: the arrow in a gutter
    --on the left, everything it folds to the right of it.
    {
        selectors = {"ha-hero-block"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"ha-summons"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tpad = 2,
    },
    {
        selectors = {"ha-summons-gutter"},
        width = HAConstants.summonsGutterWidth,
        height = HAConstants.summonsRowHeight,
        flow = "none",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"ha-summons-body"},
        width = string.format("100%%-%d", HAConstants.summonsGutterWidth),
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"ha-summons-cards"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"ha-summon-card"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        tpad = 3,
        bgimage = true,
        bgcolor = "clear",
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
        borderColor = "@border",
    },
    {
        selectors = {"ha-summons-label"},
        width = "100%",
        height = HAConstants.summonsRowHeight,
        halign = "left",
        valign = "top",
        textAlignment = "left",
    },
    {
        selectors = {"ha-stat-button"},
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        hmargin = 2,
    },
    --The right half of the characteristics row, with a hero's resources
    --centered in it as one left-packed run.
    {
        selectors = {"ha-stat-half"},
        width = "50%",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
    },
    {
        selectors = {"ha-stat-center"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        valign = "center",
    },
    {
        selectors = {"ha-section"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    },

    --[[ Exploration tab ]]
    {
        selectors = {"ha-heading"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 6,
        bmargin = 2,
        textAlignment = "left",
    },
}
