#!/usr/bin/env bash
# Set up hoa-vanilla for several players on this machine, as systemd user services.
#
#   hosting/setup.sh --game /path/to/WoW --accounts accounts.txt [--gate-port 8080] [--host-port 8090]
#
# Before: install HoA's server into the WoW folder with HoA's launcher (press Install once).
# It builds the client, installs the services, turns on the world console, creates a game account
# per line of accounts.txt and writes the login gate. Safe to run again (after an update, or to add
# players). It never touches the internet-facing side: put HTTPS in front of the gate yourself.
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
GAME="" ACCOUNTS="" GATE_PORT=8080 HOST_PORT=8090
while [ $# -gt 0 ]; do
	case "$1" in
	--game) GAME=$2; shift 2 ;;
	--accounts) ACCOUNTS=$2; shift 2 ;;
	--gate-port) GATE_PORT=$2; shift 2 ;;
	--host-port) HOST_PORT=$2; shift 2 ;;
	-h | --help) usage ;;
	*) echo "unknown option: $1" >&2; usage 1 ;;
	esac
done
[ -n "$GAME" ] && [ -n "$ACCOUNTS" ] || usage 1

REPO=$(cd "$(dirname "$0")/.." && pwd -P)
GAME=$(cd "$GAME" && pwd -P)
ACCOUNTS=$(realpath "$ACCOUNTS")
CONF=${XDG_CONFIG_HOME:-$HOME/.config}
GATE_DIR=$CONF/hoa-vanilla
UNITS=$CONF/systemd/user
QUADLETS=$CONF/containers/systemd
RUN=$GAME/server/run

step() { printf '\n== %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

step "Checking"
case "$GAME$REPO" in *" "*) die "a path has a space in it (systemd units can't take it): rename or move the folder" ;; esac
[ -d "$GAME/Data" ] || die "$GAME/Data not found: --game is the WoW 1.12.1 folder"
[ -x "$RUN/mangosd" ] && [ -x "$RUN/realmd" ] && [ -x "$GAME/server/mariadb/bin/mariadbd" ] ||
	die "no HoA server in $GAME/server: run HoA's launcher there and press Install once"
[ -d "$GAME/server/mariadb-data" ] || die "no database in $GAME/server/mariadb-data: let the launcher finish its install"
[ -f "$ACCOUNTS" ] || die "$ACCOUNTS not found (see hosting/accounts.example.txt)"
command -v cargo >/dev/null || die "Rust is missing: install it from https://rustup.rs"
command -v python3 >/dev/null || die "python3 is missing"
command -v systemctl >/dev/null || die "systemd is needed for the services"
if command -v podman >/dev/null; then GATE=podman
elif command -v caddy >/dev/null; then GATE=caddy
else die "the login gate needs podman or caddy"; fi
chmod 600 "$ACCOUNTS"
echo "game $GAME"
echo "repo $REPO, gate via $GATE"

step "Building the client (the first time takes a while)"
cd "$REPO"
scripts/web-setup.sh
scripts/web-build.sh
cargo build --release -p wenilla-host

step "World console"
# The launcher rebuilds mangosd.conf from config/mangosd.overrides.conf, so set it in both.
for f in "$RUN/mangosd.conf" "$GAME/config/mangosd.overrides.conf"; do
	[ -f "$f" ] || continue
	if grep -q '^Console.Enable' "$f"; then sed -i 's/^Console.Enable.*/Console.Enable = 1/' "$f"
	else echo 'Console.Enable = 1' >>"$f"; fi
done
touch "$RUN/console.in"

step "Services"
mkdir -p "$UNITS" "$GATE_DIR"
for f in hoa.target hoa-db.service hoa-realmd.service hoa-mangosd.service hoa-host.service; do
	sed -e "s#%h/hoa/hoa-vanilla#$REPO#g" -e "s#%h/hoa/game#$GAME#g" -e "s#%h/hoa#$REPO#g" \
		-e "s#127.0.0.1:8090#127.0.0.1:$HOST_PORT#g" "$REPO/hosting/systemd/$f" >"$UNITS/$f"
done
if [ "$GATE" = podman ]; then
	mkdir -p "$QUADLETS"
	sed "s#%h/hoa/Caddyfile#$GATE_DIR/Caddyfile#" "$REPO/hosting/systemd/hoa-web.container" >"$QUADLETS/hoa-web.container"
else
	cat >"$UNITS/hoa-web.service" <<EOF
[Unit]
Description=Hordes of Azeroth browser build, password gate
[Service]
ExecStart=$(command -v caddy) run --config $GATE_DIR/Caddyfile --adapter caddyfile
Restart=always
[Install]
WantedBy=default.target
EOF
fi
systemctl --user daemon-reload
systemctl --user enable hoa.target >/dev/null
systemctl --user restart hoa.target

step "Waiting for the world server"
for _ in $(seq 120); do (exec 3<>/dev/tcp/127.0.0.1/8085) 2>/dev/null && break; sleep 2; done
(exec 3<>/dev/tcp/127.0.0.1/8085) 2>/dev/null || die "mangosd is not answering on 8085: journalctl --user -u hoa-mangosd"
# Realm list: the browser reaches the world server through wenilla-host, on this machine.
"$GAME/server/mariadb/bin/mariadb" -h 127.0.0.1 -P 3306 -u root -proot --skip-ssl realmd -e \
	"UPDATE realmlist SET address = '127.0.0.1', port = 8085"

step "Game accounts"
# One console command at a time; creating an account that already exists is just an error in the log.
grep -v '^#' "$ACCOUNTS" | while read -r name password; do
	[ -n "$name" ] || continue
	echo "account create $name $password" >>"$RUN/console.in"
	sleep 4
	# For an account that already existed: bring its password in line with accounts.txt.
	echo "account set password $name $password $password" >>"$RUN/console.in"
	echo "  $name"
	sleep 4
done
: >"$RUN/console.in"

step "Login gate"
python3 -I "$REPO/hosting/make-gate.py" "$ACCOUNTS" "$GATE_DIR/Caddyfile" --data "$GAME/Data" \
	--listen "127.0.0.1:$GATE_PORT" --host "127.0.0.1:$HOST_PORT"
systemctl --user daemon-reload
systemctl --user restart hoa-web

step "Done"
echo "The gate is on http://127.0.0.1:$GATE_PORT/ (log in with a line from $(basename "$ACCOUNTS"))."
echo "Next: put HTTPS in front of it (README, step 5) and send your friends the link."
echo "To keep it running after you log out: loginctl enable-linger $USER"
