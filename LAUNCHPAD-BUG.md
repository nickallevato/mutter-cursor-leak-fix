# Launchpad bug draft: `mutter` (Ubuntu), series Resolute (26.04)

**File at:** https://bugs.launchpad.net/ubuntu/+source/mutter/+filebug
**Attach:** `patch/0001-cursor-wayland-dont-hold-a-ref-on-the-surface.patch`
(once the bug exists, also add the tag `resolute`)

---

**Title:** Leaked Wayland cursor surfaces make GNOME Shell progressively slower over uptime (fixed upstream in 50.3 by 918da17b)

**Description:**

[ Impact ]

In mutter 50.1 every Wayland cursor surface a client creates is leaked, together with its
`MetaCursorWayland` sprite. Each leaked surface also stays connected to the cursor
renderer's `cursor-painted` signal, so every cursor repaint on every output walks all of
them on the compositor thread. The cost grows with client churn: browsers, Electron apps,
Playwright/automation, anything that sets a texture cursor. The desktop slowly degrades to
roughly half rate on all monitors, including a stuttering pointer, until the user logs out.

Measured on an affected 26.04.1 desktop (3× 4K, 2 days 8 hours of uptime): 20,388
handlers on `cursor-painted`, all the same callback (`on_cursor_painted`); ~380,000
`g_closure_invoke` calls per second; gnome-shell main thread at 42 % vs ~15 % when healthy;
non-primary CRTCs at 50–66 ms per frame. Restarting the client apps freed none of it.

Independently confirmed by a second user on an AMD iGPU laptop (Ubuntu 26.04), so it is not
NVIDIA-specific; logging out clears it. 50.1-0ubuntu2.5 (resolute-proposed, 2026-10-08) does not
include the fix.

Cause: 95d44e93 ("wayland: Keep ref on surface at MetaWaylandCursor") created a reference
cycle, MetaWaylandSurface → role (MetaWaylandCursorSurface) → MetaCursorWayland → strong
ref back to the surface. Upstream fixed it on gnome-50 with 918da17b ("cursor/wayland:
Don't hold a ref on the surface", MR !5097), first released in 50.3. 50.1-0ubuntu2.4 does
not include it.

[ Test Plan ]

A headless reproducer (nothing is shown on the real desktop) is at
https://github.com/nickallevato/mutter-cursor-leak-fix (`test/`). It runs
`mutter --headless` on a private D-Bus session, moves a virtual pointer with the
RemoteDesktop API, and starts N short-lived GTK4 clients that each set a texture cursor
and exit. An LD_PRELOAD shim counts live `MetaWaylandCursorSurface` /
`MetaCursorWayland` objects with weak refs.

Results with 30 clients:
- 50.1-0ubuntu2.2: 30 of 30 cursor surfaces still alive after all clients exited
- 50.1-0ubuntu2.4: 30 of 30 still alive
- 50.1-0ubuntu2.4 + 918da17b: 0 of 30 (never more than 1 alive at a time)

Manual check on a real session: use texture-cursor apps (e.g. a browser) heavily for a
day. With the fix, gnome-shell CPU stays at baseline and the cursor stays smooth; without
it, both degrade.

[ Where problems could occur ]

The patch turns the sprite's surface reference into a weak pointer. Code that used the
surface through the sprite after the surface was destroyed now sees NULL. Upstream guards
the two places that do this (`prepare_at` and `get_buffer`). A missed caller would show up
as a gnome-shell crash on cursor changes while a client is exiting. The reproducer covers
exactly that case, a client exiting while its cursor is displayed, 30 times per run, with
no crash or critical. The change is 4 hunks in one file, is upstream in 50.3–50.5, and
applies cleanly on top of 50.1-0ubuntu2.4.

[ Other Info ]

Investigated, backported and tested with the help of an AI coding agent (Claude Code);
findings and numbers were checked on the affected machine. Workaround until fixed: log out
and back in.

---

## Follow-up comment for LP #2171024 (2026-11-10), with the debdiff attached

**Attach:** `patch/mutter_50.1-0ubuntu2.7.debdiff` (tick "This attachment is a patch"), then
subscribe `ubuntu-sponsors`. Regenerate against a newer base with `build/debdiff.sh`.

**Comment:**

Attaching a debdiff for resolute: 50.1-0ubuntu2.6 (currently in resolute-proposed) plus the
upstream fix 918da17b as 50.1-0ubuntu2.7. The patch is the unmodified gnome-50 commit with
DEP-3 headers; it applies without fuzz on 2.5 and 2.6. Please adjust the version and
changelog as needed.

New data since filing:

- 50.1-0ubuntu2.5 (resolute-updates since 2026-10-22) still leaks: the headless reproducer
  shows 30 of 30 cursor surfaces alive after all clients exited; 2.5 + the patch shows 0 of
  30, with no criticals in the mutter log.
- The 2.6 changelog in resolute-proposed does not include the fix either.
- Regression in the field: the affected desktop ran a locally patched 2.4 from 2026-09-24
  with no recurrence (21 handlers on `cursor-painted` after 2 days). The 2.5 update replaced
  that build on 2026-11-04; 14 hours into a session on 2026-11-10 the same callback again had
  8,083 handlers and ~53,000 handler invocations per second, with a stuttering pointer.
  Rebuilding 2.5 with the patch fixes it again.

Could the bug be nominated for Resolute? Reproducer and build scripts:
https://github.com/nickallevato/mutter-cursor-leak-fix
