#!/bin/bash

# ==== Script aus dem Autostart entfernen ====
if [ -f /etc/rc.local ]; then
  rm -f /etc/rc.local && echo "rc.local entfernt (Autostart abgeschaltet)." || echo "WARNUNG: Entfernen von rc.local fehlgeschlagen."
else
  echo "rc.local nicht vorhanden, kein Autostart entfernt."
fi

usb_init() {
  # Logdatei direkt im Rootverzeichnis
  LOG_FILE="/usb-init-$(date '+%Y-%m-%d-%H-%M-%S').log"

  # Hilfsfunktion zum Loggen
  log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
  }

  # Root-Rechte prüfen
  if [ "$(id -u)" -ne 0 ]; then
    log "Die Funktion muss als root ausgeführt werden!"
    return 1
  fi

  # USB-Geräte ermitteln (nur solche mit ID_BUS=usb, d.h. echte USB-Massenspeicher)
  USB_DEVICES=()
  for dev in /dev/sd[a-z]; do
    if [ -b "$dev" ]; then
      if udevadm info --query=property --name="$dev" | grep -q '^ID_BUS=usb$'; then
        USB_DEVICES+=("$dev")
      fi
    fi
  done

  if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    log "Keine USB-Geräte gefunden."
    return 1
  fi

  log "Gefundene USB-Blockgeräte:"
  for dev in "${USB_DEVICES[@]}"; do
    log "    $dev"
  done

  # Zähler für Skripte (um später Erfolg/Nicht-Erfolg zurückzumelden)
  TOTAL_FOUND_SCRIPTS=0

  # Verarbeite jedes USB-Gerät einzeln
  for device in "${USB_DEVICES[@]}"; do
    devname=$(basename "$device")
    MOUNT_POINT="/mnt/usb-$devname"

    # Prüfen, ob Gerät bereits gemountet ist
    mountpoint=""
    if grep -q "^$device" /proc/mounts; then
      mountpoint=$(grep "^$device" /proc/mounts | awk '{print $2}')
      log "$device ist bereits gemountet auf $mountpoint"
    else
      mkdir -p "$MOUNT_POINT"
      log "Mounte $device auf $MOUNT_POINT ..."
      if mount "$device" "$MOUNT_POINT" >>"$LOG_FILE" 2>&1; then
        mountpoint="$MOUNT_POINT"
        log "Erfolgreich gemountet."
      else
        log "Fehler beim Mounten von $device auf $MOUNT_POINT"
        continue
      fi
    fi

    # Suche nach Initialisierungsskripten auf diesem Medium
    SCRIPTS=()
    for file in "$mountpoint"/USB-init-*.sh; do
      if [ -f "$file" ] && [ -x "$file" ]; then
        SCRIPTS+=("$file")
      fi
    done

    if [ ${#SCRIPTS[@]} -eq 0 ]; then
      log "Keine Initialisierungsskripte für $device auf $mountpoint gefunden."
    else
      log "Gefundene Initialisierungsskripte auf $device:"
      for script in "${SCRIPTS[@]}"; do log "    $script"; done
      ((TOTAL_FOUND_SCRIPTS+=${#SCRIPTS[@]}))

      # Skripte nach Namen sortieren
      IFS=$'\n' sorted_scripts=($(printf "%s\n" "${SCRIPTS[@]}" | sort))
      unset IFS

      # Skripte ausführen
      for script in "${sorted_scripts[@]}"; do
        log "Starte Initialisierungsskript: $script"
        "$script" >>"$LOG_FILE" 2>&1
        RETURN_CODE=$?
        log "Return-Code von $script: $RETURN_CODE"
        if [ $RETURN_CODE -ne 0 ]; then
          log "FEHLER beim Ausführen von $script (Return-Code $RETURN_CODE), breche Skriptausführung für $device ab."
          break
        fi
      done
    fi

    # Gerät aushängen, falls zuvor gemountet
    if [ "$mountpoint" = "$MOUNT_POINT" ]; then
      log "Aushängen von $device von $mountpoint ..."
      if umount "$mountpoint" >>"$LOG_FILE" 2>&1; then
        log "Erfolgreich ausgehängt."
        rmdir "$mountpoint" 2>/dev/null
      else
        log "Fehler beim Aushängen von $mountpoint."
      fi
    else
      log "$device war bereits gemountet, lasse Mountpoint unangetastet."
    fi
    log "----------------------------------"
  done

  if [ "$TOTAL_FOUND_SCRIPTS" -eq 0 ]; then
    log "Es wurden auf keinem USB-Gerät Initialisierungsskripte gefunden. Beende erfolgreich mit Code 0."
    return 0
  else
    log "Initialisierungsskripte wurden gefunden und verarbeitet. Beende erfolgreich mit Code 0."
    return 0
  fi
}

# Hauptaufruf
if usb_init; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - USB-Initialisierung erfolgreich."
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Fehler bei der USB-Initialisierung. Siehe Log für Details (/usb-init-...)"
  exit 1
fi
