# App icon

`AppIcon.icon` is the source of the app icon: an Icon Composer document (an `icon.json` and SVG layers). The app targets build their own copies, `Mactrix/AppIcon.icon` and `MactrixiOS/AppIcon.icon`. After you change the icon here, copy it to both folders:

```
cp -R design/icon/AppIcon.icon/ Mactrix/AppIcon.icon/
cp -R design/icon/AppIcon.icon/ MactrixiOS/AppIcon.icon/
```

Open a `.icon` in Icon Composer (`/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app`) to edit it. `concepts/` keeps the concepts from MATRIX-233. `AppIcon.icon` is `concepts/voices-b-paper.icon`.

## Renders

`render.sh` renders icons with `ictool`. For each icon, it renders Default, Dark, TintedLight, TintedDark, ClearLight and ClearDark at 512 px, and 16, 32 and 64 px Default. Then it builds a contact sheet with `contact-sheet.swift`. The output goes to `design/icon/renders/`, which git ignores.

```
design/icon/render.sh                       # AppIcon only
SHEET=contact-sheet-round4.png design/icon/render.sh \
    voices-a-charcoal voices-b-paper voices-c-mono voices-d-ocean voices-e-sunset voices-f-forest
```

A name is `AppIcon` or a folder name in `concepts/` without `.icon`. The sheets of MATRIX-233:

| Sheet | Names |
|---|---|
| round 1 | `concept-1-refresh concept-2-brackets concept-3-chat` |
| round 2 | `concept-2a-m concept-2b-p concept-2c-pd` |
| round 3 | `round-1-canon round-2-note round-3-wheel round-4-staff round-5-voices` |
| round 4 | the six `voices-*` names above |

`DEVELOPER_DIR` selects the Xcode that has Icon Composer (default `/Applications/Xcode-beta.app/Contents/Developer`).
