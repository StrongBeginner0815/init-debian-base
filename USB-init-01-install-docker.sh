#!/bin/bash

# ========================================
# Projekt: Init-Debian-Base
# Author: https://github.com/StrongBeginner0815
FILENAME="USB-init-01-install-docker.sh"
# Zuständig für die Installation von Docker:
# - entfernt alte Docker-Pakete
# - installiert benötigte Abhängigkeiten
# - richtet das Docker-Repository für Debian ein
# - installiert Docker und zugehörige Tools
# - fügt alle User (außer root) der Docker-Gruppe hinzu
# ========================================

# ======= Konfigurationsvariablen =======
DEPENDENCIES="ca-certificates curl"
GPG_KEY_URL="https://download.docker.com/linux/debian/gpg"
GPG_KEY_PATH="/etc/apt/keyrings/docker.asc"
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"

# ======= Logging konfigurieren =======
LOGFILE="/$(date +'%Y-%m-%d--%H-%M-%S')-$FILENAME.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_success() { log "SUCCESS: $*"; }
log_error()   { log "ERROR: $*"; }
log "==== Docker-Installationsskript gestartet ===="

# ======= Fehlerbehandlung =======
error_exit() {
    log_error "$*"
    exit 1
}
trap 'error_exit "Ein unerwarteter Fehler ist aufgetreten. (Befehl: $BASH_COMMAND)"' ERR

set -o errexit
set -o nounset
set -o pipefail

# ======= Distributionserkennung (nur Debian) =======
if [[ ! -f /etc/debian_version ]]; then
    error_exit "Dieses Skript ist ausschließlich für DEBIAN konzipiert!"
fi
log "Debian-System erkannt."

# ======= Rechte-Prüfung =======
if [[ $EUID -ne 0 ]]; then
    log_error "Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# ======= Alte Docker-Pakete entfernen =======
log "Entferne mögliche alte Docker-Pakete..."
for PAKET in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get -y remove "$PAKET" && log "Altes Paket entfernt: $PAKET" || true
done
log_success "Alte Docker-Pakete entfernt (sofern vorhanden)."

# ======= Abhängigkeiten installieren =======
log "Aktualisiere Paketliste (apt update)..."
apt-get update && log_success "Paketquellen erfolgreich aktualisiert."
log "Installiere benötigte Pakete: $DEPENDENCIES"
apt-get install -y $DEPENDENCIES && log_success "Pakete erfolgreich installiert."

# ======= Docker-GPG-Key & Repository einrichten =======
log "Richte Keyrings-Verzeichnis ein..."
install -m 0755 -d /etc/apt/keyrings

log "Lade Docker-GPG-KEY herunter..."
if curl -fsSL "$GPG_KEY_URL" -o "$GPG_KEY_PATH"; then
    chmod a+r "$GPG_KEY_PATH"
    log_success "Docker-GPG-KEY erfolgreich heruntergeladen und gesetzt."
else
    error_exit "Fehler beim Herunterladen des Docker-GPG-KEYs."
fi

log "Füge Docker-Repository zu den APT-Quellen hinzu..."
# Debian-Release (z.B. bookworm, bullseye) holen:
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=$GPG_KEY_PATH] https://download.docker.com/linux/debian $CODENAME stable" > "$DOCKER_LIST"
log_success "Docker-Repository hinzugefügt."

log "Aktualisiere Paketliste (apt update)..."
apt-get update && log_success "Paketquellen nach Repository-Erweiterung aktualisiert."

# ======= Docker installieren =======
log "Installiere Docker-CE, BuildKit & Compose..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
    log_success "Docker und Komponenten erfolgreich installiert."

# ======= User zur docker-Gruppe hinzufügen (außer root) =======
log "Füge alle Benutzer (außer root) der 'docker'-Gruppe hinzu..."
# Stelle sicher, dass die Gruppe existiert (sollte durch Paket automatisch kommen, aber zur Sicherheit):
getent group docker >/dev/null 2>&1 || groupadd docker

while IFS=: read -r username _ uid _ _ _ home; do
    if [[ $uid -ge 1000 && "$username" != "nobody" && "$username" != "root" ]]; then
        usermod -aG docker "$username"
        log "Benutzer $username zur Gruppe 'docker' hinzugefügt."
    fi
done </etc/passwd
log_success "Benutzer zur Docker-Gruppe hinzugefügt."

log_success "Docker-Installationsskript erfolgreich ausgeführt."

exit 0
