
#!/bin/bash

set -euo pipefail

CSV="$(dirname "$(realpath "$0")")/comptes.csv"
DOSSIER_CLES="$(dirname "$CSV")/config/cles_publiques"
EXPIRATION_FREELANCE="2026-12-31"

if [[ $EUID -ne 0 ]]; then
    echo "Erreur : il faut executer ce script en root"
    exit 1
fi

if [[ ! -f "$CSV" ]]; then
    echo "Erreur : fichier comptes.csv introuvable"
    exit 1
fi

IFS= read -r entete < "$CSV"
if [[ "$entete" != "login;nom;groupe_principal;groupes_secondaires" ]]; then
    echo "Erreur : format de comptes.csv incorrect"
    exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
    echo "Erreur : le paquet acl est necessaire"
    exit 1
fi

if ! date -d "$EXPIRATION_FREELANCE" >/dev/null 2>&1; then
    echo "Erreur : date d'expiration invalide"
    exit 1
fi

groupes=(admins acces_ssh support dev design commercial freelance)

for groupe in "${groupes[@]}"; do
    if ! getent group "$groupe" >/dev/null; then
        groupadd "$groupe"
        echo "Groupe cree : $groupe"
    else
        echo "Groupe deja existant : $groupe"
    fi
done

while IFS=';' read -r login nom groupe_principal groupes_secondaires; do
    [[ -z "$login" ]] && continue

    if [[ ! "$login" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Erreur : identifiant invalide : $login"
        exit 1
    fi

    if [[ -z "$nom" ]]; then
        echo "Erreur : nom manquant pour $login"
        exit 1
    fi

    if [[ ! " ${groupes[*]} " == *" $groupe_principal "* ]]; then
        echo "Erreur : groupe principal invalide pour $login"
        exit 1
    fi

    if [[ -n "$groupes_secondaires" ]]; then
        IFS=',' read -ra secondaires <<< "$groupes_secondaires"

        for groupe in "${secondaires[@]}"; do
            if [[ ! " ${groupes[*]} " == *" $groupe "* ]]; then
                echo "Erreur : groupe secondaire invalide : $groupe"
                exit 1
            fi
        done
    fi

    if ! id "$login" &>/dev/null; then
        useradd -m -c "$nom" -g "$groupe_principal" "$login"
        echo "Utilisateur cree : $login"
    else
        usermod -c "$nom" -g "$groupe_principal" "$login"
        echo "Utilisateur existant : $login"
    fi

    usermod -G "$groupes_secondaires" "$login"

    repertoire=$(getent passwd "$login" | cut -d: -f6)

    if [[ ! -d "$repertoire" ]]; then
        mkdir -p "$repertoire"
        chown "$login:$groupe_principal" "$repertoire"
    fi

    chmod 700 "$repertoire"

    if [[ "$groupe_principal" == "freelance" ]]; then
        chage -E "$EXPIRATION_FREELANCE" "$login"
        echo "Expiration configuree : $login"
    fi

    if [[ ",${groupes_secondaires}," == *",acces_ssh,"* ]]; then
        cle="$DOSSIER_CLES/$login.pub"

        if [[ ! -s "$cle" ]]; then
            echo "Erreur : cle publique manquante : $cle"
            exit 1
        fi

        install -d -m 700 -o "$login" -g "$groupe_principal" "$repertoire/.ssh"
        install -m 600 -o "$login" -g "$groupe_principal" "$cle" "$repertoire/.ssh/authorized_keys"

        echo "Cle SSH installee : $login"
    fi

done < <(tail -n +2 "$CSV")

configurer_acl() {
    local chemin="$1"
    local groupe="$2"
    local droits="$3"

    setfacl -m "g:${groupe}:${droits}" "$chemin"
    setfacl -m "d:g:${groupe}:${droits}" "$chemin"
}

mkdir -p /srv/projets/externe
mkdir -p /srv/maquettes
mkdir -p /srv/clients

for chemin in /srv/projets /srv/projets/externe /srv/maquettes /srv/clients; do
    chown root:root "$chemin"
    setfacl -b -k "$chemin"
    chmod 0700 "$chemin"
    setfacl -m u::rwx,g::---,m::rwx,o::--- "$chemin"
    setfacl -m d:u::rwx,d:g::---,d:m::rwx,d:o::--- "$chemin"
done

configurer_acl /srv/projets dev rwx
configurer_acl /srv/projets design r-x

setfacl -m g:freelance:--x /srv/projets

configurer_acl /srv/projets/externe dev rwx
configurer_acl /srv/projets/externe design r-x
configurer_acl /srv/projets/externe freelance rwx

configurer_acl /srv/maquettes dev r-x
configurer_acl /srv/maquettes design rwx
configurer_acl /srv/maquettes commercial r-x

configurer_acl /srv/clients commercial rwx

echo "Repertoires et ACL configures"
echo "Traitement des comptes all good"

