-- Window Hints — paste into ~/.config/hypr/bindings.lua
--
-- Suggested bind: SUPER + F. If that collides, use SUPER + H or SUPER + ;
-- (first summon will say so). Esc always leaves the hints submap, even if
-- the shell is dead — that is the stuck-submap recovery path.
--
-- Chord alphabet is fixed: asdfghjkl (no x, no digits — those are verbs).
-- Keys go to the plugin's IpcHandler target `window-hints` (documented extra
-- shell IPC target), not `shell call <plugin-id>`, so they cannot recurse
-- through the overlay.

hl.bind("SUPER + F", hl.dsp.exec_cmd("omarchy-shell shell toggle io.github.chris.window-hints '{}'"))

hl.define_submap("hints", function()
    local function key(k)
        return hl.dsp.exec_cmd("omarchy-shell window-hints key " .. k)
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
