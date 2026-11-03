#!/usr/bin/env bash
# Rebuild HoA's spell effects (Data/patch-z.MPQ) without the launcher, as its Install/Update does.
#
#   hosting/spell-effects.sh --game /path/to/WoW [--version 0.6.2]
#
# Run it after updating HoA's server files. It builds HoA's Kit (tools/telegraphs in the
# hordes-of-azeroth repository, at the installed version) with .NET 10, from `dotnet` if you have
# it or the mcr.microsoft.com/dotnet/sdk:10.0 image with podman. It stops the HoA services while
# it writes, keeps the old patch-z.MPQ next to it, and reruns the gate if setup.sh made one.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
GAME="" VERSION=""
while [ $# -gt 0 ]; do
	case "$1" in
	--game) GAME=$2; shift 2 ;;
	--version) VERSION=$2; shift 2 ;;
	-h | --help) usage ;;
	*) echo "unknown option: $1" >&2; usage 1 ;;
	esac
done
[ -n "$GAME" ] || usage 1
GAME=$(cd "$GAME" && pwd -P)
[ -d "$GAME/Data" ] || { echo "error: $GAME/Data not found" >&2; exit 1; }
VERSION=${VERSION:-$(cat "$GAME/VERSION" 2>/dev/null || true)}
[ -n "$VERSION" ] || { echo "error: no $GAME/VERSION; pass --version" >&2; exit 1; }
VERSION=${VERSION#v}

WORK=$(mktemp -d)
stopped=""
# Whatever happens, the services come back and the scratch folder goes.
cleanup() {
	[ -n "$stopped" ] && { echo "== starting the HoA services"; systemctl --user start hoa.target; }
	rm -rf "$WORK"
}
trap cleanup EXIT
echo "== HoA Kit v$VERSION"
git clone -q --depth 1 --branch "v$VERSION" --filter=blob:none --sparse \
	https://github.com/jonhaldors/hordes-of-azeroth.git "$WORK/src"
git -C "$WORK/src" sparse-checkout set tools/telegraphs
cat >"$WORK/src/Kit.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><LangVersion>latest</LangVersion>
  <Nullable>disable</Nullable><AllowUnsafeBlocks>true</AllowUnsafeBlocks><InvariantGlobalization>true</InvariantGlobalization></PropertyGroup>
</Project>
EOF

running=$(systemctl --user is-active hoa-mangosd 2>/dev/null || true)
if [ "$running" = active ]; then
	echo "== stopping the HoA services"
	systemctl --user stop hoa.target hoa-db hoa-realmd hoa-mangosd hoa-host
	stopped=1
fi
[ -f "$GAME/Data/patch-z.MPQ" ] && cp -p "$GAME/Data/patch-z.MPQ" "$GAME/patch-z.MPQ.previous"

echo "== building and running Kit"
if command -v dotnet >/dev/null && dotnet --list-sdks | grep -q '^10\.'; then
	(cd "$WORK/src" && dotnet build -c Release -o "$WORK/bin" -v q -nologo && dotnet "$WORK/bin/Kit.dll" build "$GAME")
else
	command -v podman >/dev/null || { echo "error: needs the .NET 10 SDK or podman" >&2; exit 1; }
	podman run --rm --security-opt label=disable -v "$WORK:$WORK" -v "$GAME:$GAME" -w "$WORK/src" \
		mcr.microsoft.com/dotnet/sdk:10.0 sh -c "dotnet build -c Release -o $WORK/bin -v q -nologo && dotnet $WORK/bin/Kit.dll build $GAME"
fi

CONF=${XDG_CONFIG_HOME:-$HOME/.config}/hoa-vanilla
if [ -f "$CONF/Caddyfile" ]; then
	echo "== the game files changed: rerun make-gate.py (as setup.sh ran it) and restart hoa-web,"
	echo "   so returning players fetch them fresh"
fi
echo "== done: $(stat -c %s "$GAME/Data/patch-z.MPQ") bytes; the old one is $GAME/patch-z.MPQ.previous"
