<div align="center">
  <h1>hoa-vanilla</h1>
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
- **Linux** with Rust (`rustup`) and a C compiler. Building needs no root.
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

### 1. Pick the players

Copy [`hosting/accounts.example.txt`](hosting/accounts.example.txt) to `accounts.txt`, one
`name password` per line (letters and digits only). Each line is both a website login and a game
account with the same password. Keep this file private (`chmod 600`) and out of git.

### 2. Create their game accounts

`mangosd` takes commands on its console. Turn it on with `Console.Enable = 1` in
`<game>/server/run/mangosd.conf`. The example unit feeds the console from a file, so you can
type commands without a terminal attached:

```bash
echo "account create thrall ChangeMe123" >> <game>/server/run/console.in
```

Send one command per line and give each a few seconds. Use the same names and passwords as in
`accounts.txt`.

### 3. Make the gate

```bash
python3 -I hosting/make-gate.py accounts.txt Caddyfile --data <game>/Data
```

This writes a `Caddyfile` (mode 600, it holds the passwords) that listens on `127.0.0.1:8080`
and passes everything on to `wenilla-host`. Run it whenever you change `accounts.txt`, then
restart the gate. Run it again after an update that changes the game's MPQs: the gate tags the
game files, so returning players fetch the changed ones instead of keeping old copies. Options:
`--listen` and `--host` if you use other ports.

### 4. Run it all

[`hosting/systemd/`](hosting/systemd/) has user units for the whole stack. They assume this
layout (change the paths if yours differs):

```
~/hoa/game          the WoW folder HoA's launcher installed into
~/hoa/hoa-vanilla   this repository, built
~/hoa/Caddyfile     the gate, from make-gate.py
```

```bash
cp hosting/systemd/*.service hosting/systemd/hoa.target ~/.config/systemd/user/
cp hosting/systemd/hoa-web.container ~/.config/containers/systemd/     # the gate, via podman
systemctl --user daemon-reload
systemctl --user start hoa.target hoa-web
```

`hoa.target` starts the database, `realmd`, `mangosd` and `wenilla-host`. `hoa-web` is the gate
(Caddy in podman; any Caddy 2 works).

### 5. Put HTTPS in front

Point a domain at your machine and let a reverse proxy with TLS forward to `127.0.0.1:8080`.
With Caddy that's all of it:

```
hoa.example.com {
	reverse_proxy 127.0.0.1:8080
}
```

Send your friends the link and their name and password.

### Co-op

Players on the same server see each other. `/invite` groups them, and the group shares one run
(same horde, levelling up together). No launcher is needed for it.

### Updates

When HoA releases a new version, update the server files the way the launcher does (or run the
launcher's **Update** once, with the server stopped), then pull this repository and rebuild the
client. The launcher also rebuilds `Data/patch-z.MPQ` (HoA's spell effects); without it, run HoA's
Kit yourself (`tools/telegraphs` in the HoA repository, `dotnet` and `build <game>`). Then rerun
`make-gate.py`. Server and client should be on the same HoA version. Back up the `characters` and
`realmd` databases first.

## Status

Solo runs work in Chrome and Firefox, and a two-player co-op run has worked in Chrome. Not tested
yet: 3–4 players at once.

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
