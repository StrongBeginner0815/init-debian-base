#!/bin/bash

# ========================================
# Projekt: Init-Debian-Base
# Author: https://github.com/StrongBeginner0815
FILENAME="download-init_Script.sh"
# Zuständig für das Herunterladen des init_and_reboot-Scripts:
# - lädt das eigentliche Init-Script herunter,
# - richtet den Autostart per rc.local ein.
# ========================================

# ======= Konfigurationsvariablen =======
DEPENDENCIES="curl"
DOWNLOAD_URL="https://raw.githubusercontent.com/StrongBeginner0815/init-debian-base/refs/heads/main/init_and_reboot.sh"
TARGET_SCRIPT="/usr/local/sbin/init_and_reboot.sh"
RC_LOCAL="/etc/rc.local"

# ======= Logging konfigurieren =======
LOGFILE="/$(date +'%Y-%m-%d--%H-%M-%S')-$FILENAME.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_success() { log "SUCCESS: $*"; }
log_error()   { log "ERROR: $*"; }
log "==== Download-Skript gestartet ===="

# ======= Fehlerbehandlung =======
error_exit() {
    log_error "$*"
    exit 1
}
trap 'error_exit "Ein unerwarteter Fehler ist aufgetreten. (Befehl: $BASH_COMMAND)"' ERR

set -o errexit
set -o nounset
set -o pipefail

# ======= Rechte-Prüfung =======
if [[ $EUID -ne 0 ]]; then
    log_error "Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# ======= Abhängigkeiten installieren =======
log "Aktualisiere Paketliste (apt update)..."
apt-get update && log_success "Paketquellen erfolgreich aktualisiert."
log "Installiere benötigte Pakete: $DEPENDENCIES"
apt-get install -y $DEPENDENCIES && log_success "Pakete erfolgreich installiert."

# ======= Prüfe, ob curl installiert ist =======
if ! command -v curl >/dev/null 2>&1; then
    error_exit "curl ist nicht installiert!"
fi

# ======= Initialisierungsscript herunterladen =======
log "Lade Initialisierungsskript von $DOWNLOAD_URL herunter..."
if curl -sfSL "$DOWNLOAD_URL" -o "$TARGET_SCRIPT"; then
    chmod 700 "$TARGET_SCRIPT"
    log_success "Initialisierungsskript($TARGET_SCRIPT) erfolgreich heruntergeladen und ausführbar gemacht."
else
    error_exit "Download von $DOWNLOAD_URL nach $TARGET_SCRIPT fehlgeschlagen!"
fi

# ======= Autostart über rc.local einrichten =======
log "Richte Autostart über rc.local für $TARGET_SCRIPT ein..."
cat >"$RC_LOCAL" <<EOF
#!/bin/bash
if [ -f "$TARGET_SCRIPT" ]; then
    exec $TARGET_SCRIPT
else
    echo "ERROR: $TARGET_SCRIPT nicht gefunden!" >&2
    exit 1
fi
EOF

chmod 755 "$RC_LOCAL" && log_success "rc.local für $TARGET_SCRIPT gesetzt." || error_exit "Setzen von rc.local fehlgeschlagen."

log_success "Download-Skript erfolgreich ausgeführt."

exit 0
