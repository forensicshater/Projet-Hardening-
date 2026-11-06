
#!/bin/bash

set -euo pipefail

SEUIL="${1:-5}"

if [[ $EUID -ne 0 ]]; then
    echo "Erreur : executer ce script en root"
    exit 2
fi

if [[ ! "$SEUIL" =~ ^[1-9][0-9]*$ ]]; then
    echo "Erreur : seuil invalide"
    exit 2
fi

FICHIER=$(mktemp)
trap 'rm -f "$FICHIER"' EXIT

journalctl -u ssh.service --since "24 hours ago" \
    --no-pager -o cat > "$FICHIER"

awk -v seuil="$SEUIL" '
function adresse(    i) {
    for (i = 1; i < NF; i++)
        if ($i == "from")
            return $(i+1)
    return ""
}

function utilisateur(    i) {
    for (i = 1; i < NF; i++) {
        if ($i == "for") {
            if ($(i+1) == "invalid" && $(i+2) == "user")
                return $(i+3)
            return $(i+1)
        }
    }

    if ($1 == "Invalid" && $2 == "user")
        return $3

    return ""
}

{
    if ($0 ~ /Failed (password|publickey) for/ ||
        $0 ~ /^Invalid user /) {
        ip = adresse()
        user = utilisateur()

        if (ip != "")
            echecs[ip]++

        if (user != "")
            comptes[user]++

        total_echecs++
    }

    if ($0 ~ /Accepted (publickey|password) for/) {
        user = utilisateur()

        if (user != "")
            reussites[user]++

        total_reussites++
    }
}

END {
    alerte = 0

    print "=== RAPPORT SSH ==="
    print "Seuil :", seuil
    print ""

    print "Echecs par IP :"
    for (ip in echecs) {
        print ip, ":", echecs[ip]

        if (echecs[ip] >= seuil)
            alerte = 1
    }

    print ""
    print "Comptes vises :"
    for (user in comptes)
        print user, ":", comptes[user]

    print ""
    print "Connexions reussies :"
    for (user in reussites)
        print user, ":", reussites[user]

    print ""
    print "Total echecs :", total_echecs + 0
    print "Total reussites :", total_reussites + 0

    if (alerte) {
        print "ALERTE : seuil depasse"
        exit 1
    }

    print "OK : aucune IP au seuil d alerte"
    exit 0
}
' "$FICHIER"
