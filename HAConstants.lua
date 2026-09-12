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
HAConstants.iconAddToCombat = "phosphor/sword-light.png"
HAConstants.iconSetCaster = "icons/icon_app/icon_app_4.png"
HAConstants.iconHarm = "phosphor/minus-circle-light.png"
HAConstants.iconHeal = "phosphor/plus-circle-light.png"
HAConstants.iconSpeed = "phosphor/sneaker-move.png"
HAConstants.iconStability = "phosphor/anchor.png"
HAConstants.iconDisengage = "90af1d38-c00f-4aaa-b671-ba0a49c3ef49"

--- How each off-the-ground movement mode reads. Keyed by what
--- `CurrentMoveType()` returns; anything absent leaves the row off entirely.
HAConstants.moveTypes = {
    fly = {
        label = "Flying",
        icon = "phosphor/feather-light.png",
    },
    climb = {
        label = "Climbing",
        icon = "phosphor/ladder-simple.png",
    },
    burrow = {
        label = "Burrowing",
        icon = "phosphor/shovel-light.png",
    },
}

HAConstants.nameMaxChars = 24

HAConstants.tabCombat = "combat"
HAConstants.tabExploration = "exploration"

--- The themed {tab} class is sized for a full-page tab bar; these shrink it.
HAConstants.tabWidth = 80
HAConstants.tabHeight = 20
HAConstants.tabFontSize = 12

--- Tooltips default to body size, which is far too loud for a list of names.
HAConstants.tooltipFontSize = 10

--- Surges and heroic resources only exist in combat; this stands in otherwise.
HAConstants.notInCombat = "-"

HAConstants.iconFilter = "phosphor/funnel-light.png"

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

--- The stamina history tooltip re-roots out of the panel, so it carries its own
--- cascade. Rows are tinted by composing a status class over these.
HAConstants.historyStyles = {
    {
        selectors = {"ha-history"},
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        pad = 4,
    },
    {
        selectors = {"label", "ha-history-row"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        textAlignment = "left",
        fontSize = 10,
        vmargin = 1,
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
    {
        selectors = {"ha-empty"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    },

    --[[ Combat tab ]]
    --Cards butt up against each other, separated by a hairline on the bottom
    --edge rather than by a gap.
    {
        selectors = {"ha-card"},
        width = "100%-8",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vmargin = 0,
        hpad = 4,
        vpad = 4,
        bgimage = true,
        border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
        borderColor = "@border",
    },
    {
        selectors = {"ha-card", "ha-card-even"},
        bgcolor = "@bg",
    },
    {
        selectors = {"ha-card", "ha-card-odd"},
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"ha-card-row"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        vmargin = 1,
    },
    --Token and name share the left half of the row, the stamina bar the right.
    {
        selectors = {"ha-card-identity"},
        width = "50%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
    },
    {
        selectors = {"ha-card-token"},
        width = 22,
        height = 22,
        halign = "left",
        valign = "center",
    },
    {
        selectors = {"ha-card-name"},
        width = "100%-26",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        textAlignment = "left",
    },
    {
        selectors = {"ha-stat-icon"},
        width = 12,
        height = 12,
        halign = "left",
        valign = "center",
        hmargin = 2,
    },
    --Icon and value travel together in a group, which owns the gap to the next
    --pair and carries the tooltip naming the stat.
    {
        selectors = {"ha-stat-group"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        rmargin = 10,
    },
    {
        selectors = {"ha-stat-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textAlignment = "left",
    },

    --[[ Health bar. Fill and label are stacked, so the bar itself has no flow. ]]
    {
        selectors = {"ha-health"},
        width = "50%-30",
        height = 13,
        flow = "none",
        halign = "left",
        valign = "center",
        hmargin = 4,
    },
    -- No width: it is the stamina reading, set per hero at construction.
    -- Composed onto the theme's {fillBarFill}, which supplies the shading
    -- gradient. Its own @accent bgcolor is overridden here; three selectors so
    -- the state rules beat the resting one outright rather than tying with it.
    {
        selectors = {"ha-health-fill"},
        height = "100%-2",
        halign = "left",
        valign = "center",
        lmargin = 1,
        bgimage = true,
    },
    {
        selectors = {"fillBarFill", "ha-health-fill"},
        bgcolor = "@success",
    },
    {
        selectors = {"fillBarFill", "ha-health-fill", "ha-winded"},
        transitionTime = 0.4,
        bgcolor = "@warning",
    },
    {
        selectors = {"fillBarFill", "ha-health-fill", "ha-dying"},
        transitionTime = 0.4,
        bgcolor = "@danger",
    },
    {
        selectors = {"ha-health-adjust"},
        width = 11,
        height = 11,
        valign = "center",
    },
    {
        selectors = {"ha-health-adjust", "ha-health-left"},
        halign = "left",
        lmargin = 1,
    },
    {
        selectors = {"ha-health-adjust", "ha-health-right"},
        halign = "right",
        rmargin = 1,
    },
    {
        selectors = {"ha-health-entry"},
        width = "70%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    },
    {
        selectors = {"ha-health-label"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    },

    --[[ Chips, shared by conditions, languages and skills ]]
    {
        selectors = {"ha-chips"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 2,
    },
    {
        selectors = {"ha-chip"},
        width = "auto",
        height = 16,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hmargin = 2,
        vmargin = 1,
        hpad = 5,
    },
    {
        selectors = {"ha-chip-icon"},
        width = 10,
        height = 10,
        halign = "left",
        valign = "center",
        rmargin = 3,
    },
    {
        selectors = {"ha-chip-label"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textAlignment = "left",
    },
    {
        selectors = {"ha-chip-add"},
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        hmargin = 2,
    },
    {
        selectors = {"ha-chip-setcaster"},
        width = 11,
        height = 11,
        halign = "left",
        valign = "center",
        lmargin = 3,
    },
    --Hidden until the chip is hovered. `hidden`, not `opacity`: a failed match
    --on opacity leaves an invisible control that still swallows clicks.
    {
        selectors = {"ha-chip-remove"},
        width = 12,
        height = 12,
        halign = "left",
        valign = "center",
        lmargin = 4,
        bgimage = true,
        border = 1,
        borderColor = "@danger",
        cornerRadius = 0,
        hidden = 1,
    },
    {
        selectors = {"ha-chip-remove", "parent:hover"},
        hidden = 0,
    },
    {
        selectors = {"ha-chip-remove", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"ha-chip-remove-x"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    },
    --Resting tint for an icon button. The glyph lives in a child buttonIcon
    --panel and is tinted by bgcolor, so a foreground class on the button never
    --reaches it, and the theme's own with* classes cover hover only.
    {
        selectors = {"panel", "buttonIcon", "parent:ha-tint-success"},
        bgcolor = "@success",
    },
    {
        selectors = {"panel", "buttonIcon", "parent:ha-tint-warning"},
        bgcolor = "@warning",
    },
    {
        selectors = {"panel", "buttonIcon", "parent:ha-tint-danger"},
        bgcolor = "@danger",
    },
    --For glyphs sitting on the stamina fill, which is already carrying the
    --status colour: they take the same @fg the reading does.
    {
        selectors = {"panel", "buttonIcon", "parent:ha-tint-fg"},
        bgcolor = "@fg",
    },
    {
        selectors = {"ha-addcombat"},
        width = 16,
        height = 16,
        halign = "left",
        valign = "center",
        hmargin = 3,
    },
    {
        selectors = {"ha-stat-button"},
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        hmargin = 2,
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
        selectors = {"ha-filter-row"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 2,
    },
    --Centred across everything the button does not take, rather than across the
    --whole row, so the text does not sit visibly off-centre.
    {
        selectors = {"ha-filter-label"},
        width = "100%-22",
        height = "auto",
        halign = "left",
        valign = "center",
        textAlignment = "center",
    },
    {
        selectors = {"ha-filter-button"},
        width = 16,
        height = 16,
        halign = "right",
        valign = "center",
    },
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
