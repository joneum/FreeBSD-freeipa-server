#!/bin/sh
#
# Check every port directory in this repository without needing a ports
# tree.  portlint would be the thorough answer, but it runs make(1) and
# that needs the whole infrastructure, which is a ports clone per run.
# What is checked here is what actually goes wrong in a port repository:
# a file that was forgotten, a distinfo that lost a line, a leftover from
# patch(1) that got committed.
#
# usage: ci/check-ports.sh

set -eu

fail=0

note() {
	printf '  %s\n' "$1"
}

bad() {
	printf '  %s\n' "$1" >&2
	fail=1
}

ports=$(find . -name pkg-descr -not -path './.git/*' | sed 's|/pkg-descr$||' | sort)

if [ -z "$ports" ]; then
	echo "no port directory found" >&2
	exit 1
fi

for d in $ports; do
	echo "=== ${d#./}"

	for f in Makefile pkg-descr; do
		if [ ! -f "$d/$f" ]; then
			bad "$f is missing"
			continue
		fi
	done
	[ -f "$d/Makefile" ] || continue

	# the fields every port carries
	for var in PORTNAME MAINTAINER COMMENT WWW; do
		if ! grep -qE "^${var}[?+]?=" "$d/Makefile"; then
			bad "$var is not set in the Makefile"
		fi
	done
	if ! grep -qE '^(PORTVERSION|DISTVERSION)[?+]?=' "$d/Makefile"; then
		bad "neither PORTVERSION nor DISTVERSION is set"
	fi

	# WWW moved out of pkg-descr years ago
	if grep -q '^WWW:' "$d/pkg-descr"; then
		bad "pkg-descr still carries a WWW: line; it belongs in the Makefile"
	fi
	if [ ! -s "$d/pkg-descr" ]; then
		bad "pkg-descr is empty"
	fi

	# distinfo: a TIMESTAMP, and SHA256 and SIZE for every file
	if [ -f "$d/distinfo" ]; then
		if ! head -1 "$d/distinfo" | grep -qE '^TIMESTAMP = [0-9]+$'; then
			bad "distinfo does not begin with a TIMESTAMP line"
		fi
		sums=$(grep -c '^SHA256 (' "$d/distinfo" || true)
		sizes=$(grep -c '^SIZE (' "$d/distinfo" || true)
		if [ "$sums" != "$sizes" ]; then
			bad "distinfo has $sums SHA256 lines and $sizes SIZE lines"
		fi
		if grep -vE '^(TIMESTAMP = [0-9]+|SHA256 \(.+\) = [0-9a-f]{64}|SIZE \(.+\) = [0-9]+)$' \
			"$d/distinfo" | grep -q .; then
			bad "distinfo has a line in neither the TIMESTAMP, SHA256 nor SIZE form"
			grep -nvE '^(TIMESTAMP = [0-9]+|SHA256 \(.+\) = [0-9a-f]{64}|SIZE \(.+\) = [0-9]+)$' \
				"$d/distinfo" | sed 's/^/      /' >&2
		fi
		note "distinfo: $sums distfiles"
	elif grep -qE '^(USE_GITHUB|MASTER_SITES|DISTFILES)[?+]?=' "$d/Makefile" &&
	     ! grep -qE '^NO_DISTFILES' "$d/Makefile"; then
		bad "the Makefile fetches something but there is no distinfo"
	fi

	# every patch has to be named for the file it patches
	if [ -d "$d/files" ]; then
		for p in "$d"/files/patch-*; do
			[ -e "$p" ] || continue
			case $(basename "$p") in
			patch-*) ;;
			*) bad "$(basename "$p") is in files/ but is not named patch-*" ;;
			esac
		done
		note "files/: $(find "$d/files" -type f | wc -l | tr -d ' ') entries"
	fi
done

echo "=== leftovers"
left=$(find . \( -name '*.orig' -o -name '*.rej' -o -name '*~' \) \
	-not -path './.git/*' | sort)
if [ -n "$left" ]; then
	bad "these should not be committed:"
	printf '%s\n' "$left" | sed 's/^/      /' >&2
else
	note "none"
fi

work=$(find . -type d -name work -not -path './.git/*' | sort)
if [ -n "$work" ]; then
	bad "a work directory is committed:"
	printf '%s\n' "$work" | sed 's/^/      /' >&2
else
	note "no work directory"
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "every port holds together"
else
	echo "see the lines above" >&2
fi
exit "$fail"
