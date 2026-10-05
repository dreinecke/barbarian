# Open questions

## Q-101 How should the Reptile panel live inside the merged Barbarian plugin?

Reptile's zero-width widget exists only to host its panel and IPC target
(`tinkerbell.reptile`, HYPER+L). Barbarian already hosts two surfaces (the arrange
panel and the theme-grid overlay) under one id. Quickshell IPC targets are plain
strings, so the merged plugin can keep a second handler answering to
`tinkerbell.reptile` — that would leave HYPER+L, bindings.lua and both engines'
callbacks working unchanged.

- A second panel inside Barbarian's widget, keeping its own IPC name — one folder and installer, keybind and engines untouched (cheapest)
- Everything re-routed to the one id `tinkerbell.arrange` — one identity everywhere, but the keybind and every engine callback get retargeted
- A tab inside the main Barbarian panel — one window, but Reptile loses its own header, puns and keyboard model

## Q-102 Should install.sh migrate machines off the old plugin automatically?

After the merge, every machine still has the `tinkerbell.reptile` entry in
shell.json (machine-local) and its folder under plugins/. The entry must leave the
bar and the folder must go; under Q-101's first answer the keybind stays as it is.
Barbarian now owns a hardened removal path (DEL: in bar-arrange-apply, then
plugin-uninstall: layout write first, one folder at a time, never a restart).

- Yes — install.sh drops the entry, then detaches plugin-uninstall for the folder, and the keybind reminder is printed only if it needs changing
- No — the merge lands inert; I take the entry, folder and (if needed) keybind out by hand on each machine
- Half — the installer only trashes the folder; I edit shell.json by hand

## Q-103 What happens to the reptile repository?

- Archived — a closing README points at Barbarian; the file history stays there and Barbarian's README records where Reptile came from
- Grafted — reptile's commits are subtree-merged in first, so `git log` carries the layouts panel's history too
- Left alone — untouched, but its install.sh stops being the thing that runs
