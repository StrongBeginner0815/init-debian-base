#!/bin/bash
set -euo pipefail

# Initialisierung der Variablen
LOG_FILE="/download-install-docker-$(date '+%Y-%m-%d-%H-%M-%S').log"

# Funktion zum Umgang mit Fehlern
error_handler() {
  # Ausgabe eines Fehlers und Beenden des Skripts
  echo "FEHLER: $*" >&2
  echo "FEHLER: $*" >> "$LOG_FILE"
  exit 1
}

# Überprüfung, ob das Skript als root ausgeführt wird
echo "Überprüfung der Benutzerrechte..." >> "$LOG_FILE"
if [ "$(id -u)" -ne 0 ]; then
  error_handler "Das Skript muss als root ausgeführt werden."
fi
echo "Benutzerrechte sind korrekt." >> "$LOG_FILE"

# Beginn der Installation von Docker
echo "Beginn der Installation von Docker am $(date)" >> "$LOG_FILE"

# Aktualisierung der Paketliste
echo "Aktualisiere die Paketliste..." >> "$LOG_FILE"
if! apt-get -y update; then
  error_handler "Fehler bei der Aktualisierung der Paketliste"
fi
echo "Paketliste erfolgreich aktualisiert." >> "$LOG_FILE"

# Deinstallation von möglichen Resten
echo "Deinstallation von möglichen Resten..." >> "$LOG_FILE"
for PAKET in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if! sudo apt-get -y remove "$PAKET"; then
    error_handler "Fehler bei der Deinstallation von $PAKET"
  fi
done
echo "Mögliche Reste erfolgreich deinstalliert." >> "$LOG_FILE"

# Hinzufügen des offiziellen Docker-GPG-Schlüssels
echo "Hinzufügen des offiziellen Docker-GPG-Schlüssels..." >> "$LOG_FILE"
if! apt-get -y install ca-certificates curl; then
  error_handler "Fehler bei der Installation von ca-certificates und curl"
fi
if! install -m 0755 -d /etc/apt/keyrings; then
  error_handler "Fehler beim Erstellen des Verzeichnisses /etc/apt/keyrings"
fi
if! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
  error_handler "Fehler beim Herunterladen des Docker-GPG-Schlüssels"
fi
if! chmod a+r /etc/apt/keyrings/docker.asc; then
  error_handler "Fehler beim Ändern der Berechtigungen für den Docker-GPG-Schlüssel"
fi
echo "Offizieller Docker-GPG-Schlüssel erfolgreich hinzugefügt." >> "$LOG_FILE"

# Hinzufügen des Docker-Repositorys zu den Apt-Quellen
echo "Hinzufügen des Docker-Repositorys zu den Apt-Quellen..." >> "$LOG_FILE"
if! echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null; then
  error_handler "Fehler beim Hinzufügen des Docker-Repositorys"
fi
if! apt-get -y update; then
  error_handler "Fehler bei der Aktualisierung der Paketliste nach dem Hinzufügen des Docker-Repositorys"
fi
echo "Docker-Repository erfolgreich zu den Apt-Quellen hinzugefügt." >> "$LOG_FILE"

# Installation von Docker
echo "Installation von Docker..." >> "$LOG_FILE"
if! apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
  error_handler "Fehler bei der Installation von Docker"
fi
echo "Docker erfolgreich installiert." >> "$LOG_FILE"

# Abschlussmeldung
echo "Installation von Docker abgeschlossen am $(date)" >> "$LOG_FILE"
echo "Docker sollte jetzt erfolgreich installiert sein."
