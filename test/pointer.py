# Keeps one RemoteDesktop session alive (sessions die with their D-Bus client),
# parks the virtual pointer mid-screen and jiggles it so every new window gets
# wl_pointer.enter.
import time
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
def call(path, iface, meth, args=None, sig=None):
    return bus.call_sync("org.gnome.Mutter.RemoteDesktop", path, iface, meth, args,
                         GLib.VariantType(sig) if sig else None, 0, -1, None)
s = call("/org/gnome/Mutter/RemoteDesktop", "org.gnome.Mutter.RemoteDesktop", "CreateSession", None, "(o)")[0]
call(s, "org.gnome.Mutter.RemoteDesktop.Session", "Start")
print("pointer session", s, flush=True)
call(s, "org.gnome.Mutter.RemoteDesktop.Session", "NotifyPointerMotionRelative", GLib.Variant("(dd)", (640.0, 360.0)))
d = 4.0
while True:
    try:
        call(s, "org.gnome.Mutter.RemoteDesktop.Session", "NotifyPointerMotionRelative", GLib.Variant("(dd)", (d, 0.0)))
    except GLib.Error as e:
        print("pointer:", e.message, flush=True); break
    d = -d; time.sleep(0.1)
