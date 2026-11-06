#!/usr/bin/env bash
# s5/p2: drift u DNS-u. Zapis koji upravlja Terraform mijenjamo "ručno" (nsupdate, mimo koda),
# pa plan pokazuje razliku, a apply vraća stanje iz koda. Pokreće se iz make s5-p2-apply.
set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
KEY=/var/lib/ruo5/kljucevi/ruo-tf.key

echo "\$ nsupdate -k ruo-tf.key   (briše app.oblak.ruo.lab i mijenja adresu za db)"
sudo nsupdate -k "$KEY" <<'EOF'
server 10.50.0.53
zone oblak.ruo.lab
update delete app.oblak.ruo.lab. A
update delete db.oblak.ruo.lab. A
update add db.oblak.ruo.lab. 300 A 10.40.3.99
send
EOF
sleep 1
echo "app: '$(dig +short @10.50.0.53 app.oblak.ruo.lab A)'   db: $(dig +short @10.50.0.53 db.oblak.ruo.lab A)"
