

#!/usr/bin/env bash
set -euo pipefail


DATE="$(date +%Y-%m-%d_%H-%M-%S)"
OUTDIR="./audit_${DATE}"
REPORT="${OUTDIR}/rapport_audit_${DATE}.txt"

mkdir -p "$OUTDIR"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'



ok()   { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$REPORT"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$REPORT"; }
fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$REPORT"; }
section() { echo -e "\n===== $1 =====" | tee -a "$REPORT"; }



check_ssh() {
  section "SSH"

  if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    ok "Service SSH actif"

    if ss -tlnp | grep -q ':22\b'; then
      ok "Port 22 à l'écoute"
    else
      warn "Port 22 non détecté"
    fi
  else
    fail "Service SSH inactif"
  fi
}



check_ufw() {
  section "UFW"

  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qi "Status: active"; then
      ok "UFW actif"
      ufw status verbose | tee -a "$REPORT" >/dev/null
    else
      warn "UFW installé mais inactif"
    fi
  else
    warn "UFW non installé"
  fi
}



check_passwd_permissions() {
  section "/etc/passwd"

  perms="$(stat -c %a /etc/passwd 2>/dev/null || echo unknown)"
  owner="$(stat -c %U /etc/passwd 2>/dev/null || echo unknown)"
  group="$(stat -c %G /etc/passwd 2>/dev/null || echo unknown)"

  echo "Owner: $owner / Group: $group / Perms: $perms" | tee -a "$REPORT"

  if [[ "$perms" == "644" ]]; then
    ok "/etc/passwd correctement protégé"
  else
    warn "Permissions /etc/passwd à vérifier"
  fi
}


check_listening_services() {
  section "Services en écoute"

  ss -tulpn | tee -a "$REPORT" >/dev/null

  if ss -tulpn | grep -q LISTEN; then
    ok "Services en écoute détectés"
  else
    warn "Aucun service en écoute trouvé"
  fi
}



check_updates() {
  section "Mises à jour système"

  if command -v apt >/dev/null 2>&1; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)

    if [ "$UPDATES" -eq 0 ]; then
      ok "Système à jour"
    else
      warn "$UPDATES mises à jour disponibles"
    fi
  else
    warn "APT non disponible"
  fi
}



check_shadow_empty_passwords() {
  section "/etc/shadow"

  EMPTY=$(awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null || true)

  if [ -z "$EMPTY" ]; then
    ok "Aucun compte sans mot de passe"
  else
    warn "Comptes sans mot de passe : $EMPTY"
  fi
}



check_ssh_permissions() {
  section "~/.ssh"

  for dir in /home/*/.ssh; do
    if [ -d "$dir" ]; then
      perms=$(stat -c %a "$dir")
      owner=$(stat -c %U "$dir")

      echo "$dir -> owner=$owner perms=$perms" | tee -a "$REPORT"

      if [ "$perms" -le 700 ]; then
        ok "$dir sécurisé"
      else
        warn "$dir permissions trop ouvertes"
      fi
    fi
  done
}

main() {
  echo "Rapport d'audit Linux - $(date -Is)" | tee "$REPORT"
  echo "Hôte: $(hostname)" | tee -a "$REPORT"

  check_ssh
  check_ufw
  check_passwd_permissions
  check_listening_services
  check_updates
  check_shadow_empty_passwords
  check_ssh_permissions

  echo -e "\nRapport généré : $REPORT" | tee -a "$REPORT"
}

main "$@"