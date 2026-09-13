local mod = dmhub.GetModLoading()

--- The Exploration tab: what the party collectively knows, as chips. Each
--- language or skill appears once with a speaker count; the tooltip names who.
--- @class HAExplorationTab: GameType
HAExplorationTab = RegisterGameType("HAExplorationTab")

--- Open Request Rolls for one hero with one skill already chosen. The dialog
--- seeds its token pool from the map selection and takes the skill through
--- `skills`, so pre-selecting means setting the selection and passing the id.
--- No checkType: leaving it off keeps both roll types on offer, and Test -- the
--- one carrying the skill dropdown -- is already the default.
--- @param token token The hero to request the roll from.
--- @param skillid string The skill's id in Skill.tableName.
local function OpenRequestRolls(token, skillid)
    dmhub.selectedTokens = {token}
    LaunchablePanel.LaunchPanelByName("Request Rolls", { skills = {skillid} })
end

--- Click a skill chip to ask for that roll. One hero goes straight through;
--- several offer a menu of who to ask first.
--- @param element Panel The chip, which hosts the popup.
--- @param bucket table An HAHeroData.Aggregate bucket.
local function RequestSkillRoll(element, bucket)
    local skillid = HAHeroData.SkillIdByName(bucket.name)
    if skillid == nil then
        return
    end

    if #bucket.members == 1 then
        OpenRequestRolls(bucket.members[1].token, skillid)
        return
    end

    local entries = {}
    for _, member in ipairs(bucket.members) do
        local token = member.token
        entries[#entries + 1] = {
            text = member.name,
            click = function()
                element.popup = nil
                OpenRequestRolls(token, skillid)
            end,
        }
    end

    element.popup = gui.ContextMenu{
        styles = ThemeEngine.MergeStyles(HAConstants.menuStyles),
        entries = entries,
    }
end

--- One heading plus its chip row.
--- @param title string Section heading.
--- @param buckets table[] As produced by HAHeroData.Aggregate.
--- @param onPress fun(element: Panel, bucket: table)|nil Chip click handler.
--- @return Panel
local function BuildSection(title, buckets, onPress)
    local chips = {}

    if #buckets == 0 then
        chips[#chips + 1] = gui.Label{
            classes = {"thc-chip-label", "sizeXxs", "fgMuted"},
            text = "None",
        }
    end

    for _, bucket in ipairs(buckets) do
        local names = {}
        for _, member in ipairs(bucket.members) do
            names[#names + 1] = member.name
        end

        --No "x1": the chip being here already says someone has it, so printing
        --it on every entry only buries the counts worth noticing.
        chips[#chips + 1] = THCWidgets.Chip{
            label = bucket.count > 1
                and string.format("%s x%d", bucket.name, bucket.count)
                or bucket.name,
            tooltip = table.concat(names, "\n"),
            press = onPress ~= nil and function(element)
                onPress(element, bucket)
            end or nil,
        }
    end

    return gui.Panel{
        classes = {"ha-section"},

        gui.Label{
            classes = {"ha-heading", "bold", "sizeXxs"},
            text = title,
        },
        gui.Panel{
            classes = {"thc-chips"},
            wrap = true,
            children = chips,
        },
    }
end

--- One filter's caption, with the party's own name filled in where it applies.
--- @param filter table An HAConstants.explorationFilters entry.
--- @return string text
local function ResolveFilterText(filter)
    if filter.textFormat ~= nil then
        return string.format(filter.textFormat, HAHeroData.PartyName())
    end
    return filter.text
end

--- @param filterId string
--- @return string text
local function FilterText(filterId)
    for _, filter in ipairs(HAConstants.explorationFilters) do
        if filter.id == filterId then
            return ResolveFilterText(filter)
        end
    end
    return ""
end

--- The tab body, which owns the filter that decides whose languages and skills
--- are being counted. The filter is a view preference, so it lives here and
--- survives the refreshes that rebuild the sections under it.
--- @return Panel body
function HAExplorationTab.Build()
    local m_filter = HAConstants.filterAssigned

    local sections = gui.Panel{
        classes = {"ha-section"},

        refreshSections = function(element)
            local entries = HAHeroData.CollectByFilter(m_filter)

            local languages = HAHeroData.Aggregate(entries, function(hero)
                return HAHeroData.GetLanguageNames(hero, false)
            end)
            local skills = HAHeroData.Aggregate(entries, HAHeroData.GetSkillNames)

            --Requesting a roll is a Director's job, and the Request Rolls
            --panel hides itself from players anyway.
            element.children = {
                BuildSection("LANGUAGES", languages),
                BuildSection("SKILLS", skills, dmhub.isDM and RequestSkillRoll or nil),
            }
        end,
    }

    --The caption is re-read on every refresh rather than written once: the
    --party filter's caption carries the party's name, which can be changed
    --while the panel is open.
    local header
    header = THCWidgets.HeaderBar{
        icon = HAConstants.iconFilter,
        text = FilterText(m_filter),
        tooltip = "Choose which heroes are counted",

        press = function(element)
            local entries = {}
            for _, filter in ipairs(HAConstants.explorationFilters) do
                if dmhub.isDM or not filter.dmOnly then
                    local id = filter.id
                    entries[#entries + 1] = {
                        text = ResolveFilterText(filter),
                        check = m_filter == id,
                        click = function()
                            element.popup = nil
                            m_filter = id
                            header:FireEventTree("setHeaderText", FilterText(m_filter))
                            sections:FireEvent("refreshSections")
                        end,
                    }
                end
            end

            --A context menu re-roots out of this panel's tree, so it carries
            --its own cascade rather than inheriting ours.
            element.popup = gui.ContextMenu{
                styles = ThemeEngine.MergeStyles(HAConstants.menuStyles),
                entries = entries,
            }
        end,
    }

    return gui.Panel{
        classes = {"ha-tabbody"},
        vscroll = true,

        refreshData = function(element)
            header:FireEventTree("setHeaderText", FilterText(m_filter))
            element:FireEventTree("refreshSections")
        end,

        create = function(element)
            element:FireEventTree("refreshSections")
        end,

        header,
        sections,
    }
end
