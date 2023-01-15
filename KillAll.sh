echo "--> Kill All Apps"
killall geth beacon-chain validator
pkill -f ./prysm.*
pkill -f lodestar.js
pkill -f lighthouse
docker compose -f /home/adigium/eth-pos-devnet/docker-run.yml down || echo Looks like docker is not running.

