# Headless test client: a maximized, undecorated GTK4 window whose whole area
# carries a *texture* cursor (named cursors go through wp_cursor_shape and never
# create a cursor surface), then exits after 0.7 s.
import gi, sys
gi.require_version("Gtk", "4.0"); gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib
def act(app):
    w = Gtk.ApplicationWindow(application=app); w.maximize()
    px = bytes([255, 0, 0, 255]) * (32 * 32)
    tex = Gdk.MemoryTexture.new(32, 32, Gdk.MemoryFormat.R8G8B8A8, GLib.Bytes.new(px), 32 * 4)
    w.set_decorated(False)
    area = Gtk.DrawingArea(hexpand=True, vexpand=True)
    area.set_cursor(Gdk.Cursor.new_from_texture(tex, 0, 0, None))
    w.set_child(area)
    w.present()
    GLib.timeout_add(700, app.quit)
app = Gtk.Application(application_id=None)
app.connect("activate", act); app.run([])
