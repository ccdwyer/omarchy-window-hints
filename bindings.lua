-- Window Hints — paste into ~/.config/hypr/bindings.lua
--
-- Suggested bind: SUPER + F. If that collides, use SUPER + H or SUPER + ;
-- (first summon will say so). Esc always leaves the hints submap, even if
-- the shell is dead — that is the stuck-submap recovery path.
--
-- Keep `alphabet` in sync with the plugin's inline `alphabet` setting.
-- `hints-ctl submap install <alphabet>` regenerates this block from the
-- active setting (the default below is asdfghjkl).

hl.bind("SUPER + F", hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.chris.window-hints '{}'"))

hl.define_submap("hints", function()
    local id = "io.github.chris.window-hints"
    local alphabet = "asdfghjkl"
    local function key(k)
        return hl.dsp.exec_cmd("omarchy-shell shell call " .. id .. " key " .. k)
    end

    for ch in alphabet:gmatch(".") do
        hl.bind(ch, key(ch))
        hl.bind("SHIFT + " .. ch, key(string.upper(ch)))
    end

    if not alphabet:find("x", 1, true) then
        hl.bind("x", key("x"))
    end
    for n = 1, 9 do
        hl.bind(tostring(n), key(tostring(n)))
    end

    hl.bind("escape", function()
        hl.dispatch(key("escape"))
        hl.dispatch(hl.dsp.submap("reset"))
    end)
    hl.bind("catchall", hl.dsp.no_op())
end)
