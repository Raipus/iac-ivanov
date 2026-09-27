export PREFIX=ivanov-01

yc compute instance delete "$PREFIX-web-1"
yc compute instance delete "$PREFIX-web-2"
yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"

yc compute instance list
yc vpc network list
yc compute disk list