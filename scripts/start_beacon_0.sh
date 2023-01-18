lighthouse beacon --testnet-dir /home/adigium/eth-pos-devnet/data/testnet --datadir /home/adigium/eth-pos-devnet/data/consensus/0 --execution-endpoint http://127.0.0.1:8551 --execution-jwt /home/adigium/eth-pos-devnet/data/execution/0/geth/jwtsecret --http --http-port 5052 --eth1 --staking --enable-private-discovery --enr-address 66.228.33.208 --enr-udp-port 9000 --enr-tcp-port 9000 --port 9000 --disable-packet-filter --graffiti ProducedBy_Beacon_Node_2 --boot-nodes=$(cat /home/adigium/eth-pos-devnet/consensus/bootnodes.txt 2>/dev/null | tr '\n' ',' | sed s/,$//g)
