#!/bin/bash

echo "[*] Setting config server"
docker exec configSrv1 mongosh --port 27017 --eval "
  rs.initiate({
    _id: 'config_server_repl',
    configsvr: true,
    members: [
      { _id: 0, host: 'configSrv1:27017' },
      { _id: 1, host: 'configSrv2:27017' },
      { _id: 2, host: 'configSrv3:27017' }
    ]
  })
"
sleep 3
echo

echo "[*] Setting shard1"
docker exec shard11 mongosh --port 27018 --eval "
  rs.initiate({
    _id: 'shard1repl',
    members: [
      { _id: 0, host: 'shard11:27018' },
      { _id: 1, host: 'shard12:27018' },
      { _id: 2, host: 'shard13:27018' }
    ]
  })
"
docker exec shard11 mongosh --port 27018 --eval "rs.status()"
sleep 3
echo

echo "[*] Setting shard2"
docker exec shard21 mongosh --port 27019 --eval "
  rs.initiate({
    _id: 'shard2repl',
    members: [
      { _id: 0, host: 'shard21:27019' },
      { _id: 1, host: 'shard22:27019' },
      { _id: 2, host: 'shard23:27019' }
    ]
  })
"
docker exec shard21 mongosh --port 27019 --eval "rs.status()"
sleep 3
echo

echo "[*] Restarting mongos_router to pick up config replica"
docker restart mongos_router
sleep 5

echo "[*] Setting routers"
docker exec mongos_router mongosh --port 27020 --eval "
  sh.addShard('shard1repl/shard11:27018,shard12:27018,shard13:27018');
  sh.addShard('shard2repl/shard21:27019,shard22:27019,shard23:27019');
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
