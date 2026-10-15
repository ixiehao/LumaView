# Reproducible installer presentation

Run `./Scripts/package-dmg.sh` on an Apple-silicon Mac with Xcode and Python
3.10 or newer. Set `PACKAGING_PYTHON` when the preferred Python executable is
not on `PATH`.

LumaView deliberately uses `dmgbuild` 1.6.7 to write Finder metadata directly,
rather than depending on a manually opened Finder window. The visual design is
original LumaView artwork: its colour field, title, drag arrow, capability note
and all dimensions are authored in `Scripts/create-dmg-background.swift`.
`Scripts/dmg-settings.py` supplies the app and Applications positions, icon
view and background reference.

After the image is compressed, `Scripts/verify-dmg-layout.py` remounts it and
requires all of the following before the package can succeed:

- Finder icon view and the intended 980 × 620 window;
- 128 px icons at the saved LumaView and Applications positions;
- a valid image background alias, without the legacy `pBBk` bookmark;
- the `/Applications` link and the app bundle.

The required Python packages live only in `build/dmg-tools` and are ignored by
Git. They are packaging infrastructure, not application dependencies. For a
visual acceptance check, eject any older LumaView installer volume, open the
new DMG in a fresh Finder window, and confirm that the app is dragged from left
to right into Applications.
