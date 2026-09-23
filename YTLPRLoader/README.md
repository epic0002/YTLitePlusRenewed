# TweakLoader

There are two kinds of tweaks in the IPA:

- **Always on.** Everything in `Frameworks/` is loaded at startup by `TweakLoader.dylib`, same as before.
- **Switchable.** YTKACE, YouMod and Cercube live in `YTLPR.bundle/`. They have switches in
  YouTube Settings under **TweakLoader**, and they start switched off. Changes apply after YouTube restarts
  (there's a Restart YouTube button on the page).

## Testing a new build of a tweak

Replace the dylib in `Frameworks/` with the new one (same file name) and build. That's it.

On GitHub you can do it without touching the repo: when you run **Build IPA**, paste a direct link to the
test dylib in **test_dylib_url**. It replaces `YTLitePlusRenewed.dylib` unless you change **test_dylib_name**.

## Adding an always-on tweak

Put the `.dylib` in `Frameworks/`. If it comes with a `.bundle` folder, put that in `Resources/`.

## Adding a switchable tweak

1. Put the `.dylib` in `YTLPR.bundle/` (not `Frameworks/`, or it will always load).
2. If it has a `.bundle` folder, put that in `Resources/`.
3. Add a line for it in `YTLPR.bundle/Tweaks.json`:

```json
{ "name": "Cercube", "file": "Cercube.dylib", "about": "Downloads, themes and more by Cercube" }
```

## Options for switchable tweaks

| Key | What it does | Needed |
| --- | --- | --- |
| `name` | Name shown on the switch | yes |
| `file` | The dylib's file name in `YTLPR.bundle` | yes |
| `about` | Small text under the name | no |
| `on` | `true` makes it start switched on. Leave it out and it starts off | no |
| `needs` | Files in `YTLPR.bundle` that must load first | no |
| `clashes` | Files in `YTLPR.bundle` that can't run with this one. Turning this on turns those off | no |

## Building

```bash
make
./build-ipa.sh YouTube-decrypted.ipa YTLitePlusRenewed.ipa
```

`build-ipa.sh` takes a decrypted YouTube IPA. It injects `TweakLoader.dylib` and this loader, copies
`Frameworks/`, `Resources/` and `YTLPR.bundle` into the app, and fixes tweaks that link Substrate the
jailbreak way. If you give it an old YTLitePlusRenewed IPA it removes the old injected tweaks first.

## Building on GitHub

1. Open the **Actions** tab of the repo and pick **Build IPA**.
2. Press **Run workflow** and paste a direct download link to a decrypted YouTube IPA.
3. When it finishes, the IPA is under **Artifacts** at the bottom of the run page.

## If YouTube keeps crashing

If YouTube crashes twice in a row while starting, the switchable tweaks are skipped on the next launch.
Open Settings > TweakLoader, turn off the one causing it, and restart.

Loader made by [itzzace](https://github.com/itzzace). `Tools/macho_inject.py` and `Tools/list_macho.py` come from [YTKACE](https://github.com/itzzace/ytkace) (MIT).
