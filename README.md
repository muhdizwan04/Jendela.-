# Jendela

A native, low-energy macOS desktop companion.

## Design rule

**No polling unless macOS gives us no alternative, and every unavoidable timer
carries a tolerance.** A background app costs battery through CPU *wakeups*, not
through work, so:

- Music metadata arrives on distributed notifications from Music.app and
  Spotify — zero polling.
- Volume, mute and output-device changes arrive on CoreAudio property
  listeners — zero polling.
- Low Power Mode, thermal pressure and battery/AC state arrive on system
  notifications — zero polling.
- The clipboard is the one exception: macOS publishes no pasteboard-change
  notification. It is checked on a timer that reads only the change counter,
  stretches from 1s to 3s to 8s depending on whether the hub is open and
  whether the machine is conserving, and sets a 50% tolerance so the wakeup is
  coalesced with other timers rather than waking the CPU on its own.
- Live blur is used only when not conserving power; the panel falls back to a
  flat fill otherwise.

`Battery saver` has three modes. **Automatic** (the default) follows Low Power
Mode, battery vs AC, and thermal state.

## The notch hub

Collapsed it is invisible and exactly the width of the physical notch, with a
14pt lip hanging below the menu bar — the menu-bar strip and the cut-out itself
do not reliably deliver mouse events, so that lip is the hover target.

Expanded, it is **one opaque black surface, the same black as the notch**, with
no material and no border. A tint or a stroked edge is what makes a panel read
as a separate window hanging below the notch instead of the notch itself
growing, so neither is used. Its controls are inset below the menu bar for the
same hit-testing reason.

Which tabs it carries is up to you — Notch Hub › *What the hub shows*. It keeps
at least one, and resizes to whichever tab is open.

## What works

- The notch hub is the product. Everything else supports it.
- **A theme can set a real desktop picture** — the gradient is rendered
  once to a PNG per display and handed to the window server, after which it
  costs nothing
- A compact notch hub sized from the **real** notch (`auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`), not a percentage of the screen width, so it lines up
  exactly on any Mac. Collapsed it reads as a slightly deeper notch; it hangs a
  14pt lip below the menu bar because the menu-bar strip and the notch cut-out
  do not reliably deliver mouse events, and that lip is the hover target.
  Expanded, its controls are inset below the menu bar for the same reason.
  The panel is sized to whichever section is showing, and is pinnable
- **Hide the notch**, the way TopNotch does it: the menu-bar strip of your
  desktop picture is painted pure black, so the camera cut-out blends into it.
  Your own wallpaper is used as the source and aspect-filled exactly as macOS
  fits it, so nothing is reframed; the original path is remembered and put back
  when you switch it off. Rendered once to a PNG and handed to the window
  server, so it costs nothing while it is on
- Quick Notes rendered at desktop-icon level, behind normal apps (off by
  default)
- Clipboard history with search, pinning, click-to-paste and drag-to-copy.
  Items marked concealed by password managers are skipped. Images over 8 MB are
  recorded but not stored (truncating them produced a corrupt paste)
- Real now-playing metadata and transport control for Music and Spotify. If
  macOS denies Automation, the UI says so instead of showing a state it cannot
  verify
- **YouTube Music transport** via the system media keys — it is a web page with
  no scripting interface, so the media keys (which browsers honour) are the only
  way to drive it. This needs Accessibility permission; the UI says so when it
  is missing. Track metadata for YouTube Music is not available without private
  API, so none is claimed
- Real system volume, mute and output-device switching
- A working 25-minute focus timer
- A menu bar controller, and all settings persist

## Run

```bash
./run-macos.sh
```

Builds the package, quits any running instance, refreshes the local `.app`,
re-signs it so the Automation grant survives rebuilds, and opens it.

## Desktop widgets (WidgetKit)

Four system-managed widgets ship in an embedded extension: **Quick Note**,
**Clipboard**, **Theme Clock** and **Photo**. Add them from the desktop widget
gallery
(right-click the desktop → Edit Widgets → Jendela).

They are on WidgetKit rather than custom always-on windows because the system
then owns their power budget — a widget costs nothing when it is not updating.
The timeline policy is `.never`: the app writes a snapshot to the App Group
container and calls `reloadAllTimelines()` only when the content actually
changes, so the widget process is never woken on a schedule. The clock uses
`Text(_:style:)`, which WidgetKit renders live without reloading at all.

The Photo widget rotates the same way — as a *timeline*, not a timer. WidgetKit
gets one entry per picture with the time it should appear and switches them
itself, so a rotating photo widget costs the same as a static one. Photos are
copied into the App Group and downscaled to a 1400px long edge once on import,
so the widget never resizes an image while drawing. Add them under **Photos** in
the Studio.

Two things are load-bearing and worth knowing before changing them:

- **The widget extension must be sandboxed.** WidgetKit will not register an
  unsandboxed `.appex` at all — it simply never appears in `pluginkit`.
- Because it is sandboxed, it cannot read Application Support, so the app and
  the widget share data through the App Group
  `FRWW9Y9Y94.com.widgetmac.desktop`.

## Building

`./run-macos.sh` builds through Xcode, because SwiftPM cannot produce an
`.appex`. The `.xcodeproj` is **generated** by `Support/generate_project.rb` —
nothing in it is hand-maintained, so re-run that script after adding a source
file. `swift build` still compiles the app on its own, without widgets.

## Running it

Three pieces, each its own npm project. There is nothing to install: the dev
server is a single file using only Node built-ins, so a fresh checkout runs
immediately and there is no lockfile to keep current.

    npm run dev              # all three together, labelled, one Ctrl-C stops them

    cd web    && npm run dev # landing page      → localhost:3000
    cd admin  && npm run dev # dashboard         → localhost:3001
    cd server && npm run dev # API               → localhost:8787

The two front ends proxy `/api` to the server, so the browser sees a single
origin. Without that the session cookie would not be sent and every signed-in
page would look signed out in development while working in production — a
miserable class of bug to chase.

`shared/` holds the stylesheet and the icon, served by both front ends and by
the API in production, so there is one copy to change.

The download button and version line read `appcast.json` — the same file
`Support/release.sh` writes and the app checks for updates — so the site
can never advertise a build that was not actually published. Before a
release the page says so instead of offering a dead link.

To deploy: upload the contents of `web/` plus the dmg from `dist/` to any
static host (Cloudflare Pages, Netlify, GitHub Pages). Point
`DOWNLOAD_BASE` in `Support/release.env` at wherever the dmg lands.

## Accounts and licences

`server/` is a zero-dependency Node service: `node:http` and `node:sqlite`,
no packages to audit or keep patched, and the whole database is one file.

    cp server/.env.example server/.env    # fill in
    ./server/run.sh                       # serves the site and the API together

With no email provider configured the sign-in link is printed to the
console, so the entire purchase and sign-in flow can be exercised locally
without an account anywhere.

Sign-in is a magic link — there is no password to choose, forget or leak —
and the response is identical whether or not the address has an account, so
the page cannot be used to discover who is a customer. Sessions are
HttpOnly cookies.

Payment webhooks are HMAC-verified; an unverified webhook would let anyone
mint themselves a licence. Retries are idempotent on the provider's order
id, refunds mark the licence refunded, and the same Ed25519 key the app
verifies with signs the key that is issued.

`server/test.mjs` covers that end to end, and a Swift test takes a licence
the server issued and checks the app accepts it — if the two ever disagreed
on key format, every customer would pay and then be refused.

### The signing key

`jendela-licence-private.key` signs every licence. The app carries only the
matching public key, so it can verify a licence with no network — which is
what makes a lifetime licence honest, and what makes this one file the most
important thing in the repository.

It is gitignored and `chmod 600`. Two things follow from that:

- **Anyone holding it can mint unlimited licences.** Keep it out of
  backups that sync somewhere shared, screenshots and pasted logs.
- **Losing it strands every customer.** The public key is compiled into
  every copy of the app already installed. A new signing key means those
  builds reject every licence issued afterwards, so the only way back is
  shipping an update and reissuing to everyone. Keep an offline copy
  somewhere you will still have in five years.

Issue a key by hand with:

    swift Support/licence_tool.swift sign jendela-licence-private.key <email> [days]

Omit the days for a lifetime licence. The app reads a key from the keychain,
falling back to `~/Library/Application Support/Jendela/.licence-key`, so a
key can be installed without going through the UI.

### Dashboard

`/admin.html`, restricted to the single address in `ADMIN_EMAIL`, signing
in through the same magic link as everyone else — one way in, and it is the
one already covered by tests. Every admin endpoint re-checks on the
request; hiding the page would not be security.

It shows active licences, gross, downloads and purchases per day, recent
licences, customer search, manual issuing and revoking.

It deliberately shows no install or trial numbers. The app never contacts
the server, so those figures do not exist — a funnel between downloads and
purchases would be a guess presented as a measurement. Revoking is honest
about its limits too: it marks the row, but a key already on someone's Mac
keeps working, because licences verify offline.

## Releasing

`./Support/release.sh --check` reports whether a release is possible and
changes nothing. The full run builds Release, signs with Developer ID,
verifies the entitlements, packages a dmg, notarises, staples both the app
and the dmg, and writes `dist/appcast.json` for the in-app update check.

It refuses to build rather than producing something unshippable: an Apple
Development certificate cannot be notarised, and `get-task-allow` in the
signature is rejected by the notary service. Both are caught before the
slow steps rather than after a four-minute upload.

Configuration lives in `Support/release.env` (gitignored); copy
`release.env.example`. A paid Apple Developer Program membership is
required for the Developer ID certificate.

## Not implemented

Being explicit about what is still a mock:

- **Discord call state.** The camera and share switches drive the mini view
  manually. Reading real call state requires a registered Discord application
  and your authorisation through Discord's RPC interface; the app does not
  inspect your camera or screen in the background. Discord's *running* state is
  detected and shown.
- **Icon packs and screen savers.** Gallery previews only; neither changes
  anything on disk yet.
- **Icon packs and screen savers** remain gallery previews.
