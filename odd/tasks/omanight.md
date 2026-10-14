# omanight — native Omarchy Night Light plugin

Best-of-three night light plugin (key-tone, jeremylanger, agkrishnendu) built from scratch.
Plugin id `vinicios.nightlight`; replaces the built-in `omarchy.nightlight` service.

## Specs

- S1 (user, verbatim): "pegar O melhor dos três Questão de recursos E etc, recursos Enfim, tudo que tiver de bom Pra gente compilar Em um plugin aqui nativo, né? Do Marche De night" — one native Omarchy shell plugin combining the best features of the three references.
- S2 Architecture (accepted recommendation): `service` + `bar-widget` kinds, `keepLoaded: true`, `omarchy.clonedFrom: "omarchy.nightlight"`; the service owns time and drives hyprsunset live with `hyprctl hyprsunset temperature`; it never rewrites `~/.config/hypr/hyprsunset.conf`.
- S3 Compatibility: keep the IPC target `nightlight` with `status`, `refresh`, `enable`, `disable`, `toggle`; expose `enabled` and `setNightlight(bool)` for the stock Indicators proxy. `omarchy toggle nightlight` (which changes hyprsunset then calls `nightlight refresh`) is adopted as an override until the next scheduled change instead of being undone.
- S4 Schedule modes: `sun` (default; offline NOAA sunrise/sunset from `~/.local/state/omarchy/settings/weather.json`, Open-Meteo geocode by name when coordinates are missing, manual lat/lon via IPC), `fixed` (on/off HH:MM), `manual` (constant temperature). Polar day/night falls back to fixed times.
- S5 Two-stage night: evening temperature (default 3400K) at night start, late temperature (default 2700K) N minutes later (default 180, 0 disables).
- S6 Gradual fades interpolated in mireds (default 45 min, 0 = snap): evening and late fades start at their event; the morning fade ends at the night end (screen neutral by sunrise/off time). Fades are shortened so they never overlap.
- S7 Overrides with holds `next` (next scheduled change), `1h`, `morning` (next night end), `HH:MM`; persisted with absolute deadlines; re-applied when hyprsunset drifts or restarts; "Resume schedule" ends it.
- S8 Presets Day 6500 / Evening 4000 / Night 3400 / Candle 1900 and a 1000–6500K slider, both as overrides with the selected hold.
- S9 Panel UI (references 1–3): hero with warmth name, status line, current K and master switch; kelvin-gradient slider; presets; hold + resume; schedule editor (mode, times, temperatures, fade); day timeline with current marker and fade gradient bars; hyprsunset health warning; keyboard navigation.
- S10 Bar widget: moon icon, dimmed when off, optional hide-when-off (`hideWhenOff` setting), tooltip with K and status; left click panel, right click toggle, middle click resume schedule.
- S11 Tests: node unit tests for the pure model; Quickshell integration test with faked hyprctl; `omarchy plugin validate .` passes.
- S12 Docs: README covering install, controls, IPC, files, uninstall.

## Tasks

- T1 S4-S8 Pure model `Model.js` + node tests — inline — commit: pending
- T2 S2-S4,S7 Service.qml (state, ticking, apply, IPC) + manifest — inline — commit: pending
- T3 S9-S10 Panel.qml + BarWidget.qml — inline — commit: pending
- T4 S11 Quickshell integration test + validate — inline — commit: pending
- T5 S12 README + verify — inline — commit: pending

## Log

- L1 (user request, verbatim): "https://github.com/key-tone/omarchy-nightlight https://github.com/agkrishnendu/omarchy-nightlight https://github.com/jeremylanger/omarchy-nightlight Eu quero que você Dê uma Investigada pra gente pegar O melhor dos três Questão de recursos E etc, recursos Enfim, tudo que tiver de bom Pra gente compilar Em um plugin aqui nativo, né? Do Marche De night De night, né? Plugin de night, night e noite Aí você vai investigar Aqui os códigos, né? A base de código, esses três plugins Que são de night e noite Pra você ver O que tem de bom de cada um Pra gente ver, compilar Em um plugin pra nós aqui Fazer um plugin do zero Do nosso Marche, entendeu? Mas você não vai sair fazendo Você vai investigar E aí você vai retornar A sua conclusão, ok?"
- L2 Investigation delivered; open decisions: replace native service, UI language, default mode, location fallback.
- L3 (user, verbatim): "GO" — proceeding with the recommended answers: replace native service, English UI, `sun` default, weather.json + Open-Meteo geocode + manual lat/lon.
