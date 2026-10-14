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

- T1 S4-S8 Pure model `Model.js` + node tests — inline — commit: 84fa6e5 (22 node tests green)
- T2 S2-S4,S7 Service.qml (state, ticking, apply, IPC) + manifest — inline — commit: 312093a + fix 30bb4d3 (9 qs scenarios green)
- T3 S9-S10 Panel.qml + BarWidget.qml — inline — commit: 3da08f9 (7 qs panel scenarios green)
- T4 S11 Quickshell integration test + validate — inline — commit: 30bb4d3, 3da08f9 (tests/run.sh green 3x; omarchy plugin validate exit 0)
- T5 S12 README + verify — worker mv7m2tyc-1-rygp — commit: a7dc7cb, a6853ed (live-verified; independent verifier unavailable)

## Log

- L1 (user request, verbatim): "https://github.com/key-tone/omarchy-nightlight https://github.com/agkrishnendu/omarchy-nightlight https://github.com/jeremylanger/omarchy-nightlight Eu quero que você Dê uma Investigada pra gente pegar O melhor dos três Questão de recursos E etc, recursos Enfim, tudo que tiver de bom Pra gente compilar Em um plugin aqui nativo, né? Do Marche De night De night, né? Plugin de night, night e noite Aí você vai investigar Aqui os códigos, né? A base de código, esses três plugins Que são de night e noite Pra você ver O que tem de bom de cada um Pra gente ver, compilar Em um plugin pra nós aqui Fazer um plugin do zero Do nosso Marche, entendeu? Mas você não vai sair fazendo Você vai investigar E aí você vai retornar A sua conclusão, ok?"
- L2 Investigation delivered; open decisions: replace native service, UI language, default mode, location fallback.
- L3 (user, verbatim): "GO" — proceeding with the recommended answers: replace native service, English UI, `sun` default, weather.json + Open-Meteo geocode + manual lat/lon.
- L4 (user, verbatim): "uma pergunta pq ate agora voce nao usou nenhum subagente do odd? e proposital?" — answered: implementation chain was sequential (Writer rule not met); the exploration skipped the mandatory evidence-budget delegation (routing defect acknowledged).
- L5 (user, verbatim): "continue oque o ODD manda" — README delegated to gentle-ai-worker in background (disjoint surface README.md, LICENSE).
- L6 Root cause of flaky Service test: an aborted debug run left an unguarded onLoaded in Service.qml; the watched FileView reloaded a superseded text and rolled back prefs. Fixed with a separate unwatched writer view + own-write guard (30bb4d3). Harness FileView reads of the fake missed same-size rewrites within a second; switched to cat.
- L7 Risk: item 3 (replaces the `nightlight` IPC target and stock Indicators proxy contract) -> independent gentle-ai-verify.
- L8 gentle-ai-verify task mv7mbery-2-zypp failed: "No API key found for openai" (provider config). Not retried; S3 host-compatibility remains unverified independently -> Needs your decision.
- L9 (user, verbatim): "go" — install + cleanup authorized. Leftovers moved (not deleted) to ~/.local/state/omanight-legacy-backup-20261014014339 (dangling systemd units/wants, old state dirs, .bak plugin, previous omanight.json). Symlinked and enabled; stock omarchy.nightlight disabled automatically.
- L10 Live finding: the stock `nightlight` IpcHandler keeps the target until `omarchy restart shell`; README updated. After restart: status from our service, 2700K late stage (sunset 18:38), no QML warnings. S3 live check: `omarchy toggle nightlight` -> override off "Off until 04:57"; `nightlight resume` -> 2700K schedule. Stock Indicators proxy path not exercised (no indicators entry using it).
