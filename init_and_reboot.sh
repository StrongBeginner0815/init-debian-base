#!/bin/bash

# ========================================
# Debian Initialisierungs-Script für Basiskonfiguration
# Installiert benötigte Pakete, legt Benutzer mit sicheren Passwörtern an,
# verhindert SSH-Root-Login, sendet Zugangsdaten an einen Server und startet neu.
# ========================================

set -o errexit
set -o nounset
set -o pipefail

# ======= Konfigurationsvariablen =======
# Legen Sie hier gewünschte Pakete fest (alle benötigten inkl. Abhängigkeiten)
PACKAGES="sudo curl wget git jq passwd util-linux"

# URL des Remote-Servers für Zugangsdatenübertragung
CRED_SERVER="http://example.com/credentials"

# Passwortlänge Vorgaben
USER_PW_MIN=100
USER_PW_MAX=200
ROOT_PW_MIN=100
ROOT_PW_MAX=200
USER_MINLEN=2
USER_MAXLEN=5

# ======= Logging konfigurieren =======
LOGFILE="/tmp/$(date +'%Y-%m-%d-%H-%M-%S')-init-debian-base.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_success() { log "SUCCESS: $*"; }
log_error()   { log "ERROR: $*"; }

# ======= Fehlerbehandlung =======
error_exit() {
    log_error "$*"
    log_error "System wird zur Sicherheit heruntergefahren."
    shutdown -h now
    exit 1
}

trap 'error_exit "Ein unerwarteter Fehler ist aufgetreten. (Befehl: $BASH_COMMAND)"' ERR

# ======= Root-Prüfung =======
if [[ $EUID -ne 0 ]]; then
    log_error "Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

log "==== Debian-Initialisierungsskript gestartet ===="

# ======= Autostart-Eintrag entfernen =======
if [ -f /etc/rc.local ]; then
    rm -f /etc/rc.local && log_success "rc.local entfernt (Autostart abgeschaltet)." || error_exit "Entfernen von rc.local fehlgeschlagen."
else
    log "rc.local nicht vorhanden, kein Autostart entfernt."
fi

# ======= Paketinstallation =======
log "Aktualisiere Paketliste (apt update)..."
apt-get update && log_success "Paketquellen erfolgreich aktualisiert." || error_exit "apt update fehlgeschlagen."
log "Installiere benötigte Pakete: $PACKAGES"
apt-get install -y $PACKAGES && log_success "Pakete erfolgreich installiert." || error_exit "Paketinstallation fehlgeschlagen."

# ======= Zufälligen Benutzername generieren =======
username=$(tr -dc 'a-z' < /dev/urandom | head -c$(shuf -i "$USER_MINLEN"-"$USER_MAXLEN" -n 1))
log "Neuer Benutzername: $username"

# ======= Sichere Passwörter generieren =======
user_pw_length=$(shuf -i "$USER_PW_MIN"-"$USER_PW_MAX" -n 1)
root_pw_length=$(shuf -i "$ROOT_PW_MIN"-"$ROOT_PW_MAX" -n 1)
user_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c"$user_pw_length")
root_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c"$root_pw_length")
log "Neues User-Passwort generiert (Länge: ${#user_password}), Passwort wird nicht geloggt."
log "Neues Root-Passwort generiert (Länge: ${#root_password}), Passwort wird nicht geloggt."

# ======= Benutzer anlegen und konfigurieren =======
if id "$username" &>/dev/null; then
    error_exit "Benutzer '$username' existiert bereits!"
fi

useradd -m -s /bin/bash "$username" && log_success "Benutzer $username erstellt." || error_exit "Fehler bei Benutzeranlage."
usermod -aG sudo "$username" && log_success "Benutzer $username zu 'sudo' hinzugefügt." || error_exit "usermod fehlgeschlagen."
echo "$username:$user_password" | chpasswd && log_success "Passwort für $username gesetzt." || error_exit "Passwort setzen fehlgeschlagen."

# ======= Root-Passwort setzen =======
echo "root:$root_password" | chpasswd && log_success "Neues root-Passwort gesetzt." || error_exit "Fehler beim Setzen des root-Passworts."

# ======= SSH Root-Login deaktivieren =======
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
    if grep -Eq "^\s*PermitRootLogin\s+" "$SSHD_CONFIG"; then
        sed -i "s/^\s*PermitRootLogin\s\+.*/PermitRootLogin no/" "$SSHD_CONFIG"
    else
        echo "PermitRootLogin no" >> "$SSHD_CONFIG"
    fi
    log_success "SSH-Root-Login deaktiviert."
    systemctl reload sshd || systemctl reload ssh || true
else
    log_error "sshd_config nicht gefunden! Kann SSH-Root-Login nicht einschränken."
fi

# ======= Zugangsdaten übertragen =======
TMPFILE_USER="/tmp/cred_user_response.txt"
TMPFILE_ROOT="/tmp/cred_root_response.txt"

user_json=$(jq -n --arg username "$username" --arg password "$user_password" '{"username": $username, "password": $password}')
root_json=$(jq -n --arg username "root" --arg password "$root_password" '{"username": $username, "password": $password}')

# -> Nutzer-Daten übertragen
runuser -l "$username" -c \
  "curl -sfSL -X POST -H 'Content-Type: application/json' -d '$user_json' '$CRED_SERVER'" \
  >"$TMPFILE_USER" 2>&1
curl_status=$?
if [ $curl_status -eq 0 ]; then
    log_success "Userdaten erfolgreich an $CRED_SERVER gesendet."
else
    log_error "Fehler beim Senden der Userdaten an $CRED_SERVER. Ausgabe folgt:"
    cat "$TMPFILE_USER"
    error_exit "Übertragung der Userdaten fehlgeschlagen."
fi
rm -f "$TMPFILE_USER"

# -> Root-Daten übertragen
curl -sfSL -X POST -H 'Content-Type: application/json' -d "$root_json" "$CRED_SERVER" >"$TMPFILE_ROOT" 2>&1
curl_status=$?
if [ $curl_status -eq 0 ]; then
    log_success "Root-Zugangsdaten erfolgreich an $CRED_SERVER übermittelt."
else
    log_error "Fehler bei der Übertragung der Root-Zugangsdaten an $CRED_SERVER. Ausgabe folgt:"
    cat "$TMPFILE_ROOT"
    error_exit "Übertragung der Root-Zugangsdaten fehlgeschlagen."
fi
rm -f "$TMPFILE_ROOT"

# ======= Root-User belassen, Passwort geändert =======
log_success "Root-User bleibt erhalten. Passwort geändert und SSH-Zugang gesperrt."

# ======= USB-init.sh für Autostart herunterladen und einrichten =======
USB_SCRIPT_URL="https://raw.githubusercontent.com/StrongBeginner0815/init-debian-base/refs/heads/main/USB-init.sh"
USB_SCRIPT_TARGET="/usr/local/sbin/USB-init.sh"
RC_LOCAL="/etc/rc.local"

log "Lade USB-init.sh von $USB_SCRIPT_URL herunter..."
if curl -sfSL "$USB_SCRIPT_URL" -o "$USB_SCRIPT_TARGET"; then
    chmod 700 "$USB_SCRIPT_TARGET"
    log_success "USB-init.sh erfolgreich heruntergeladen und ausführbar gemacht."
else
    log_error "Konnte USB-init.sh nicht herunterladen!"
    error_exit "Download von USB-init.sh fehlgeschlagen."
fi

log "Richte Autostart über rc.local für USB-init.sh ein..."
cat >"$RC_LOCAL" <<EOF
#!/bin/bash
if [ -f "/usr/local/sbin/USB-init.sh" ]; then
    exec /usr/local/sbin/USB-init.sh
else
    echo "ERROR: /usr/local/sbin/USB-init.sh nicht gefunden!" >&2
    exit 1
fi
EOF
chmod 755 "$RC_LOCAL" && log_success "rc.local für USB-init.sh gesetzt." || error_exit "Setzen von rc.local fehlgeschlagen."

# ======= System-Neustart durchführen =======
log "Führe Systemneustart durch..."
shutdown -r now
