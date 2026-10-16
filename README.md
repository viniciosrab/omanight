# Night Light for Omarchy

Warms your screen at night and brings it back in the morning, on its own. It follows sunset and sunrise where you live and changes the color gradually, so you barely notice.

It replaces Omarchy's built-in night light. Your existing keybindings and bar indicator keep working.

## Install

```bash
omarchy plugin add https://github.com/viniciosrab/omanight.git --enable
omarchy restart shell
```

A moon appears on the right side of the bar.

## How it works

Out of the box, every day:

| When | Screen |
|---|---|
| Daytime | 6500K (normal) |
| Sunset | Warms to 3400K over 45 minutes |
| 3 hours after sunset | Warms further to 2700K |
| Sunrise | Back to 6500K, finishing right at sunrise |

Sunset and sunrise come from the location in Omarchy's Weather widget and are worked out on your computer, so the times shift with the seasons by themselves.

## Using it

**The moon on the bar**

| Click | Does |
|---|---|
| Left | Opens the panel |
| Right | Turns the night light on or off |
| Middle | Goes back to the automatic schedule |

The moon is dimmed while the night light is off.

**The panel** has an on/off switch and a slider from 1000K (warmest) to 6500K. Arrow keys work too, and `Esc` closes it.

Anything you change by hand lasts until the next step of the schedule, then the automatic schedule takes over again. A middle click on the moon brings it back sooner.

## Changing the schedule

Run these in a terminal. Changes are saved and survive restarts.

| Command | Changes |
|---|---|
| `omarchy-shell nightlight setEvening 3400` | Temperature at sunset |
| `omarchy-shell nightlight setLate 2700` | Temperature later in the night |
| `omarchy-shell nightlight setLateAfter 180` | Minutes after sunset for the second step (`0` turns it off) |
| `omarchy-shell nightlight setFade 45` | Minutes each change takes (`0` is instant) |
| `omarchy-shell nightlight setMode fixed` | Use fixed times instead of the sun (`sun` to go back) |
| `omarchy-shell nightlight setSchedule 21:00 06:30` | The fixed on and off times |
| `omarchy-shell nightlight setLocation -23.55 -46.63` | Your location, if the Weather widget doesn't have it |
| `omarchy-shell nightlight status` | Shows the current state and today's schedule |

To show the moon only while the night light is on:

```bash
omarchy bar set vinicios.nightlight hideWhenOff true
```

## Uninstall

```bash
omarchy plugin disable vinicios.nightlight
```

Omarchy's built-in night light comes back. To also forget your settings, delete `~/.local/state/omarchy/settings/omanight.json`.

## Development

Run `tests/run.sh` (needs a Wayland session). It uses fake `hyprctl`/`hyprsunset` and a scratch `HOME`, so it never touches your screen or settings.

## License

MIT, see [LICENSE](LICENSE).
