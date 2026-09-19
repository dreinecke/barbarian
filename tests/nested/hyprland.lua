-- The nested test Hyprland's config (tests/nested/nested start). Five persistent, named desks on
-- the headless output, and a window rule per test class so a renumber has rules to follow.
-- ⚠️ The desk table's shape is what hook-rewrite-desks rewrites: one `{ id = "N", name = "…" },`
-- per line, closed by a `}` on a line of its own.
hl.monitor({ output = "WAYLAND-1", mode = "1280x720", position = "1600x0", scale = 1 })
hl.monitor({ output = "BARBTEST", mode = "1600x1400", position = "0x0", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
            animations = { enabled = false } })
local desks = {
  { id = "1", name = "Enterprise" },
  { id = "2", name = "Webscape" },
  { id = "3", name = "Personal" },
  { id = "4", name = "Tinkerbell" },
  { id = "5", name = "Hazel" },
}
for _, d in ipairs(desks) do
  hl.workspace_rule({ workspace = d.id, default_name = d.name, persistent = true, monitor = "BARBTEST" })
end
hl.window_rule({ match = { class = "^t-web$" }, workspace = "2 silent" })
hl.window_rule({ match = { class = "^t-per$" }, workspace = "3 silent" })
hl.window_rule({ match = { class = "^t-tink$" }, workspace = "4 silent" })
