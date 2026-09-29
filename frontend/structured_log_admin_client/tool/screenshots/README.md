# Screenshots for the user guide

Regenerates every picture in
[`docs/guides/user-guide.md`](../../../../docs/guides/user-guide.md).

```bash
npm install
npm run shoot -- --build
```

That writes all 26 files into `docs/guides/assets/user-guide/`. Without
`--build` it uses whatever is already in `build/web`, which is what you want
while iterating on a scene. `--out <dir>` writes somewhere else — useful for
comparing a run against the committed set before replacing it. `--only 07`
limits the run to the screenshots whose name starts with that.

Needs Chrome. It is looked up at the usual macOS path; set `CHROME_PATH` for
anywhere else.

## What it drives

`test_driver/guide_app.dart` — the shipped application on the mocked network
from `lib/testing/mock_server.dart`, seeded by `test_driver/guide_fixture.dart`.

No server, no database, no CORS. The previous version of this script drove a
live stand, which is why it was never committed and why the pictures could
not be reproduced: by the time anyone wanted to regenerate one, the stand and
its data were gone. A fixture in the repository can be read, reviewed and
changed; an afternoon's stand cannot.

Two query parameters choose who is looking: `?stage=onboarding` is signed out
with a temporary password (the first three pictures), `?as=user` is a plain
`user` rather than an administrator (the navigation one). Everything else is
the administrator `bob`.

## How it finds things

By the semantics tree, not by coordinates. Flutter paints into a canvas, so a
coordinate-driven script is guessing where a widget settled — the failure
`test_driver/live_app.dart` documents at length. `guide_app.dart` calls
`ensureSemantics()`, which puts a `<flt-semantics>` element carrying its label
behind every control, and the scenes name what they want.

Three things that cost an afternoon to find out, so they are worth knowing
before editing a scene:

- **A parent node carries all of its children's text.** Matching without
  excluding parents clicks the middle of the screen. `find` only considers
  leaves.
- **Typing goes through the semantics element, and only into a focused one.**
  Synthetic key events land nowhere: DOM focus returns to `<flutter-view>`
  immediately. `type` clicks the field (which is what makes the framework
  consider it active) and then sets the value and fires `input`, the way a
  screen reader does. Setting a second field without focusing it changes
  nothing at all — a sign-in with the right password still failed.
- **A popup menu is not in the tree.** Fluent's combo box renders its items in
  a layer the semantics tree does not describe, so the level filter is chosen
  with the keyboard.

Text fields have no accessible name of their own — the label is a separate
line of text above the input — so `type` finds the label and then takes the
next field. That is worth fixing in `AdminTextField` rather than here: a
screen reader announces nothing for those fields either.

## When a scene breaks

It will, and usually because a button was renamed. The run leaves
`_failed.png` in the output directory and prints every label the screen was
offering, which is normally enough to see what the control is called now.
