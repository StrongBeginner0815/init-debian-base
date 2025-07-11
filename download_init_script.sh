#!/bin/bash
set -euo pipefail

DOWNLOAD_URL="https://raw.githubusercontent.com/StrongBeginner0815/init-debian-base/refs/heads/main/init_and_reboot.sh"
TARGET_SCRIPT="$target/usr/local/sbin/init_and_reboot.sh"
RC_LOCAL="$target/etc/rc.local"

error_exit() {
    echo "ERROR: $*" >&2
    exit 1
}

# Prüfe, ob curl installiert ist
if ! command -v curl >/dev/null 2>&1; then
    error_exit "curl ist nicht installiert!"
fi

# Lade das Initialisierungsscript herunter
if ! curl -sfSL "$DOWNLOAD_URL" -o "$TARGET_SCRIPT"; then
    error_exit "Download von $DOWNLOAD_URL nach $TARGET_SCRIPT fehlgeschlagen!"
fi

chmod 700 "$TARGET_SCRIPT" || error_exit "Setzen der Ausführungsrechte auf $TARGET_SCRIPT fehlgeschlagen!"

# Erstelle /etc/rc.local für Autostart
cat >"$RC_LOCAL" <<EOF
#!/bin/bash
if [ -f "/usr/local/sbin/init_and_reboot.sh" ]; then
    exec /usr/local/sbin/init_and_reboot.sh
else
    echo "ERROR: /usr/local/sbin/init_and_reboot.sh nicht gefunden!" >&2
    exit 1
fi
EOF

chmod 755 "$RC_LOCAL" || error_exit "Setzen der Ausführungsrechte auf $RC_LOCAL fehlgeschlagen!"

exit 0
