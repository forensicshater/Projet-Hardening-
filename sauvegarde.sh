
#!/bin/bash
set -euo pipefail

DEST="/mnt/backup"
SNAPSHOTS="$DEST/snapshots"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
NOUVEAU="$SNAPSHOTS/$DATE"

if [ "$(id -u)" -ne 0 ]; then
    echo "Erreur : exécuter ce script avec sudo."
    exit 1
fi

if ! mountpoint -q "$DEST"; then
    echo "Erreur : le disque de sauvegarde n'est pas monté."
    exit 1
fi

umask 077
mkdir -p "$SNAPSHOTS"

PRECEDENT=$(find "$SNAPSHOTS" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??_??-??-??' | sort | tail -n 1)

mkdir -p "$NOUVEAU/etc" "$NOUVEAU/srv"

if [ -n "$PRECEDENT" ]; then
    rsync -aAXH --numeric-ids --link-dest="$PRECEDENT/etc" /etc/ "$NOUVEAU/etc/"
    rsync -aAXH --numeric-ids --link-dest="$PRECEDENT/srv" /srv/ "$NOUVEAU/srv/"
else
    rsync -aAXH --numeric-ids /etc/ "$NOUVEAU/etc/"
    rsync -aAXH --numeric-ids /srv/ "$NOUVEAU/srv/"
fi

find "$SNAPSHOTS" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??_??-??-??' | sort | head -n -7 | while IFS= read -r ANCIEN; do
    rm -rf -- "$ANCIEN"
done

echo "Sauvegarde terminée : $NOUVEAU"
