"""Fail packaging if the final mounted image loses its Finder presentation."""
import os
import sys

from ds_store import DSStore
from mac_alias import Alias


def text(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value


mount, app_name = sys.argv[1:]
mount = os.path.realpath(mount)
store_path = os.path.join(mount, ".DS_Store")
with DSStore.open(store_path, "r") as store:
    assert store["."]["icvl"] == (b"type", b"icnv"), "Finder default view is not icon view"
    window = store["."]["bwsp"]
    assert window["WindowBounds"] == "{{180, 120}, {980, 620}}", window
    assert not window["ShowToolbar"] and not window["ShowSidebar"], window
    view = store["."]["icvp"]
    assert view["backgroundType"] == 2, "Finder background is not an image"
    assert view["iconSize"] == 128 and view["arrangeBy"] == "none", view
    assert store[app_name]["Iloc"] == (268, 300), "App icon position changed"
    assert store["Applications"]["Iloc"] == (712, 300), "Applications icon position changed"
    assert not list(store.find(".", b"pBBk")), "Obsolete background bookmark found"

    saved_alias = Alias.from_bytes(view["backgroundImageAlias"])
    actual_alias = Alias.for_file(os.path.join(mount, ".background.png"))
    assert saved_alias.volume.creation_date == actual_alias.volume.creation_date
    assert text(saved_alias.volume.name) == text(actual_alias.volume.name)
    assert saved_alias.target.cnid == actual_alias.target.cnid
    assert saved_alias.target.creation_date == actual_alias.target.creation_date
    assert text(saved_alias.target.posix_path) == text(actual_alias.target.posix_path)

assert os.path.isdir(os.path.join(mount, app_name)), "App missing from disk image"
assert os.readlink(os.path.join(mount, "Applications")) == "/Applications"
print("Finder installer layout verified")
