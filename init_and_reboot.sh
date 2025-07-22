#!/bin/bash

# ========================================
# Projekt: Init-Debian-Base
# Author: https://github.com/StrongBeginner0815
FILENAME="init_and_reboot.sh"
# Zuständig für die Basiskonfiguration:
# - Entfernt eigenen Autostart-Eintrag
# - Installiert benötigte Pakete
# - Legt Benutzer mit sicherem Passwort an
# - Verhindert SSH-Root-Login
# - Sendet Zugangsdaten an einen Cred-Server im lokalen Netz
# - Lädt USB-init-Script herunter und vermerkt es für den Autostart
# - Startet neu
# ========================================

# ======= Konfigurationsvariablen =======
# Zu installierende Pakete
dependencies="sudo curl wget git jq passwd util-linux"
PACKAGES="nano $dependencies"

# URLs
CRED_SERVER="http://credentials.local:5000"
USB_SCRIPT_URL="https://raw.githubusercontent.com/StrongBeginner0815/init-debian-base/refs/heads/main/USB-init.sh"

# Passwortlänge (Vorgaben für Zufallsgenerierung)
USER_PW_MIN=100
USER_PW_MAX=200
ROOT_PW_MIN=100
ROOT_PW_MAX=200
USER_MINLEN=2
USER_MAXLEN=5

# ======= Logging konfigurieren =======
LOGFILE="/$(date +'%Y-%m-%d--%H-%M-%S')-$FILENAME.log"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_success() { log "SUCCESS: $*"; }
log_error()   { log "ERROR: $*"; }
log "==== Debian-Initialisierungsskript gestartet ===="

# ======= Fehlerbehandlung =======
error_exit() {
    log_error "$*"
    log_error "System wird zur Sicherheit heruntergefahren."
    shutdown -h now
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

# ======= Zeitzone auf Europa/Berlin setzen =======
log "Setze Zeitzone auf Europe/Berlin..."
timedatectl set-timezone Europe/Berlin && log_success "Zeitzone auf Europe/Berlin gesetzt." || error_exit "Setzen der Zeitzone fehlgeschlagen."

# ======= Zufälligen Benutzernamen generieren =======
username=$(tr -dc 'a-z' < /dev/urandom | head -c$(shuf -i "$USER_MINLEN"-"$USER_MAXLEN" -n 1))
log "Neuer Benutzername: $username"

# ======= Sichere Passwörter generieren =======
user_pw_length=$(shuf -i "$USER_PW_MIN"-"$USER_PW_MAX" -n 1)
root_pw_length=$(shuf -i "$ROOT_PW_MIN"-"$ROOT_PW_MAX" -n 1)
user_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c"$user_pw_length")
root_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c"$root_pw_length")
log "Neues User-Passwort generiert (Länge: ${#user_password}), Passwort wird nicht geloggt."
log "Neues Root-Passwort generiert (Länge: ${#root_password}), Passwort wird nicht geloggt."

# ======= Zugangsdaten übertragen =======
user_json=$(jq -n --arg username "$username" --arg password "$user_password" '{"username": $username, "password": $password}')
root_json=$(jq -n --arg username "root" --arg password "$root_password" '{"username": $username, "password": $password}')

# User-Anmeldedaten übertragen
usr_curl_response=$(curl -sfSL -X POST -H 'Content-Type: application/json' -d "$user_json" "$CRED_SERVER")
usr_curl_ecode=$?
if [ $usr_curl_ecode -eq 0 ]; then
    log_success "User-Anmeldedaten erfolgreich an $CRED_SERVER gesendet."
else
    log_error "Fehler beim Senden der User-Anmeldedaten an $CRED_SERVER. Ausgabe folgt: $usr_curl_response"
    error_exit "Übertragung der User-Anmeldedaten fehlgeschlagen."
fi

# Root-Anmeldedaten übertragen
root_curl_response=$(curl -sfSL -X POST -H 'Content-Type: application/json' -d "$root_json" "$CRED_SERVER")
root_curl_ecode=$?
if [ $root_curl_ecode -eq 0 ]; then
    log_success "Root-Anmeldedaten erfolgreich an $CRED_SERVER gesendet."
else
    log_error "Fehler beim Senden der Root-Anmeldedaten an $CRED_SERVER. Ausgabe folgt: $root_curl_response"
    error_exit "Übertragung der Root-Anmeldedaten fehlgeschlagen."
fi

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

# ======= USB-init.sh für Autostart herunterladen und einrichten =======
log "Lade USB-init.sh von $USB_SCRIPT_URL herunter..."
if curl -sfSL "$USB_SCRIPT_URL" -o "/usr/local/sbin/USB-init.sh"; then
    chmod 700 "/usr/local/sbin/USB-init.sh"
    log_success "USB-init.sh erfolgreich heruntergeladen und ausführbar gemacht."
else
    log_error "Konnte USB-init.sh nicht herunterladen!"
    error_exit "Download von USB-init.sh fehlgeschlagen."
fi

log "Richte Autostart über rc.local für USB-init.sh ein..."
cat > "/etc/rc.local" <<EOF
#!/bin/bash
if [ -f "/usr/local/sbin/USB-init.sh" ]; then
    exec /usr/local/sbin/USB-init.sh
else
    echo "ERROR: /usr/local/sbin/USB-init.sh nicht gefunden!" >&2
    exit 1
fi
EOF
chmod 755 "/etc/rc.local" && log_success "rc.local für USB-init.sh gesetzt." || error_exit "Setzen von rc.local fehlgeschlagen."

# ======= System-Neustart durchführen =======
log "Führe Systemneustart durch..."
shutdown -r now
