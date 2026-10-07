#!/usr/bin/env bash
# Maquette KVM/libvirt du TP « Automatiser l'arrivée d'utilisateurs avec PowerShell ».
# Construit DC01 et SRV01 (Windows Server Core) et ADMIN (Windows 11 Pro) sur un LAN
# isolé 10.77.10.0/24, crée le domaine learn-it.local et prend l'instantané « etat-initial ».
# Les VM sont pilotées par l'agent invité QEMU : l'hôte n'a aucune adresse sur le LAN du TP.
# Aide : kvm/lab.sh aide
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true # « & » littéral dans ${var//motif/remplacement}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///system}"

# Une valeur de LAB par copie isolée de la maquette : VM tp-dc01, tp-srv01, tp-admin, réseau tp-lan.
LAB="${LAB:-tp}"
NET="$LAB-lan"
POOL="${POOL:-default}"
DL="${DL:-$HOME/Téléchargements}"
SERVER_ISO="${SERVER_ISO:-$DL/SERVER_EVAL_x64FRE_en-us.iso}"
SERVER_INDEX="${SERVER_INDEX:-1}"       # lab.sh images : 1 = Standard Core sur les ISO d'évaluation
SERVER_OSINFO="${SERVER_OSINFO:-win2k22}" # win2k25 pour Windows Server 2025
SERVER_UI="${SERVER_UI:-en-US}"         # langue de l'ISO serveur
WIN11_ISO="${WIN11_ISO:-$DL/Win11_25H2_French_x64_v2.iso}"
WIN11_INDEX="${WIN11_INDEX:-6}"         # lab.sh images : 6 = Windows 11 Pro sur l'ISO grand public
WIN11_UI="${WIN11_UI:-fr-FR}"
VIRTIO_ISO="${VIRTIO_ISO:-$DL/virtio-win/virtio-win.iso}"
WORK="${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/tp-learnit}" # fichiers générés, hors dépôt
SNAPSHOT="${SNAPSHOT:-etat-initial}"
VMS=(dc01 srv01 admin)
PS_EXE='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

die() { echo "ERREUR : $*" >&2; exit 1; }
# Les états lus par le script (running, shut off...) ne doivent pas dépendre de la langue de l'hôte.
virsh() { LC_ALL=C command virsh "$@"; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# Rôle -> nom Windows, adresse, mémoire (Mio), disque (Go), système.
spec() {
    case "$1" in
        dc01)  echo "DC01 10.77.10.10 ${DC_RAM:-2048} 60 server" ;;
        srv01) echo "SRV01 10.77.10.20 ${SRV_RAM:-2048} 60 server" ;;
        admin) echo "ADMIN 10.77.10.30 ${ADMIN_RAM:-4096} 64 win11" ;;
        *) die "VM inconnue : $1 (dc01, srv01 ou admin)" ;;
    esac
}
dom() { spec "$1" >/dev/null; echo "$LAB-$1"; }

# Le secret d'administration de la maquette n'est jamais écrit dans le dépôt.
password() {
    if [[ -z "${LAB_PASSWORD:-}" ]]; then
        [[ -t 0 ]] || die "définir LAB_PASSWORD (secret Administrator du domaine et des VM)"
        read -rsp 'Secret Administrator de la maquette : ' LAB_PASSWORD; echo
    fi
    [[ ${#LAB_PASSWORD} -ge 8 ]] || die "LAB_PASSWORD doit respecter la complexité Windows (8 caractères et plus)"
    export LAB_PASSWORD
}

# ---------------------------------------------------------------- agent invité QEMU
ga() { virsh qemu-agent-command "$1" "$2" --timeout "${3:-30}"; }

agent_ok() { ga "$1" '{"execute":"guest-ping"}' 5 >/dev/null 2>&1; }

# Exécuter un programme dans l'invité (en SYSTEM), attendre sa fin, rendre sa sortie et son code.
ga_exec() {
    local vm=$1 path=$2 req pid st code
    shift 2
    req=$(jq -nc --arg p "$path" '{execute:"guest-exec",arguments:{path:$p,arg:$ARGS.positional,"capture-output":true}}' --args -- "$@")
    pid=$(ga "$(dom "$vm")" "$req" | jq -r '.return.pid')
    while :; do
        st=$(ga "$(dom "$vm")" "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}")
        [[ $(jq -r '.return.exited' <<<"$st") == true ]] && break
        sleep 2
    done
    # La console Windows écrit dans la page de codes OEM (850 avec les paramètres régionaux fr-FR).
    jq -r '.return["out-data"] // empty' <<<"$st" | base64 -d | iconv -f CP850 -t UTF-8 | tr -d '\r'
    jq -r '.return["err-data"] // empty' <<<"$st" | base64 -d | iconv -f CP850 -t UTF-8 | tr -d '\r' >&2
    code=$(jq -r '.return.exitcode // 1' <<<"$st")
    return "$code"
}

# Copier un petit fichier local dans l'invité (scripts uniquement : un seul message JSON).
ga_put() {
    local vm=$1 dest=$2 src=$3 h
    h=$(ga "$(dom "$vm")" "$(jq -nc --arg p "$dest" '{execute:"guest-file-open",arguments:{path:$p,mode:"wb"}}')" | jq -r .return)
    ga "$(dom "$vm")" "$(jq -nc --argjson h "$h" --arg b "$(base64 -w0 "$src")" \
        '{execute:"guest-file-write",arguments:{handle:$h,"buf-b64":$b}}')" >/dev/null
    ga "$(dom "$vm")" "{\"execute\":\"guest-file-close\",\"arguments\":{\"handle\":$h}}" >/dev/null
}

# Exécuter un script PowerShell du dépôt dans l'invité : lab.sh ps VM fichier.ps1 [-Param valeur...]
ga_ps() {
    local vm=$1 file=$2 dest
    shift 2
    dest="C:\\Windows\\Temp\\lab-$(basename "$file")"
    ga_put "$vm" "$dest" "$file"
    ga_exec "$vm" "$PS_EXE" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$dest" "$@"
}

# Exécuter une commande PowerShell courte : lab.sh cmd VM 'Get-Service WinRM'
# Passer par un fichier -File plutôt que -EncodedCommand : les erreurs restent du texte lisible.
# ErrorActionPreference Stop : toute erreur rend un code de sortie non nul à l'hôte.
ga_cmd() {
    local vm=$1 file
    shift
    mkdir -p "$WORK"
    file=$(mktemp "$WORK/cmd-XXXXXX.ps1")
    {
        printf '\xef\xbb\xbf'
        printf '%s\n' "\$ProgressPreference = 'SilentlyContinue'" "\$ErrorActionPreference = 'Stop'" 'try {' "$*" \
            '} finally {Remove-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue}'
    } >"$file"
    ga_ps "$vm" "$file" && rm -f "$file" || { local code=$?; rm -f "$file"; return $code; }
}

wait_agent() {
    local vm=$1 limit=${2:-3600} t=0
    info "Attente de l'agent invité de $(dom "$vm")"
    until agent_ok "$(dom "$vm")"; do
        ((t += 10)); ((t <= limit)) || die "agent de $(dom "$vm") muet après ${limit}s : ouvrir la console"
        sleep 10
    done
}

# Redémarrer par l'agent et attendre son retour (il disparaît d'abord pendant l'arrêt).
reboot_vm() {
    local vm=$1 t=0
    info "Redémarrage de $(dom "$vm")"
    virsh reboot "$(dom "$vm")" --mode agent >/dev/null
    while agent_ok "$(dom "$vm")"; do
        ((t += 3)); ((t <= 300)) || die "$(dom "$vm") ne s'arrête pas"
        sleep 3
    done
    wait_agent "$vm" 900
}

# --live seulement si la VM tourne : sinon virsh refuse et le média resterait en place.
live_flag() { virsh domstate "$(dom "$1")" | grep -q running && echo --live || true; }

# Vider tous les lecteurs DVD d'une VM (ISO Windows, ISO de réponse, ISO du dépôt).
eject_all() {
    local vm=$1 target live
    live=$(live_flag "$vm")
    while read -r target; do
        virsh change-media "$(dom "$vm")" "$target" --eject $live --config --force >/dev/null
    done < <(virsh domblklist "$(dom "$vm")" --details | awk '$2 == "cdrom" && $4 != "-" {print $3}')
}

wait_ad() {
    info "Attente du domaine sur DC01 (AD DS, SYSVOL, services Web AD)"
    ga_ps dc01 "$HERE/invite/Wait-LabDomain.ps1"
}

# ---------------------------------------------------------------- commandes
cmd_verifier() {
    local ok=1
    check() { if eval "$2" >/dev/null 2>&1; then echo "  OK   $1"; else echo "  NON  $1"; ok=0; fi; }
    info "Vérification de l'hôte"
    check "/dev/kvm accessible" '[[ -r /dev/kvm && -w /dev/kvm ]]'
    check "connexion $LIBVIRT_DEFAULT_URI" 'virsh uri'
    for c in virt-install virsh qemu-img swtpm xorriso jq iconv; do check "commande $c" "command -v $c"; done
    check "firmware UEFI Secure Boot (OVMF)" "grep -qsl secure-boot /usr/share/qemu/firmware/*.json"
    check "pool $POOL" "virsh pool-info $POOL"
    check "ISO serveur $SERVER_ISO" "[[ -s '$SERVER_ISO' ]]"
    check "ISO Windows 11 $WIN11_ISO" "[[ -s '$WIN11_ISO' ]]"
    check "ISO virtio-win $VIRTIO_ISO" "[[ -s '$VIRTIO_ISO' ]]"
    free -g | awk '/^Mem/ {printf "  INFO mémoire disponible : %s Gio (besoin : environ 8 Gio)\n", $7}'
    ((ok)) || die "prérequis manquants"
}

# Lister les éditions d'un ISO Windows (index à reporter dans SERVER_INDEX ou WIN11_INDEX).
# L'en-tête du fichier WIM indique où se trouve sa description XML : rien n'est extrait.
cmd_images() {
    local iso
    for iso in "${@:-$SERVER_ISO}"; do
        echo "$iso"
        python3 -I - "$iso" <<'PY'
import re, struct, sys
with open(sys.argv[1], 'rb') as f:
    pos = 0
    while chunk := f.read(64 << 20):
        i = chunk.find(b'MSWIM\0\0\0')
        while i != -1:
            if (pos + i) % 2048 == 0:
                back = f.tell(); f.seek(pos + i); head = f.read(208)
                size = int.from_bytes(head[72:79], 'little'); offset = struct.unpack_from('<Q', head, 80)[0]
                f.seek(pos + i + offset); xml = f.read(size).decode('utf-16-le', 'replace'); f.seek(back)
                for index, body in re.findall(r'<IMAGE INDEX="(\d+)"[^>]*>(.*?)</IMAGE>', xml, re.S):
                    tag = lambda t: (re.search(f'<{t}>(.*?)</{t}>', body, re.S) or [None, ''])[1]
                    if tag('INSTALLATIONTYPE') != 'WindowsPE':
                        print(f"  {index:>2}  {tag('NAME')}  [{tag('INSTALLATIONTYPE')}, build {tag('BUILD')}, {tag('LANGUAGE') or tag('DEFAULT')}]")
            i = chunk.find(b'MSWIM\0\0\0', i + 1)
        pos += len(chunk)
PY
    done
}

cmd_reseau() {
    if virsh net-info "$NET" >/dev/null 2>&1; then
        info "Réseau $NET déjà présent"
    else
        info "Création du réseau isolé $NET (aucune IP hôte, ni DHCP, ni NAT)"
        local xml="$WORK/$NET.xml"
        mkdir -p "$WORK"
        printf "<network>\n  <name>%s</name>\n  <bridge stp='on' delay='0'/>\n</network>\n" "$NET" >"$xml"
        virsh net-define "$xml" >/dev/null
        virsh net-autostart "$NET" >/dev/null
    fi
    virsh net-list --name | grep -qx "$NET" || virsh net-start "$NET" >/dev/null
}

# Générer l'ISO de réponse d'une VM, puis le déposer dans le pool libvirt (lisible par qemu).
build_unattend() {
    local vm=$1 host ip ram disk os template index ui dir xml pw iso vol
    read -r host ip ram disk os <<<"$(spec "$vm")"
    if [[ $os == server ]]; then template=server-core.xml index=$SERVER_INDEX ui=$SERVER_UI
    else template=windows11.xml index=$WIN11_INDEX ui=$WIN11_UI; fi
    dir="$WORK/$LAB-$vm-unattend"
    rm -rf "$dir"
    mkdir -p "$dir/lab"
    pw=$LAB_PASSWORD
    pw=${pw//&/&amp;}; pw=${pw//</&lt;}; pw=${pw//>/&gt;}
    xml=$(<"$HERE/unattend/$template")
    xml=${xml//@@COMPUTERNAME@@/$host}
    xml=${xml//@@IMAGEINDEX@@/$index}
    xml=${xml//@@UILANGUAGE@@/$ui}
    xml=${xml//@@PASSWORD@@/$pw}
    printf '%s\n' "$xml" >"$dir/autounattend.xml"
    cp "$HERE/invite/FirstLogon.ps1" "$dir/lab/"
    xorriso -osirrox on -indev "$VIRTIO_ISO" \
        -extract /virtio-win-gt-x64.msi "$dir/lab/virtio-win-gt-x64.msi" \
        -extract /guest-agent/qemu-ga-x86_64.msi "$dir/lab/qemu-ga-x86_64.msi" 2>/dev/null
    iso="$WORK/$LAB-$vm-unattend.iso"
    xorriso -as mkisofs -quiet -J -joliet-long -R -V UNATTEND -o "$iso" "$dir" 2>/dev/null
    rm -rf "$dir" # le secret ne reste que dans l'ISO du pool, supprimé par « finaliser »
    vol="$LAB-$vm-unattend.iso"
    virsh vol-delete --pool "$POOL" "$vol" >/dev/null 2>&1 || true
    virsh vol-create-as "$POOL" "$vol" "$(stat -c %s "$iso")" --format raw >/dev/null
    virsh vol-upload --pool "$POOL" "$vol" "$iso" >/dev/null
    rm -f "$iso"
}

cmd_installer() {
    local vm=$1 host ip ram disk os osinfo media extra=()
    read -r host ip ram disk os <<<"$(spec "$vm")"
    virsh dominfo "$(dom "$vm")" >/dev/null 2>&1 && die "$(dom "$vm") existe déjà (lab.sh supprimer pour repartir de zéro)"
    password
    cmd_reseau
    if [[ $os == server ]]; then osinfo=$SERVER_OSINFO media=$SERVER_ISO
    else osinfo=win11 media=$WIN11_ISO
        # Windows 11 exige un TPM 2.0 : swtpm l'émule, avec un état propre à la VM.
        extra=(--tpm backend.type=emulator,backend.version=2.0,model=tpm-crb)
    fi
    [[ -s $media ]] || die "ISO absent : $media"
    info "Préparation de l'ISO de réponse de $(dom "$vm")"
    build_unattend "$vm"
    info "Création de $(dom "$vm") : $host, $ip, ${ram} Mio, ${disk} Go"
    virt-install --connect "$LIBVIRT_DEFAULT_URI" --name "$(dom "$vm")" --osinfo "$osinfo" \
        --memory "$ram" --vcpus 2 --cpu host-passthrough --machine q35 \
        --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes \
        "${extra[@]}" \
        --disk "pool=$POOL,size=$disk,format=qcow2,bus=sata,discard=unmap,boot.order=1" \
        --disk "path=$media,device=cdrom,bus=sata,readonly=on,boot.order=2" \
        --disk "vol=$POOL/$LAB-$vm-unattend.iso,device=cdrom,bus=sata,readonly=on" \
        --network "network=$NET,model=virtio" \
        --channel unix,target.type=virtio,name=org.qemu.guest_agent.0 \
        --graphics spice --sound none \
        --metadata "description=Maquette TP learn-it.local : $host $ip" \
        --import --noautoconsole >/dev/null
    # Le DVD Windows demande « appuyez sur une touche » au démarrage UEFI : on appuie pour lui.
    for _ in $(seq 1 30); do
        virsh send-key "$(dom "$vm")" KEY_SPACE >/dev/null 2>&1 || true
        sleep 1
    done
    info "Installation de $(dom "$vm") lancée (console : virt-manager)"
}

cmd_configurer() {
    password
    info "Attente des agents invités (après « installer » : 15 à 40 min selon l'hôte)"
    for vm in "${VMS[@]}"; do wait_agent "$vm"; done
    local host ip ram disk os
    for vm in "${VMS[@]}"; do
        read -r host ip ram disk os <<<"$(spec "$vm")"
        info "Adresse fixe de $host : $ip"
        ga_ps "$vm" "$HERE/invite/Set-LabNetwork.ps1" -IPAddress "$ip" -DnsServer 10.77.10.10
    done
    info "Création de la forêt learn-it.local sur DC01 (5 à 10 min)"
    ga_ps dc01 "$HERE/invite/Install-LabForest.ps1" -SafeModePassword "$LAB_PASSWORD"
    reboot_vm dc01
    wait_ad
    for vm in srv01 admin; do
        info "Jonction de $(dom "$vm") au domaine"
        ga_ps "$vm" "$HERE/invite/Join-LabDomain.ps1" -DomainPassword "$LAB_PASSWORD"
        reboot_vm "$vm"
    done
    cmd_controler
}

# Prérequis du TP : domaine, DNS, canal sécurisé des membres et WinRM des deux serveurs.
cmd_controler() {
    info "Contrôle des prérequis du TP"
    ga_cmd dc01 'Get-ADDomain | Select-Object DNSRoot,NetBIOSName,DomainMode | Format-List'
    for vm in srv01 admin; do
        ga_cmd "$vm" '"{0} membre de {1} : canal sécurisé {2}" -f $env:COMPUTERNAME,(Get-CimInstance Win32_ComputerSystem).Domain,(Test-ComputerSecureChannel)'
    done
    ga_cmd admin 'foreach ($n in "dc01","srv01") { $t = Test-NetConnection "$n.learn-it.local" -Port 5985 -WarningAction SilentlyContinue; "{0} -> {1} WinRM {2}" -f $t.ComputerName,$t.RemoteAddress,$t.TcpTestSucceeded }'
}

# Retirer les ISO d'installation (le secret y figure) et insérer le dépôt dans ADMIN.
cmd_finaliser() {
    local vm
    for vm in "${VMS[@]}"; do
        eject_all "$vm"
        virsh vol-delete --pool "$POOL" "$LAB-$vm-unattend.iso" >/dev/null 2>&1 || true
    done
    cmd_depot
}

# ISO du dépôt (fichiers suivis par Git, modifications locales comprises) dans le lecteur d'ADMIN.
cmd_depot() {
    local dir="$WORK/depot" iso="$WORK/$LAB-depot.iso" vol="$LAB-depot.iso" target live
    info "ISO du dépôt pour ADMIN"
    rm -rf "$dir"; mkdir -p "$dir"
    (cd "$REPO" && git ls-files -z | xargs -0 cp --parents -t "$dir")
    xorriso -as mkisofs -quiet -J -joliet-long -R -V TP-POWERSHELL -o "$iso" "$dir" 2>/dev/null
    rm -rf "$dir"
    # Éjecter avant de remplacer le fichier : QEMU garderait l'ancien ouvert, et Windows
    # ne relit le volume qu'après une éjection.
    target=$(virsh domblklist "$(dom admin)" --details | awk '$2 == "cdrom" {print $3; exit}')
    live=$(live_flag admin)
    virsh change-media "$(dom admin)" "$target" --eject $live --config --force >/dev/null 2>&1 || true
    virsh vol-delete --pool "$POOL" "$vol" >/dev/null 2>&1 || true
    virsh vol-create-as "$POOL" "$vol" "$(stat -c %s "$iso")" --format raw >/dev/null
    virsh vol-upload --pool "$POOL" "$vol" "$iso" >/dev/null
    rm -f "$iso"
    virsh change-media "$(dom admin)" "$target" "$(virsh vol-path --pool "$POOL" "$vol")" \
        --insert $live --config >/dev/null
}

cmd_demarrer() {
    info "Démarrage de DC01 d'abord : il fournit le DNS et l'authentification"
    virsh domstate "$(dom dc01)" | grep -q running || virsh start "$(dom dc01)" >/dev/null
    wait_agent dc01 600
    wait_ad
    for vm in srv01 admin; do
        virsh domstate "$(dom "$vm")" | grep -q running || virsh start "$(dom "$vm")" >/dev/null
    done
    for vm in srv01 admin; do wait_agent "$vm" 600; done
    cmd_etat
}

cmd_arreter() {
    local vm t
    for vm in admin srv01 dc01; do
        virsh domstate "$(dom "$vm")" | grep -q 'shut off' && continue
        info "Arrêt propre de $(dom "$vm")"
        virsh shutdown "$(dom "$vm")" --mode agent >/dev/null 2>&1 || virsh shutdown "$(dom "$vm")" >/dev/null
        t=0
        until virsh domstate "$(dom "$vm")" | grep -q 'shut off'; do
            ((t += 5)); ((t <= 300)) || die "$(dom "$vm") ne s'arrête pas"
            sleep 5
        done
    done
}

# Instantané cohérent des trois VM, prises ensemble et éteintes (comme demandé à l'étape 01).
cmd_instantane() {
    local name=${1:-$SNAPSHOT} vm
    cmd_arreter
    for vm in "${VMS[@]}"; do
        info "Instantané $name de $(dom "$vm")"
        virsh snapshot-create-as "$(dom "$vm")" "$name" --description "Maquette TP : $name" >/dev/null
    done
}

cmd_restaurer() {
    local name=${1:-$SNAPSHOT} vm
    for vm in "${VMS[@]}"; do
        info "Retour de $(dom "$vm") à $name"
        virsh destroy "$(dom "$vm")" >/dev/null 2>&1 || true
        virsh snapshot-revert "$(dom "$vm")" "$name" --force
    done
    cmd_demarrer
}

cmd_etat() {
    local vm state agent ips
    printf '%-12s %-10s %-7s %s\n' VM ETAT AGENT IPv4
    for vm in "${VMS[@]}"; do
        state=$(virsh domstate "$(dom "$vm")" 2>/dev/null | head -1 || echo absente)
        agent=non ips=''
        if agent_ok "$(dom "$vm")"; then
            agent=oui
            ips=$(ga "$(dom "$vm")" '{"execute":"guest-network-get-interfaces"}' |
                jq -r '[.return[]["ip-addresses"][]? | select(.["ip-address-type"]=="ipv4" and (.["ip-address"]|startswith("127.")|not)) | .["ip-address"]] | join(",")')
        fi
        printf '%-12s %-10s %-7s %s\n' "$(dom "$vm")" "$state" "$agent" "$ips"
    done
    virsh snapshot-list "$(dom dc01)" --name 2>/dev/null | sed '/^$/d; s/^/instantané : /' || true
}

# Exécuter le corrigé complet sur ADMIN, comme le ferait un étudiant, puis afficher le bilan.
cmd_recette() {
    password
    [[ -n "${TP_PASSWORD:-}" ]] || die "définir TP_PASSWORD (secret temporaire des comptes tp.*)"
    info "Copie du dépôt dans C:\\TP-PowerShell sur ADMIN"
    ga_cmd admin '$cd = (Get-Volume | Where-Object FileSystemLabel -eq "TP-POWERSHELL").DriveLetter; if (-not $cd) {throw "ISO du dépôt absent"}; robocopy "${cd}:\" C:\TP-PowerShell /E /A-:R /NFL /NDL /NJH /NJS /NP | Out-Null; if ($LASTEXITCODE -ge 8) {throw "robocopy $LASTEXITCODE"}; "Dépôt copié depuis ${cd}:"'
    ga_ps admin "$HERE/invite/Invoke-Recette.ps1" -AdminPassword "$LAB_PASSWORD" -UserPassword "$TP_PASSWORD"
}

cmd_supprimer() {
    local vm disks r
    [[ ${FORCE:-} == 1 ]] || { read -rp "Supprimer définitivement les VM $LAB-* et le réseau $NET ? (oui/non) " r; [[ $r == oui ]] || exit 1; }
    for vm in "${VMS[@]}"; do
        virsh dominfo "$(dom "$vm")" >/dev/null 2>&1 || continue
        virsh destroy "$(dom "$vm")" >/dev/null 2>&1 || true
        for s in $(virsh snapshot-list "$(dom "$vm")" --name 2>/dev/null); do
            virsh snapshot-delete "$(dom "$vm")" "$s" >/dev/null || true
        done
        # Supprimer le seul disque système : jamais --remove-all-storage, qui effacerait aussi
        # les ISO Windows encore insérés s'ils appartiennent à un pool libvirt.
        eject_all "$vm"
        disks=$(virsh domblklist "$(dom "$vm")" --details | awk '$2 == "disk" {print $3}' | paste -sd,)
        virsh undefine "$(dom "$vm")" --nvram --tpm ${disks:+--storage "$disks"} >/dev/null
        virsh vol-delete --pool "$POOL" "$LAB-$vm-unattend.iso" >/dev/null 2>&1 || true
    done
    virsh vol-delete --pool "$POOL" "$LAB-depot.iso" >/dev/null 2>&1 || true
    virsh net-destroy "$NET" >/dev/null 2>&1 || true
    virsh net-undefine "$NET" >/dev/null 2>&1 || true
    info "Maquette $LAB supprimée"
}

cmd_construire() {
    cmd_verifier
    password
    for vm in "${VMS[@]}"; do cmd_installer "$vm"; done
    cmd_configurer
    cmd_finaliser
    cmd_instantane "$SNAPSHOT"
    cmd_demarrer
}

cmd_console() {
    virt-manager --connect "$LIBVIRT_DEFAULT_URI" --show-domain-console "$(dom "$1")" >/dev/null 2>&1 &
}

cmd_aide() {
    cat <<EOF
Usage : [LAB=tp] [LAB_PASSWORD=...] kvm/lab.sh COMMANDE

  verifier            Contrôler KVM, libvirt, swtpm, OVMF et les trois ISO
  images [ISO...]     Lister les éditions d'un ISO Windows et leur index
  construire          Tout faire : installer, configurer, finaliser, instantané $SNAPSHOT
  installer VM        Créer une VM (dc01, srv01, admin) et lancer Windows sans surveillance
  configurer          IP fixes, forêt learn-it.local sur DC01, jonction de SRV01 et ADMIN
  controler           Vérifier domaine, canal sécurisé et WinRM depuis ADMIN
  finaliser           Éjecter les ISO d'installation, insérer l'ISO du dépôt dans ADMIN
  depot               Régénérer l'ISO du dépôt et l'insérer dans ADMIN
  demarrer | arreter  Démarrer (DC01 d'abord) ou arrêter proprement les trois VM
  redemarrer VM       Redémarrer une VM par l'agent et attendre son retour
  instantane [NOM]    Arrêter puis photographier les trois VM ensemble ($SNAPSHOT par défaut)
  restaurer [NOM]     Revenir aux trois instantanés NOM puis redémarrer
  etat                État, agent et adresses des VM
  console VM          Ouvrir la console graphique de la VM dans virt-manager
  ps VM F.ps1 [args]  Exécuter un script PowerShell local dans la VM (en SYSTEM)
  cmd VM 'commande'   Exécuter une commande PowerShell dans la VM (en SYSTEM)
  recette             Jouer tout le corrigé sur ADMIN (exige aussi TP_PASSWORD)
  supprimer           Détruire les VM, leurs disques, instantanés et le réseau

Variables : LAB=$LAB  POOL=$POOL  SERVER_ISO  SERVER_INDEX=$SERVER_INDEX  SERVER_OSINFO=$SERVER_OSINFO
            WIN11_ISO  WIN11_INDEX=$WIN11_INDEX  VIRTIO_ISO  DC_RAM  SRV_RAM  ADMIN_RAM
EOF
}

case "${1:-aide}" in
    verifier|construire|configurer|controler|finaliser|depot|demarrer|arreter|etat|recette|supprimer|aide)
        "cmd_$1" ;;
    images) shift; cmd_images "$@" ;;
    installer) [[ $# -eq 2 ]] || die "installer VM"; cmd_installer "$2" ;;
    instantane|restaurer) "cmd_$1" "${2:-}" ;;
    redemarrer) [[ $# -eq 2 ]] || die "redemarrer VM"; reboot_vm "$2" ;;
    console) [[ $# -eq 2 ]] || die "console VM"; cmd_console "$2" ;;
    ps) [[ $# -ge 3 ]] || die "ps VM fichier.ps1 [arguments]"; vm=$2 f=$3; shift 3; ga_ps "$vm" "$f" "$@" ;;
    cmd) [[ $# -ge 3 ]] || die "cmd VM 'commande'"; vm=$2; shift 2; ga_cmd "$vm" "$*" ;;
    *) cmd_aide; exit 1 ;;
esac
