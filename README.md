# Night Light for Omarchy

A night light plugin for the Omarchy shell (`vinicios.nightlight`) that drives hyprsunset live from a schedule you control.

It combines:

- **Three schedule modes**: `sun` (sunset to sunrise, worked out offline), `fixed` (on/off at HH:MM), and `manual` (one constant temperature).
- **Two-stage night**: an evening temperature at night start and a warmer late temperature some minutes later.
- **Gradual fades** interpolated in mireds, so every step looks the same size.
- **Overrides that stick** until a hold you choose: the next change, morning, 1 hour, a clock time, or forever.
- **Presets** (Day, Evening, Night, Candle) and a 1000–6500K slider.
- **A compact panel** that opens under the moon: switch, slider, presets, resume, a collapsed schedule editor, and a warning when hyprsunset stops responding.
- **Drift recovery**: when hyprsunset restarts or changes on its own, the plugin puts the scheduled temperature back.

The plugin replaces the stock `omarchy.nightlight` service (manifest `omarchy.clonedFrom`). It keeps the stock IPC surface, so existing keybindings and indicators keep working. It sends temperatures with `hyprctl hyprsunset temperature` and **never rewrites `~/.config/hypr/hyprsunset.conf`**. If hyprsunset isn't running, the plugin starts it (through `uwsm-app` when that's available).

## Install

```bash
# from a checkout of this repository:
ln -s "$PWD" ~/.config/omarchy/plugins/vinicios.nightlight

omarchy plugin enable vinicios.nightlight
omarchy restart shell
```

The shell's hot reload watches `~/.config/omarchy/plugins/` itself, so it does not see edits made through a symlinked checkout. After changing the code, run `omarchy restart shell`.

The moon goes in the right section of the bar by default. To move it:

```bash
omarchy bar move vinicios.nightlight --section right
```

To check a checkout against the manifest schema:

```bash
omarchy plugin validate .
```

## Controls

### Bar icon

The moon is dimmed while the light is off. Its tooltip shows the current temperature and the status line.

| Input | Action |
|---|---|
| Left click | Open/close the panel |
| Right click | Turn the light on/off until the next scheduled change |
| Middle click | Resume the schedule (clears any override) |

### Panel keyboard

| Key | Action |
|---|---|
| Arrow keys / `h` `j` `k` `l` | The first press shows the cursor. After that, up/down move between rows (switch, slider, presets, hold, resume, mode) and left/right pick an item. On the slider, left/right change the temperature by 100K. |
| `Enter` / `Space` | Activate the item under the cursor |
| `t` | Toggle the light |
| `r` | Resume the schedule |
| `s` | Expand or collapse the schedule editor |
| `Tab` / `Shift+Tab` | Switch to the next/previous bar panel |
| `Esc` | Close the panel |

The **Resume schedule** row only appears while an override is active.

### Panel sections

- **Header**: warmth name (Day, Neutral, Evening, Night, Tungsten, Candle, Ember) with the current K, the status line, and the on/off switch.
- **Slider and presets**: a slider painted in kelvin colors and Day / Evening / Night / Candle. Both hold until the next scheduled change (change that with the `hold` IPC call).
- **Resume schedule**: only while something overrides the schedule.
- **Schedule**: one summary line (mode, night window, temperatures). Click it, or press `s`, to edit the mode, the on/off times (fixed mode, or sun mode without a sunset), the night and late temperatures, and the fade length. The late-stage delay is IPC only (`setLateAfter`).

## Settings

### Bar widget

| Key | Default | Meaning |
|---|---|---|
| `hideWhenOff` | `false` | Show the moon only while the light is on, the panel is open, or the bar is hovered |

```bash
omarchy bar set vinicios.nightlight hideWhenOff true
```

### Schedule

These fields are edited from the panel or over IPC and stored in `omanight.json`.

| Field | Default | Notes |
|---|---|---|
| `mode` | `sun` | `sun`, `fixed`, or `manual` |
| `eveningTemperature` | `3400` | K at night start |
| `lateTemperature` | `2700` | K for the late stage |
| `lateAfterMinutes` | `180` | Minutes after night start; `0` disables the late stage |
| `fadeMinutes` | `45` | `0` snaps; max `240` |
| `onTime` / `offTime` | `20:00` / `07:00` | Fixed mode; also the fallback in sun mode with no location, or during polar day/night |
| `manualTemperature` | `4000` | K in manual mode |
| `defaultHold` | `next` | `next`, `1h`, or `morning` |

Temperatures are clamped to 1000–6500K. The light counts as "on" below 6000K, the same threshold the stock service uses.

How fades are timed:

- The evening and late fades start at their event.
- The morning fade ends at sunrise or the off time, so the screen is already neutral by then.
- Fades are shortened when they would overlap.

## IPC

### Service: target `nightlight`

| Call | Result |
|---|---|
| `status` | JSON: enabled, temperature, target, source, status, healthy, mode, override, sunrise, sunset, polar, location, schedule |
| `refresh` | Re-read hyprsunset. An external change becomes an override (see below). |
| `enable` / `disable` / `toggle` | Turn the light on/off until the next change. These print `enabled`/`disabled`. |
| `setTemperature <kelvin>` | Override at a temperature with the default hold |
| `preset <name>` | `day`, `evening`, `night`, `candle` (uses the default hold) |
| `off <hold>` | Override to off until `hold` |
| `hold <hold>` | Set the default hold and re-time an active override |
| `resume` | Clear the override and return to the schedule |
| `setMode <mode>` | `sun`, `fixed`, `manual` (also clears the override) |
| `setSchedule <onTime> <offTime>` | Fixed/fallback times as `HH:MM` |
| `setEvening <kelvin>` / `setLate <kelvin>` / `setManual <kelvin>` | Set the stage temperatures |
| `setLateAfter <minutes>` / `setFade <minutes>` | Set the late delay and the fade length |
| `setLocation <latitude> <longitude>` | Manual coordinates. The weather widget's location never replaces them. |
| `useWeatherLocation` | Drop manual coordinates and follow `weather.json` again |

**Hold syntax** for `off` and `hold`:

| Hold | Ends at |
|---|---|
| `next` | The next scheduled change |
| `morning` | The next night end |
| `1h`, `30m`, any `<N>h` or `<N>m` | That long from now |
| `HH:MM` | The next time the clock reads that time |
| `forever` | When you resume |

Only `next`, `1h`, and `morning` are saved as the default hold. Other values passed to `hold` just re-time the active override. Passing an empty hold to `off` uses the default hold.

Overrides are saved with absolute deadlines, so they survive a shell restart. They're re-applied when hyprsunset drifts or restarts.

```bash
omarchy-shell nightlight status
omarchy-shell nightlight preset candle
omarchy-shell nightlight setTemperature 3000
omarchy-shell nightlight off morning
omarchy-shell nightlight hold 22:30
omarchy-shell nightlight resume
omarchy-shell nightlight setMode fixed
omarchy-shell nightlight setSchedule 21:00 06:30
omarchy-shell nightlight setLocation 52.52 13.40
```

`omarchy toggle nightlight` changes hyprsunset directly, then calls `nightlight refresh`. The plugin adopts the new temperature as an override until the next scheduled change instead of undoing it.

The plugin also exposes `enabled` and `setNightlight(bool)` for the stock Indicators proxy.

### Panel: target `vinicios.nightlight`

`open`, `close`, `show`, `hide`, `toggle`

```bash
omarchy-shell vinicios.nightlight toggle
```

## Files

| Path | Purpose |
|---|---|
| `~/.local/state/omarchy/settings/omanight.json` | Plugin state: schedule, override, location. Written atomically; hand edits are picked up. |
| `~/.local/state/omarchy/settings/weather.json` | Read only, as the location source (the Weather widget's `latitude`/`longitude`/`name`) |

Sun mode resolves the location in this order:

1. Manual coordinates from `setLocation`.
2. Coordinates in `weather.json`.
3. If `weather.json` has only a place name, a single lookup against the Open-Meteo geocoding API.

Sunrise and sunset are computed offline with the NOAA equations. Without a location, sun mode uses the fixed times.

## Uninstall

```bash
omarchy plugin disable vinicios.nightlight   # the stock nightlight service comes back
rm ~/.local/state/omarchy/settings/omanight.json   # optional: forget the plugin state
```

## Development

```bash
tests/run.sh        # node unit tests, then Quickshell integration tests
node --test tests/  # unit tests only (pure model in Model.js)
```

`tests/run.sh` runs each `tests/integration/*.qml` in real Quickshell against the installed Omarchy UI modules. It needs a Wayland session.

The integration tests don't touch your system:

- `hyprctl`, `hyprsunset`, `pgrep`, `uwsm-app`, and `curl` are replaced by fakes in `tests/bin`.
- `HOME` is a scratch directory.
- The live display and the running shell are left alone.

To run a single test, use `ONLY=<name> tests/run.sh`.

## Credits

Inspired by [key-tone/omarchy-nightlight](https://github.com/key-tone/omarchy-nightlight), [jeremylanger/omarchy-nightlight](https://github.com/jeremylanger/omarchy-nightlight), and [agkrishnendu/omarchy-nightlight](https://github.com/agkrishnendu/omarchy-nightlight) (MIT). This plugin was written from scratch.

## License

MIT, see [LICENSE](LICENSE).
