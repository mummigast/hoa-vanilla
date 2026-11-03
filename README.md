<div align="center">
  <h1>hoa-wenilla</h1>
  <p><b>Hordes of Azeroth, played in a browser tab</b></p>
</div>

[Hordes of Azeroth](https://github.com/jonhaldors/hordes-of-azeroth) (HoA) is a survivors-style
game mode for World of Warcraft 1.12.1: an endless horde, spells that fire on their own, and a
choice at every level-up, alone or in co-op with up to 3 friends. Normally you play it with its
launcher, a desktop client and a server on your own PC.

This repository builds HoA's client for the **browser** (WebAssembly + WebGPU), so you can host
it once and let your friends play from a link, with nothing to install on their side.

> [!NOTE]
> **A personal project.** This was made so a couple of friends could play together in the browser.
> It is shared as-is, in case it's useful to someone else: no support, no roadmap, no promises.
>
> **Mostly written by Claude**, Anthropic's AI, with a human deciding what to build and testing it.
>
> **All the real work is upstream.** The game, its content, balancing and fixes come straight from
> [Hordes of Azeroth](https://github.com/jonhaldors/hordes-of-azeroth),
> [wenilla](https://github.com/Arnesen/wenilla) and [benilla](https://github.com/samwhosung/benilla),
> merged in as they release. This repository only adds the glue to run HoA in a browser. Bugs or
> ideas about the game itself belong with those projects, and the credit goes to their authors.

## Where it comes from

Three projects, merged:

| project | what it is | what we use |
|---|---|---|
| [benilla](https://github.com/samwhosung/benilla) | a WoW 1.12.1 client written from scratch in Rust and Bevy | the client itself |
| [HoA client](https://github.com/jonhaldors/hordes-of-azeroth-client) | HoA's fork of benilla: its plugin, UI and co-op | HoA's game mode |
| [wenilla](https://github.com/Arnesen/wenilla) | a fork of benilla that builds for the browser | the browser build and `wenilla-host` |

Branch `web` is wenilla's `main` with HoA's client changes replayed on top, plus a few small
fixes of our own, needed only in the browser (all `#[cfg(target_arch = "wasm32")]`):

- `crates/wenilla`: the browser entry runs HoA's plugin.
- `benilla-app/src/ui_script/addons.rs`: loads addons named in `Interface\AddOns\wenilla-addons.txt`,
  since a web page has no AddOns folder to scan.
- `hoa/src/coop_lua.rs`: co-op calls run inline (a web page has no threads; `thread::spawn`
  froze it at character select).
- `loading_screen/hold.rs`: never withhold the frame during a long same-map teleport (froze the page).
- `wenilla-host --overlay DIR`: serves HoA's loose `Interface\GlueXML` and `Interface\AddOns`
  files over the MPQ chain, the way the desktop client reads them next to `Data`.

New HoA releases and new wenilla commits are merged into `web` as they come out.

## What you need

- **World of Warcraft 1.12.1 (build 5875), English (enUS)**, a copy used only for this.
  Nothing here includes the game.
- **HoA's server**, installed by HoA's own launcher into that game folder: download
  [the Linux launcher](https://github.com/jonhaldors/hordes-of-azeroth/releases/latest), unpack it next to
  `WoW.exe`, start it and press **Install** once. It adds the server, its MariaDB, the
  addon and the login screen files. After that you run the server yourself (below), not the launcher.
- **Linux** with systemd, Rust (`rustup`), a C compiler, and podman (or Caddy) for the login gate.
  Building needs no root. Built and run on **Bazzite** (Fedora-based); other distributions should
  work but haven't been tried. Paths must not contain spaces.
- **A browser with WebGPU** for the players: current Chrome or Edge (Linux Chrome may need WebGPU switched on in
  `chrome://flags`); recent Firefox has worked too. The page
  must be served over **HTTPS** (or `localhost`), since browsers only allow WebGPU there.

## Build

```bash
scripts/web-setup.sh                                 # once: wasm target, wasm-bindgen, wasi-sdk
scripts/web-build.sh                                 # the client → web/dist/
cargo build --release -p wenilla-host                # the small web server
```

## Play alone (the simple way)

HoA is set up for one player: the launcher creates one game account and writes it into
`Interface\GlueXML\BonkAccount.lua`, and the login screen signs you in with it.

1. Start the server: MariaDB, `realmd` and `mangosd` from `<game>/server` (the units in
   [`hosting/systemd/`](hosting/systemd/) show exactly how).
2. Start the web server, on loopback only:
   ```bash
   target/release/wenilla-host --www web/dist --data <game>/Data --overlay <game>
   ```
3. Open http://127.0.0.1:8090/ in a WebGPU browser.

> [!WARNING]
> `wenilla-host` serves the game files and the game ports to anyone who can reach it, **with no
> login**. Never expose it to the internet as it is. To let others in, use the setup below.

## Host it for several players

To let friends play, each with their own account and characters, put a login in front of
`wenilla-host`. The login (a small [Caddy](https://caddyserver.com) server) does two jobs:

1. **It keeps strangers out.** Everyone signs in with a name and password first.
2. **It gives each player their own game account.** When the login screen asks for
   `BonkAccount.lua`, the gate answers with *that player's* account instead of the launcher's
   single one, so everyone is signed into the game automatically as themselves.

```
browser ─HTTPS─ your proxy (TLS) ─ gate: Caddy login (127.0.0.1:8080)
                                       └─ wenilla-host (127.0.0.1:8090)
                                            ├─ /          the client (web/dist)
                                            ├─ /data/*    game files + HoA's overlay
                                            └─ /ws/*      → realmd :3724, mangosd :8085
```

Everything listens on `127.0.0.1`; only your HTTPS proxy faces the internet.

### Quick setup

1. Install HoA's server into your WoW folder with its launcher (**Install**, once).
2. Copy [`hosting/accounts.example.txt`](hosting/accounts.example.txt) to `accounts.txt` and
   write one `name password` per player (letters and digits only). Each line is both their
   website login and their game account. Keep the file private and out of git.
3. Run:
   ```bash
   hosting/setup.sh --game /path/to/WoW --accounts accounts.txt
   ```
   It builds the client, installs the services (systemd user units), turns on the world
   console, creates the game accounts and starts the login gate on `127.0.0.1:8080`. Run it
   again to add players or after an update; it's safe to repeat.
4. Put HTTPS in front (below) and send your friends the link and their name and password.
5. To keep it running after you log out: `loginctl enable-linger $USER`.

### HTTPS

Point a domain at your machine and let a reverse proxy with TLS forward to `127.0.0.1:8080`.
With Caddy that's all of it:

```
hoa.example.com {
	reverse_proxy 127.0.0.1:8080
}
```

<details>
<summary><b>What setup.sh does, by hand</b></summary>

- **Build:** `scripts/web-setup.sh`, `scripts/web-build.sh`, `cargo build --release -p wenilla-host`.
- **World console:** `Console.Enable = 1` in `<game>/server/run/mangosd.conf` and in
  `<game>/config/mangosd.overrides.conf` (the launcher rebuilds the first from the second). The
  unit feeds the console from `<game>/server/run/console.in`.
- **Services:** the files in [`hosting/systemd/`](hosting/systemd/), with `%h/hoa/game` replaced
  by your WoW folder and `%h/hoa/hoa-wenilla` by this repository, go to
  `~/.config/systemd/user/`; `hoa-web.container` (the gate in podman) to
  `~/.config/containers/systemd/`. `hoa.target` starts MariaDB, `realmd`, `mangosd` and
  `wenilla-host`.
- **Realm list:** `UPDATE realmd.realmlist SET address = '127.0.0.1', port = 8085`.
- **Accounts:** one `account create NAME PASSWORD` per line appended to `console.in`, a few
  seconds apart.
- **Gate:** `python3 -I hosting/make-gate.py accounts.txt <Caddyfile> --data <game>/Data`. It
  writes the Caddyfile (mode 600: it holds the passwords) with the per-player
  `BonkAccount.lua` and a tag on the game files, so returning players fetch changed files
  instead of keeping old copies. `--listen` and `--host` change the ports.

</details>

### Co-op

Players on the same server see each other. `/invite` groups them, and the group shares one run
(same horde, levelling up together). No launcher is needed for it.

### Updates

When HoA releases a new version:

1. Back up the `characters` and `realmd` databases.
2. Stop the services (`systemctl --user stop hoa.target hoa-web`), open the launcher and press
   **Update**. It updates the server and rebuilds the spell effects (`Data/patch-z.MPQ`).
3. `git pull` here, then run `hosting/setup.sh` again: it rebuilds the client and the gate's
   file tag and starts everything.

Server and client should be on the same HoA version. If you update the server files without the
launcher, rebuild the spell effects yourself with `hosting/spell-effects.sh --game /path/to/WoW`
(it builds HoA's own Kit with .NET 10, or in a podman container).

## Status

Solo runs work in Chrome and Firefox, a two-player co-op run has worked in Chrome, and it stays
smooth with a big horde on screen. Not tested yet: 3–4 players at once.

## Troubleshooting

| what you see | why, and what to do |
|---|---|
| black page, or it stops at world entry | no WebGPU: use current Chrome or Edge; on Linux, turn on WebGPU in `chrome://flags` |
| "WebGPU" errors over plain `http://` on another machine | browsers only allow WebGPU on HTTPS or `localhost`: put HTTPS in front |
| asked for a login, then the game's login screen fails | the game account is missing or has another password: rerun `setup.sh` |
| new spells look wrong after an update | the spell effects are older than the server: `hosting/spell-effects.sh` |
| a player still sees old files after an update | rerun `setup.sh` (or `make-gate.py`) so the gate's file tag changes |
| the page freezes when you pick Quit | known; close the tab instead (the server saves when you leave) |
| services stop when you log out | `loginctl enable-linger $USER` |
| anything else | `journalctl --user -u hoa-mangosd -u hoa-realmd -u hoa-host -u hoa-web` |

## Credits and licences

- Client code by [benilla](https://github.com/samwhosung/benilla) and its contributors,
  [HoA](https://github.com/jonhaldors/hordes-of-azeroth-client) and
  [wenilla](https://github.com/Arnesen/wenilla): MIT or Apache 2.0, at your option
  ([LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE)). Our changes are under the same terms.
- HoA's server, addon and launcher come from
  [hordes-of-azeroth](https://github.com/jonhaldors/hordes-of-azeroth) under GPL-3.0 and
  aren't included here.
- For how the browser build works, see [`web/README.md`](web/README.md),
  [`AGENTS.md`](AGENTS.md) and wenilla's own README.

This is a fan project, not affiliated with or endorsed by Blizzard Entertainment. It ships no
Blizzard content: you bring your own 1.12.1 client. World of Warcraft is a trademark of
Blizzard Entertainment, Inc.
