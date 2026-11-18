from pathlib import Path

application = Path(defines["app"])
files = [str(application)]
symlinks = {"Applications": "/Applications"}
icon_locations = {application.name: (166, 163), "Applications": (474, 163)}
window_rect = ((120, 120), (640, 352))
icon_size = 84
text_size = 13
format = "UDZO"
background = defines["background"]
