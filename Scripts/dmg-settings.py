"""Deterministic Finder presentation for the LumaView installer."""
import os

application = defines["app"]
format = "UDZO"
filesystem = "HFS+"
compression_level = 9
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
background = defines["background"]

# The two real Finder icons deliberately remain the focal point: drag the app
# on the left, across the illustrated arrow, to Applications on the right.
window_rect = ((180, 120), (980, 620))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    os.path.basename(application): (268, 300),
    "Applications": (712, 300),
}
