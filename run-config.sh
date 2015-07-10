####### with Virtual box VMs #######
# fedora-ab => running sipp client #
# fedora-cd => running sipp server #
# fedora-ef => running snort-ids   #

## starting virtual machine
VBoxManage startvm fedora-ab fedora-cd fedora-ef --type headless

## after some time, getting ip address and ssh
ssh docker@`VBoxManage guestproperty get "fedora-ab" "/VirtualBox/GuestInfo/Net/0/V4/IP" | awk '{ print $2 }'`
ssh docker@`VBoxManage guestproperty get "fedora-cd" "/VirtualBox/GuestInfo/Net/0/V4/IP" | awk '{ print $2 }'`
ssh docker@`VBoxManage guestproperty get "fedora-ef" "/VirtualBox/GuestInfo/Net/0/V4/IP" | awk '{ print $2 }'`

## setting CPU affinities (elevated permission required)
taskset -cp 0 `ps aux | grep fedora-ab | awk 'NR==1{print $2}'`
taskset -cp 1 `ps aux | grep fedora-cd | awk 'NR==1{print $2}'`
taskset -cp 2 `ps aux | grep fedora-ef | awk 'NR==1{print $2}'`

## starting docker daemon on all 3 VMs (elevated permission required)
docker -d &

## run containers
# fedora-cd
docker run -it --rm -p 0.0.0.0:5060:5060/udp --name sipp-server jmmills/sipp sipp -sn uas
# fedora-ab (remember to change the ip for fedora-cd)
# use -r <num> switch to specify rate of calls
docker run -it --rm --name sipp-client jmmills/sipp sipp -sn uac 192.168.56.102:5060
# fedora-ef (make sure to run promiscuous mode on enp0s3 <sudo ifconfig enp0s3 -promisc>
docker run -it --rm --net="host" --name snort-ids dodgeman9/snort-ids snort -d -i enp0s3 -c /etc/snort/snort.conf -l /var/log

## Power off VMs
VBoxManage controlvm fedora-ab poweroff
VBoxManage controlvm fedora-cd poweroff
VBoxManage controlvm fedora-ef poweroff

## run without virtual machines directly on host ##
# sipp server
docker run -it --rm --cpuset=0 --cpu-shares=512 -p 0.0.0.0:5060:5060/udp --name sipp-server jmmills/sipp sipp -sn uas
# sipp client (use -r <num> switch to specify rate of calls)
docker run -it --rm --cpuset=1 --name sipp-client aman/sipp sipp -sf uac_loop.xml 172.17.42.1:5060 -r 1000
# IDS
docker run -it --rm --cpuset=2 --net="host" --name snort-ids dodgeman9/snort-ids snort -d -i docker0 -c /etc/snort/snort.conf -l /var/log
# stress container
docker run --rm -it --cpuset=0 --cpu-shares=512 fedora/stress stress -c 1

## Network bandwidth control in VirtualBox
VBoxManage bandwidthctl fedora-ab add LIMIT --type network --limit 10m
VBoxManage modifyvm fedora-ab --nicbandwidthgroup1 LIMIT
VBoxManage bandwidthctl fedora-ab set LIMIT --limit 100m
VBoxManage bandwidthctl fedora-ab list
VBoxManage modifyvm fedora-ab --nicbandwidthgroup1 none

## docker network resource control
tc qdisc add dev vethc02f root handle 1: htb default 30
tc class add dev vethc02f parent 1: classid 1:30 htb rate 512kbit
tc class change dev vethc02f parent 1: classid 1:30 htb rate 512mbit

## install pyretic
git clone https://github.com/frenetic-lang/pyretic.git
sudo apt-get install python-dev
sudo pip install ipaddr bitarray networkzx netaddr yappi
git clone http://github.com/noxrepo/pox
export PYTHONPATH=$PYTHONPATH:/home/aman/Documents/cloud/pox
./pyretic.py pyretic.examples.topology_printer

## SDN with docker
./dockerovs add-br sdn-br0 172.31.0.1/16
docker run -it --rm --name=h1 --net=none gdanii/iperf /bin/bash
docker run -it --rm --name=h2 --net=none gdanii/iperf /bin/bash
./dockerovs add-port h1 sdn-br0 172.31.0.2/16 172.31.0.1
./dockerovs add-port h2 sdn-br0 172.31.0.3/16 172.31.0.1
./dockerovs del-br sdn-br0
./dockerovs cleanup

## NAT with pox [not working]
# create a bridge
./dockerovs add-br docker-br 172.31.0.1/16
# get the dpid
ovs-ofctl show docker-br
# attach the live port to the OpenVSwitch bridge (!careful)
ovs-vsctl add-port docker-br <PORT>
# run pox controller
python pox.py log.level --DEBUG misc.nat --dpid=<DPID> --outside-port=<PORT> --subnet=172.31.0.0/16 --inside-ip=172.31.0.1
# run the container
docker run -it --rm --net=none --name=ubuntu ubuntu /bin/sh
# attach the container to a port of openVSwitch
./dockerovs add-port ubuntu docker-br 172.31.0.3/16 172.31.0.1
# set default gateway
route add default gw 172.31.42.0

# cadvisor
docker run --volume=/:/rootfs:ro --volume=/var/run:/var/run:rw --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro --publish=8080:8080 --detach=true --name=cadvisor google/cadvisor:latest

# cloud
docker run -it --rm --net=host --name sipp-server aman/sipp sipp -sn uas -i 192.168.111.67
docker run -it --rm --name sipp-lient aman/sipp sipp -sf uac_loop.xml 192.168.111.67:5060
