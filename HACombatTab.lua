local mod = dmhub.GetModLoading()

--- The Combat tab: one compact card per hero, with stamina, the movement and
--- recovery numbers, and their conditions.
--- @class HACombatTab: GameType
HACombatTab = RegisterGameType("HACombatTab")

--- Every hero on the board and the summons and retainers under them,
--- flattened into the one list the card pool binds against.
---
--- One entry per hero. A summon or a retainer is not an entry of its own: it
--- is drawn inside its summoner's or mentor's card, so the pool only ever
--- binds heroes and the zebra never restarts mid-group.
--- @return table[] entries { token, even, summons }
function HACombatTab.CardEntries()
    local entries = {}

    for i, entry in ipairs(HAHeroData.CollectCombatHeroes()) do
        local under = HAHeroData.SummonsFor(entry.token)
        for _, retainer in ipairs(HAHeroData.RetainersFor(entry.token)) do
            under[#under + 1] = retainer
        end
        entries[#entries + 1] = {
            token = entry.token,
            even = i % 2 == 0,
            summons = under,
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
            THCWidgets.BindList(cardList, entries, THCWidgets.HeroCard, "bindHero")
        end,

        create = function(element)
            element:FireEvent("refreshData")
        end,

        emptyLabel,
        cardList,
    }
end
