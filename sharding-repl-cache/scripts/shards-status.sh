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

echo
echo "Checking redis timing:"
curl -s -o /dev/null -w "First load page. Time: %{time_total}s\n" http://173.17.0.6:8080/helloDoc/users
curl -s -o /dev/null -w "Second load page. Time %{time_total}s\n" http://173.17.0.6:8080/helloDoc/users
