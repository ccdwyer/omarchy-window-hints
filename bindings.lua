-- Window Hints — paste into ~/.config/hypr/bindings.lua
--
-- Suggested bind: SUPER + F. If that collides, use SUPER + H or SUPER + ;
-- (first summon will say so). Esc always leaves the hints submap, even if
-- the shell is dead — that is the stuck-submap recovery path.
--
-- Chord alphabet is fixed: asdfghjkl (no x, no digits — those are verbs).

hl.bind("SUPER + F", hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.chris.window-hints '{}'"))

hl.define_submap("hints", function()
    local id = "io.github.chris.window-hints"
    local function key(k)
        return hl.dsp.exec_cmd("omarchy-shell shell call " .. id .. " key " .. k)
    end

    for _, ch in ipairs({ "a", "s", "d", "f", "g", "h", "j", "k", "l" }) do
        hl.bind(ch, key(ch))
        hl.bind("SHIFT + " .. ch, key(string.upper(ch)))
    end

    hl.bind("x", key("x"))
    for n = 1, 9 do
        hl.bind(tostring(n), key(tostring(n)))
    end

    hl.bind("escape", function()
        hl.dispatch(key("escape"))
        hl.dispatch(hl.dsp.submap("reset"))
    end)
    hl.bind("catchall", hl.dsp.no_op())
end)
