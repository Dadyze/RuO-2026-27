#!/usr/bin/env bash
# s4/p5: SSH (port 22) smije samo s adrese bastiona. Zahtijeva lab (s4/p1) i pravila iz role (make s4-p5-apply).
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
BASTION=10.40.1.10
ip netns exec ruo-web ip addr show eth0 | grep -q "$BASTION" || ip netns exec ruo-web ip addr add "$BASTION/24" dev eth0   # bastion je dodatna adresa na web mašini (samo za lab)
PIDS=()
for t in "ruo-app 10.40.2.2" "ruo-db 10.40.3.2"; do set -- $t
  ip netns exec "$1" python3 -c 'import socket,sys
s=socket.socket(); s.setsockopt(1,2,1); s.bind((sys.argv[1],22)); s.listen(8)
while True: s.accept()[0].close()' "$2" & PIDS+=($!)
done
trap 'kill "${PIDS[@]}" 2>/dev/null' EXIT; sleep 1
proba() { # izvorna-adresa odredište očekivano
  r=$(ip netns exec ruo-web python3 -c 'import socket,sys
c=socket.socket(); c.settimeout(2); c.bind((sys.argv[1],0)); print("dozvoljeno" if c.connect_ex((sys.argv[2],22))==0 else "blokirano")' "$1" "$2")
  [ "$r" = "$3" ] && oz=ok || oz=RAZLIKA
  printf '  SSH iz %-10s -> %-10s :22  %-11s (očekivano: %-10s) %s\n' "$1" "$2" "$r" "$3" "$oz"
}
proba "$BASTION" 10.40.2.2 dozvoljeno
proba "$BASTION" 10.40.3.2 dozvoljeno
proba 10.40.1.2  10.40.2.2 blokirano
proba 10.40.1.2  10.40.3.2 blokirano
