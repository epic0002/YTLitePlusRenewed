# YTLPRLoader

Only this loader gets injected into YouTube. Every tweak sits in `YTLPR.bundle` and the loader
opens the ones that are switched on. The switches are in YouTube Settings under **YTLitePlusRenewed**.
Tweaks with `"on": true` in `Tweaks.json` start switched on, the rest start off. Changes apply after YouTube restarts (there's a Restart YouTube button at the bottom of the page).

## Adding a tweak

1. Put the `.dylib` in `YTLPR.bundle/`.
2. Add a line for it in `YTLPR.bundle/Tweaks.json`, inside the section you want:

```json
{ "name": "YouMute", "file": "YouMute.dylib", "about": "Mute button" }
```

That's it, no code changes and no need to rebuild the loader.

## Removing a tweak

Delete its line from `Tweaks.json` and delete the `.dylib` from `YTLPR.bundle/`.

## Options for each tweak

| Key | What it does | Needed |
| --- | --- | --- |
| `name` | Name shown on the switch | yes |
| `file` | The dylib's file name in `YTLPR.bundle` | yes |
| `about` | Small text under the name | no |
| `on` | `true` makes it start switched on. Leave it out and it starts off | no |
| `needs` | Files that must load first. Turning this tweak on turns those on too | no |
| `clashes` | Files that can't run with this one. Turning this on turns those off | no |

Example with everything:

```json
{
  "name": "YouSpeed",
  "file": "YouSpeed.dylib",
  "about": "Speed button",
  "on": true,
  "needs": ["YTVideoOverlay.dylib"],
  "clashes": ["SomeOtherSpeedTweak.dylib"]
}
```

Anything that adds a player button (YouSpeed, YouLoop, YouMute...) needs `YTVideoOverlay.dylib`.

Sections are just groups of switches. Add a new one by copying an existing `{ "title": ..., "tweaks": [...] }` block.

## Resource bundles

Most tweaks come with a `.bundle` folder (images, text, translations), like `YouMod.bundle` or `RYD.bundle`.
Put those in `Resources/`. They get copied next to YouTube's own files. If a tweak crashes
the moment it loads, a missing bundle is the most likely reason.

So adding a tweak that has a bundle is: dylib into `YTLPR.bundle/`, its `.bundle` into `Resources/`, one line in `Tweaks.json`.

## Libraries

Files that aren't tweaks but that tweaks use (`libFLEX.dylib`, `CydiaSubstrate.framework`) go in
`Frameworks/`, not in `YTLPR.bundle`. They get copied to the app's Frameworks folder.

## Building

```bash
make
./build-ipa.sh YouTube-decrypted.ipa YTLitePlusRenewed.ipa
```

`build-ipa.sh` takes a decrypted YouTube IPA. If you give it an old YTLitePlusRenewed IPA it removes the old
injected tweaks and TweakLoader first. It also warns you if `Tweaks.json` and the files in
`YTLPR.bundle` don't match.

## Building on GitHub

1. Open the **Actions** tab of the repo and pick **Build IPA**.
2. Press **Run workflow** and paste a direct download link to a decrypted YouTube IPA.
3. When it finishes, the IPA is under **Artifacts** at the bottom of the run page.

The first run takes a few extra minutes to set up Theos; later runs reuse it.

## If YouTube keeps crashing

If YouTube crashes twice in a row while starting, the loader goes into safe mode and loads nothing.
Open Settings > YTLitePlusRenewed, turn off the tweak that's crashing, and restart.

If you made a typo in `Tweaks.json`, a "Problem with Tweaks.json" row at the top of the page tells you what's wrong.

Loader made by [itzzace](https://github.com/itzzace). `Tools/macho_inject.py` and `Tools/list_macho.py` come from [YTKACE](https://github.com/itzzace/ytkace) (MIT).
