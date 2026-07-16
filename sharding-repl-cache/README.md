# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Настраиваем шардирование с репликацией, заполняем базу данных сгенерированными записями в количестве 20000 и проверяем redis кэш 

```shell
./scripts/setting-sharding-replication.sh
```

Последним шагом проверяется использование кэша и результат выглядит примерно вот так:
Checking redis timing:
First load page. Time: 1.041666s
Second load page. Time 0.002739s

## Как проверить

### Проверить общую статистику по шардированию

Открыть в браузере http://localhost:8080

### Проверить отдельно статистику по каждому шарду + redis кэширование

```shell
./scripts/shards-status.sh
```
