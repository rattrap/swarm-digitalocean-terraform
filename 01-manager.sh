#!/usr/bin/bash
set -o nounset -o errexit

docker swarm init --advertise-addr ${PRIVATE_IP}
docker swarm join-token worker -q > /tmp/join