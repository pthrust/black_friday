#!/bin/bash

echo "Documents on Shard1:"
echo -n "  shard11: "
docker exec shard11 mongosh --port 27018 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
echo -n "  shard12: "
docker exec shard12 mongosh --port 27018 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
echo -n "  shard13: "
docker exec shard13 mongosh --port 27018 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"

echo
echo "Documents on shard2: "
echo -n "  shard21: "
docker exec shard21 mongosh --port 27019 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
echo -n "  shard22: "
docker exec shard22 mongosh --port 27019 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
echo -n "  shard23: "
docker exec shard23 mongosh --port 27019 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
