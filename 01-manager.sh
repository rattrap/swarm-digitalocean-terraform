#!/usr/bin/bash
set -o nounset -o errexit

parted /dev/disk/by-id/scsi-0DO_Volume_registry mklabel gpt
parted -a opt /dev/disk/by-id/scsi-0DO_Volume_registry mkpart primary ext4 0% 100%
mkfs.ext4 -F /dev/disk/by-id/scsi-0DO_Volume_registry
mount /dev/disk/by-id/scsi-0DO_Volume_registry /mnt
mkdir /mnt/registry

docker swarm init --advertise-addr ${PRIVATE_IP}
docker swarm join-token worker -q > /tmp/join

docker network create \
    --driver=overlay \
    traefik-net

docker service create \
    --name traefik \
    --constraint=node.role==manager \
    --publish 80:80 --publish 8080:8080 \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --network traefik-net \
    traefik \
        --docker \
        --docker.swarmMode \
        --docker.domain=${DOMAIN} \
        --docker.watch --api

docker service create \
    --name whoami \
    --label "traefik.frontend.rule=HostRegexp:{catchall:.*}" \
    --label "traefik.frontend.priority=1" \
    --label "traefik.docker.network=traefik-net" \
    --label "traefik.port=80" \
    --network traefik-net \
    emilevauge/whoami

docker service create \
    --name registry \
    --constraint=node.role==manager \
    --label "traefik.port=5000" \
    --label "traefik.frontend.rule=Host:registry.${DOMAIN}" \
    --label "traefik.docker.network=traefik-net" \
    --mount type=bind,source=/mnt/registry,destination=/var/lib/registry \
    --network traefik-net \
    --publish 5000:5000 \
    registry:2