#!/bin/bash
set -euo pipefail
DESTINATION=${1:?Provide a scratch directory}
curl --fail --silent --show-error --max-time 120 --output "$DESTINATION/bank.deb" \
  https://deb.debian.org/debian/pool/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_all.deb
ar -p "$DESTINATION/bank.deb" data.tar.xz | tar -xJf - -C "$DESTINATION" ./usr/share/sounds/sf2/TimGM6mb.sf2
BANK="$DESTINATION/usr/share/sounds/sf2/TimGM6mb.sf2"
printf '%s  %s\n' c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854 "$BANK" | shasum -a 256 -c >&2
printf '%s\n' "$BANK"
