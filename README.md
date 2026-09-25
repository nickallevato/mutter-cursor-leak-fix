# mutter cursor-surface leak on Ubuntu 26.04 — found, backported, proven

**Symptom:** GNOME on Ubuntu 26.04 gets steadily slower the longer you stay logged in.
After a day or two the whole desktop feels like it is running at 30 Hz, and even the
mouse cursor stutters, on every monitor at once. A reboot or a log out fixes it, and then
it comes back.

**Cause:** a reference cycle in mutter 50.1. Every Wayland cursor surface a client creates
is kept alive forever, *after the client has exited*, and stays connected to the cursor
renderer's `cursor-painted` signal. Every cursor repaint on every monitor then walks all
of them on the compositor thread.

**Fix:** already upstream. [Jonas Ådahl's commit 918da17b](https://gitlab.gnome.org/GNOME/mutter/-/commit/918da17b0be2286382772ee38d53311b0be146b4)
(MR [!5097](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/5097)) is in mutter
**50.3+**. Ubuntu 26.04 still ships **50.1-0ubuntu2.4**, which does not have it. This repo
backports that one patch onto Ubuntu's package, includes a headless reproducer that proves
the leak and the fix, and has a build script for anyone who wants the fix now.

> **Built with AI, and proud of it.** The whole investigation was done by
> [Claude Code](https://claude.com/claude-code) (Claude Opus 5.5) working on the affected
> machine. That covered bpftrace and perf on a live compositor, reading mutter's source to
> find the cycle, finding the upstream fix, building the package in a container, and writing
> and running the A/B test harness below. A human (me) noticed the symptom, drove the
> questions, approved each `sudo`, and logged out to test it. The actual mutter fix is Jonas
> Ådahl's; our part was finding out that this bug is the reason Ubuntu 26.04 desktops slow
> down, backporting the fix, and proving it works.

## The workload that triggered it

This leak doesn't show up on a quiet desktop. It builds up with **client churn**: lots of
apps opening and closing and setting their own cursors. My daily desktop churns a lot:

- 3× 4K monitors, RTX 3070, Ubuntu 26.04.1, GNOME Shell 50.1 on Wayland
- many Brave windows and PWAs open at once, Electron apps, a web game in development
- **Playwright** runs that start and throw away browser instances again and again
- dev servers, AI coding agents driving browsers, a 3D-printer slicer, RDP sessions

The pattern I noticed: *"it happens when Playwright or dev or lots of browser sessions."*
It was always fine after a reboot and always degraded "after a certain amount of usage".

## What was measured on the live, degraded desktop (2 days 8 hours of uptime)

| Measurement | Healthy | Degraded |
|---|---|---|
| gnome-shell main thread CPU | ~15 % | **42 %** |
| share of that spent in GObject signal emission | — | **~45 %** |
| `g_closure_invoke` rate (bpftrace on libgobject) | — | **~380,000 / s** |
| handlers connected to `cursor-painted` (signal id 320) | a few | **20,388**, all the same callback |
| frame time on the non-primary CRTCs (`drm_vblank_event_delivered`) | 16.7 ms | **50–66 ms** |

All those handlers were the same callback (`on_cursor_painted` in
`meta-wayland-cursor-surface.c`), each with its own closure. Growth was about **9,000 per
day** of heavy use. **Gracefully restarting the browser freed none of them.** So the
surfaces outlive their client, and restarting apps can't fix it.

Ruled out along the way, each by measurement: GPU load and clock floor, refresh rate,
the cursor theme / hardware cursor plane, swap, disk I/O, and GNOME Shell extensions
(none of them connects to `cursor-painted`).

## Root cause

```
MetaWaylandSurface ──role──▶ MetaWaylandCursorSurface ──cursor_sprite──▶ MetaCursorWayland
        ▲                                                                   │
        └──────────────────── g_set_object (strong ref) ◀───────────────────┘
```

- `MetaWaylandSurface` only releases its role in `dispose`.
- `MetaCursorWayland` has held a **strong** reference to that surface since
  [95d44e93](https://gitlab.gnome.org/GNOME/mutter/-/commit/95d44e93734b4c947fd4519a210489494bd2d65e)
  (Feb 2026, "Keep ref on surface at MetaWaylandCursor").
- When the client destroys the `wl_surface`, `wl_surface_destructor` drops only its own
  reference. The cycle keeps all three objects alive. The role's
  `g_signal_connect_object (renderer, "cursor-painted", …)` is only undone when the role is
  disposed, which never happens.

918da17b turns the back-reference into a weak pointer and handles a NULL surface in
`prepare_at` and `get_buffer`. It is 4 hunks in one file and applies cleanly on top of
all of Ubuntu's 50.1 patches.

## Proof: headless A/B test

`test/` runs a **separate headless mutter** on a private D-Bus session with a virtual
monitor, so nothing appears on your real desktop. It drives a virtual pointer through the
RemoteDesktop API and launches N short-lived GTK4 clients. Each one maps a window under the
pointer, sets a texture cursor, and exits. An `LD_PRELOAD` shim wraps `g_object_new` and
puts a weak ref on every `MetaWaylandCursorSurface` and `MetaCursorWayland`, so
*live = created − disposed*.

30 clients, run on 2026-09-24:

| libmutter-18-0 | cursor surfaces still alive after every client exited |
|---|---|
| 50.1-0ubuntu2.2 (stock) | **30 / 30** |
| 50.1-0ubuntu2.4 (stock, current `resolute-updates`) | **30 / 30** |
| 50.1-0ubuntu2.4 + 918da17b (this repo) | **0 / 30** |

The patched build never had more than 1 alive at a time, which is the current client's.
The same run also covers the patch's new NULL-surface path: each client exits while its
cursor is still shown. Across all runs there were no crashes and no criticals.

On the real desktop, the slowdown was gone after installing the patched package and logging
back in. It was installed on 2026-09-24, so confirmation over several days of uptime is still
pending; this README will be updated.

Run it yourself (needs `gcc`, `python3-gi` with GTK 4, `dbus-run-session`):

```bash
test/setup.sh        # fetches the stock mutter binary + old libmutter from Launchpad, builds the shim
dbus-run-session -- test/run.sh stock 30 test/work/old   # leaks
dbus-run-session -- test/run.sh mine 30                  # whatever libmutter is installed
```

Two things that were not obvious when writing the test:
- GTK4 sends **named** cursors through `wp_cursor_shape_v1`, which creates no cursor
  surface, so named cursors never trigger the leak. Only texture/custom cursors do, and
  real apps (browsers, Electron, CAD/slicers) use plenty of those. `client.py` uses a
  texture cursor.
- `GOBJECT_DEBUG=instance-count` does nothing on Ubuntu's release-built GLib, which is why
  the shim counts objects itself.

## Get the fix now

```bash
docker run --rm -v "$PWD":/work ubuntu:26.04 /work/build/build.sh   # ~5 min, output in out/
sudo dpkg -i out/{libmutter-18-0,gir1.2-mutter-18,mutter-common,mutter-common-bin}_*.deb
# then log out and back in
```

The package version is `50.1-0ubuntu2.4+cursorfix1`, so Ubuntu's next real mutter update
supersedes it automatically. To roll back:

```bash
sudo apt install --allow-downgrades libmutter-18-0=50.1-0ubuntu2.4 gir1.2-mutter-18=50.1-0ubuntu2.4 \
  mutter-common=50.1-0ubuntu2.4 mutter-common-bin=50.1-0ubuntu2.4
```

Until you install a fixed build, **logging out and back in** is the only workaround. It
restarts gnome-shell, which drops the leaked surfaces.

## Getting it into Ubuntu

[`LAUNCHPAD-BUG.md`](LAUNCHPAD-BUG.md) is a ready-to-file SRU request for Ubuntu's
`mutter` package, including the SRU template.

## License

GPL-2.0-or-later, the same as mutter. The patch is upstream mutter code by Jonas Ådahl.
