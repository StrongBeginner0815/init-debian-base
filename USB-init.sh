#!/bin/bash

# ========================================
# Projekt: Init-Debian-Base
# Author: https://github.com/StrongBeginner0815
FILENAME="USB-init.sh"
# Zuständig für die Ausführung von spezifischen Init-Scripten auf USB-Sticks:
# - alle Partitionen angeschlossener Blockgeräte mounten (und später wieder unmounten) die nicht gemountet sind
# - alle Partitionen nach spezifisch benannten Scripten durchsuchen
# - diese Scripte nach festgelegter Reihenfolge ausführen
# - sich selbst aus dem Autostart entfernen
# ========================================

# ======= Konfigurationsvariablen =======
DEPENDENCIES="udevadm mount umount awk grep"

# ======= Logging konfigurieren =======
LOGFILE="/$(date +'%Y-%m-%d--%H-%M-%S')-$FILENAME.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_success() { log "SUCCESS: $*"; }
log_error()   { log "ERROR: $*"; }
log "==== USB-Init-Skript gestartet ===="

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

# ======= Prüfe, ob alle Programme installiert sind =======
log "Prüfe benötigte Programme..."
for bin in $DEPENDENCIES; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        error_exit "$bin ist nicht installiert oder nicht im Pfad!"
    fi
done
log_success "Alle benötigten Programme gefunden: $DEPENDENCIES"

# ======= Entferne Autostart-Eintrag via rc.local =======
if [[ -f /etc/rc.local ]]; then
    rm -f /etc/rc.local \
        && log_success "rc.local entfernt (Autostart abgeschaltet)." \
        || log_error "WARNUNG: Entfernen von rc.local fehlgeschlagen."
else
    log "rc.local nicht vorhanden, kein Autostart entfernt."
fi

# ======= USB-Initialisierung durchführen =======
log "Suche nach angeschlossenen USB-Blockgeräte-Partitionen ..."

USB_PARTITIONS=()
shopt -s nullglob
for part in /dev/sd*; do
    if [ -b "$part" ]; then
        # Partitionen und auch ganze Laufwerke (z.B. /dev/sda1, /dev/sdb, /dev/sdaa3)
        if [[ "$part" =~ ^/dev/sd[a-z]+[0-9]+$ ]] || [[ "$part" =~ ^/dev/sd[a-z]+$ ]]; then
            if udevadm info --query=property --name="$part" 2>/dev/null | grep -q '^ID_BUS=usb$'; then
                USB_PARTITIONS+=("$part")
            fi
        fi
    fi
done
shopt -u nullglob

if [ ${#USB_PARTITIONS[@]} -eq 0 ]; then
    log_success "Keine USB-Partitionen (Blockgeräte) gefunden."
    exit 0
fi

log "Gefundene USB-Partitionen:"
for part in "${USB_PARTITIONS[@]}"; do
    log "    $part"
done

TOTAL_FOUND_SCRIPTS=0

# ======= Verarbeitung jeder Partition =======
for partition in "${USB_PARTITIONS[@]}"; do
    partname=$(basename "$partition")
    MOUNT_POINT="/mnt/usb-init-$partname"

    # Prüfen, ob Partition bereits gemountet ist
    mountpoint=""
    mount_existing=""
    mountpoint_line=$(grep -m1 "^$partition " /proc/mounts || true)
    if [[ -n "$mountpoint_line" ]]; then
        mountpoint=$(echo "$mountpoint_line" | awk '{print $2}')
        log "$partition ist bereits gemountet auf $mountpoint"
        mount_existing="yes"
    else
        if [ -d "$MOUNT_POINT" ]; then
            # Mountpoint existiert, aber kein aktiver Mount drauf
            if mountpoint | grep -q " $MOUNT_POINT "; then
                log "Mountpoint $MOUNT_POINT ist bereits ein aktiver Mountpoint (seltene Race Condition)!"
                mount_existing="yes"   # Verhalte dich wie wenn gemountet
                mountpoint="$MOUNT_POINT"
            else
                log "Mountpoint $MOUNT_POINT existiert bereits und ist NICHT gemountet, wird verwendet."
            fi
        else
            mkdir -p "$MOUNT_POINT"
        fi
        if [[ -z "$mount_existing" ]]; then
            log "Mounte $partition auf $MOUNT_POINT ..."
            if mount "$partition" "$MOUNT_POINT"; then
                mountpoint="$MOUNT_POINT"
                log_success "Erfolgreich gemountet."
            else
                log_error "Fehler beim Mounten von $partition auf $MOUNT_POINT"
                continue
            fi
        fi
    fi

    # Suche nach Initialisierungsskripten auf diesem Medium (auch wenn bereits gemountet!)
    SCRIPTS=()
    if [ -n "$mountpoint" ]; then
        shopt -s nullglob
        for file in "$mountpoint"/USB-init-*.sh; do
            if [ -f "$file" ] && [ -x "$file" ]; then
                SCRIPTS+=("$file")
            fi
        done
        shopt -u nullglob
    fi

    if [ ${#SCRIPTS[@]} -eq 0 ]; then
        log "Keine Initialisierungsskripte für $partition auf $mountpoint gefunden."
    else
        log "Gefundene Initialisierungsskripte auf $partition:"
        for script in "${SCRIPTS[@]}"; do log "    $script"; done
        ((TOTAL_FOUND_SCRIPTS+=${#SCRIPTS[@]}))

        # Skripte nach Namen sortieren
        IFS=$'\n' sorted_scripts=($(printf "%s\n" "${SCRIPTS[@]}" | sort))
        unset IFS

        # Skripte ausführen: Bei Fehler wird für DIESE Partition abgebrochen, die nächste Partition trotzdem verarbeitet!
        for script in "${sorted_scripts[@]}"; do
            log "Starte Initialisierungsskript: $script"
            "$script"
            RETURN_CODE=$?
            log "Return-Code von $script: $RETURN_CODE"
            if [ $RETURN_CODE -ne 0 ]; then
                log_error "FEHLER beim Ausführen von $script (Return-Code $RETURN_CODE), fahre mit nächster Partition fort."
                break
            fi
        done
    fi

    # Partition aushängen, falls von uns gemountet (nur eigenes Verzeichnis entfernen!)
    if [[ -z "$mount_existing" && -n "$mountpoint" && "$mountpoint" == "$MOUNT_POINT" ]]; then
        log "Aushängen von $partition von $mountpoint ..."
        if umount "$mountpoint"; then
            log_success "Erfolgreich ausgehängt."
            if [ -d "$mountpoint" ] && [ -z "$(ls -A "$mountpoint")" ]; then
                rmdir "$mountpoint"
                log "Mountpoint $mountpoint wurde gelöscht."
            else
                log "Mountpoint $mountpoint wird nicht entfernt (entweder nicht leer oder existiert nicht)."
            fi
        else
            log_error "Fehler beim Aushängen von $mountpoint."
        fi
    else
        log "$partition war bereits gemountet oder kein passender Mountpoint, lasse Mountpoint unangetastet."
    fi
    log "----------------------------------"
done

if [ "$TOTAL_FOUND_SCRIPTS" -eq 0 ]; then
    log_success "Es wurden auf keinem USB-Gerät Initialisierungsskripte gefunden."
else
    log_success "Initialisierungsskripte wurden gefunden und verarbeitet."
fi

exit 0
