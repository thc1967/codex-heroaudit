local mod = dmhub.GetModLoading()

--- The Exploration tab: what the party collectively knows, as chips. Each
--- language or skill appears once with a speaker count; the tooltip names who.
--- @class HAExplorationTab: GameType
HAExplorationTab = RegisterGameType("HAExplorationTab")

--- One heading plus its chip row.
--- @param title string Section heading.
--- @param buckets table[] As produced by HAHeroData.Aggregate.
--- @return Panel
local function BuildSection(title, buckets)
    local chips = {}

    if #buckets == 0 then
        chips[#chips + 1] = gui.Label{
            classes = {"ha-chip-label", "sizeXxs", "fgMuted"},
            text = "None",
        }
    end

    for _, bucket in ipairs(buckets) do
        --No "x1": the chip being here already says someone has it, so printing
        --it on every entry only buries the counts worth noticing.
        chips[#chips + 1] = HADockPanel.Chip{
            label = bucket.count > 1
                and string.format("%s x%d", bucket.name, bucket.count)
                or bucket.name,
            tooltip = table.concat(bucket.heroes, "\n"),
        }
    end

    return gui.Panel{
        classes = {"ha-section"},

        gui.Label{
            classes = {"ha-heading", "bold", "sizeXxs"},
            text = title,
        },
        gui.Panel{
            classes = {"ha-chips"},
            wrap = true,
            children = chips,
        },
    }
end

--- Both sections, rebuilt from a fresh read of the party.
--- @return Panel[] sections
function HAExplorationTab.BuildSections()
    local entries = HAHeroData.CollectHeroes()

    local languages = HAHeroData.Aggregate(entries, function(hero)
        return HAHeroData.GetLanguageNames(hero, false)
    end)
    local skills = HAHeroData.Aggregate(entries, HAHeroData.GetSkillNames)

    return {
        BuildSection("LANGUAGES", languages),
        BuildSection("SKILLS", skills),
    }
end
