# dmgbuild settings for Hashlight's drag-to-Applications disk image (used by scripts/build-dmg.sh).
# dmgbuild runs this file with `defines` holding the -D values passed by the build script.
import os.path

application = defines["app"]
app_name = os.path.basename(application)
window_width = int(defines["window_width"])
window_height = int(defines["window_height"])

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

files = [application]
symlinks = {"Applications": "/Applications"}

background = defines["background"]
window_rect = ((200, 200), (window_width, window_height))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 100
# The generated background draws the arrow between these two icon centres.
icon_locations = {
    app_name: (window_width // 2, 140),
    "Applications": (window_width // 2, 400),
}
