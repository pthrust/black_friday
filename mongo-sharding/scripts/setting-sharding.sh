#!/bin/bash

echo "[*] Setting config server"
docker exec configSrv mongosh --port 27017 --eval "
  rs.initiate({
    _id: 'config_server',
    configsvr: true,
    members: [{ _id: 0, host: 'configSrv:27017' }]
  })
"
sleep 3
echo

echo "[*] Setting shard1"
docker exec shard1 mongosh --port 27018 --eval "
  rs.initiate({
    _id: 'shard1',
    members: [{ _id: 0, host: 'shard1:27018' }]
  })
"
docker exec shard1 mongosh --port 27018 --eval "rs.status()"
sleep 3
echo

echo "[*] Setting shard2"
docker exec shard2 mongosh --port 27019 --eval "
  rs.initiate({
    _id: 'shard2',
    members: [{ _id: 0, host: 'shard2:27019' }]
  })
"
docker exec shard2 mongosh --port 27019 --eval "rs.status()"
sleep 3
echo

echo "[*] Setting routers"
docker exec mongos_router mongosh --port 27020 --eval "
  sh.addShard('shard1/shard1:27018');
  sh.addShard('shard2/shard2:27019');
"
sleep 3
echo

echo "[*] Enable sharding"
docker exec mongos_router mongosh --port 27020 --eval "
  sh.enableSharding('somedb');
  sh.shardCollection('somedb.helloDoc', { _id: 'hashed' });
"
sleep 3
echo

echo "[*] Insert generated items to somedb"
docker exec mongos_router mongosh --port 27020 --eval "
(async () => {
  db = db.getSiblingDB('somedb');
  const total = 20000;
  const batchSize = 1000;
  let inserted = 0;
  for (let i = 0; i < total; i += batchSize) {
    const docs = [];
    for (let j = i; j < i + batchSize && j < total; j++) {
      docs.push({ age: j, name: 'ly' + j });
    }
    try {
      const res = await db.helloDoc.insertMany(docs, { ordered: false });
      const count = Object.keys(res.insertedIds).length;
      inserted += count;
      print('Batch ' + (i / batchSize + 1) + ' inserted ' + count + ' docs');
    } catch (e) {
      print('ERROR in batch ' + (i / batchSize + 1) + ': ' + e.message);
    }
  }
  print('Total inserted in this run: ' + inserted);
  const finalCount = await db.helloDoc.countDocuments();
  print('Total documents in collection now: ' + finalCount);
})();
"
sleep 3
echo

echo -n "[*] Generated items on shard1: "
docker exec shard1 mongosh --port 27018 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"

echo -n "[*] Generated items on shard2: "
docker exec shard2 mongosh --port 27019 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"