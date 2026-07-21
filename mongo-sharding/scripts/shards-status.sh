#!/bin/bash

echo -n "Documents on shard1: "
docker exec shard1 mongosh --port 27018 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"

echo -n "Documents on shard2: "
docker exec shard2 mongosh --port 27019 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"