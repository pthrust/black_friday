# Задания с 7 по 10

## Задание 7. Проектирование схем коллекций для шардирования данных

### 7.1. Коллекция orders

#### Схема коллекции

```javascript
// orders collection schema
{
  _id: ObjectId("..."),                    // Уникальный идентификатор заказа
  client_id: String("user_12345"),          // Идентификатор клиента
  order_date: ISODate("2026-07-16T10:30:00Z"), // Дата и время оформления
  items: [                                  // Список заказанных товаров
    {
      product_id: ObjectId("..."),
      product_name: String("Смартфон X"),
      category: String("Электроника"),
      price: Number(59999.99),
      quantity: Number(1)
    }
  ],
  status: String("delivered"),              // Статус заказа
  total_amount: Number(59999.99),           // Общая сумма заказа
  geo_zone: String("moscow")                // Геозона заказа
}
```

#### Рекомендуемый хешированный шард-ключ в данной ситуации: { client_id: "hashed" }. Обоснование:

- Хешированное шардирование обеспечивает равномерное распределение данных по всем шардам.  
- client_id имеет уникальные значения, что критически важно для равномерного распределения.  
- Основные операции — поиск истории заказов конкретного пользователя (client_id) — будут выполняться на одном шарде, что минимизирует сетевые задержки.  
- Избегаем монотонно возрастающих ключей (например, _id или order_date), которые создают «горячие» шарды при range-шардировании.  
- Альтернативный вариант (не рекомендуется): range-шардирование по order_date. При высокой нагрузке на запись все новые заказы будут попадать в один шард, создавая перекос.

#### Команда настройки шардирования:

```javascript
// Включение шардирования для базы данных
sh.enableSharding("mobile_world")

// Настройка шардирования коллекции orders
sh.shardCollection("mobile_world.orders", { "client_id": "hashed" })

// Для быстрой истории заказов (сортировка по дате)
db.orders.createIndex({ client_id: 1, order_date: -1 })

// Для поиска по статусу (если нужно)
db.orders.createIndex({ client_id: 1, status: 1 })
```

#### Команды основных операций

```javascript

// Быстрое создание заказа (с одновременным списанием остатков)
const session = db.getMongo().startSession()
session.startTransaction()
try {
  db.orders.insertOne({
    client_id: "user_12345",<br> order_date: new Date(),
    items: [ { product_id: ObjectId("..."), product_name: "Смартфон X", category: "Электроника", price: 59999.99, quantity: 1 } ]
    status: "created",
    total_amount: 59999.99,
    geo_zone: "moscow"<br>
  }, { session });
  
  db.products.updateOne(
    { _id: ObjectId("...") },
    { $inc: { "stock.moscow": -1 } },
    { session }
   );
  session.commitTransaction();
} catch(e) { session.abortTransaction(); }

// Поиск истории заказов пользователя (сортировка по дате)
db.orders.find({ client_id: "user_12345" }).sort({ order_date: -1 }).limit(20)

// Отображение статуса заказа
db.orders.findOne({ _id: ObjectId("...") })
db.orders.findOne({ client_id: "user_12345", _id: ObjectId("...") })

// Заказы за период (админка)
db.orders.find({
  client_id: "user_12345",
  order_date: { $gte: ISODate("2026-01-01"), $lt: ISODate("2026-02-01") }
  }).sort({ order_date: 1 })
```

#### Риски и их минимизация

| Риск | Минимизация |
|---|---|
| Запросы по order_date без client_id становятся scatter-gather | Добавить составной индекс: { client_id: 1, order_date: -1 } |
| Неравномерное распределение при малом количестве клиентов | Контролировать размер чанков через chunkSize |

### 7.2. Коллекция products

#### Схема коллекции

```javascript
// products collection schema
{
  product_id: ObjectId("..."),             // Уникальный идентификатор товара
  name: String("Смартфон X"),              // Наименование
  category: String("Электроника"),         // Категория товара
  price: Number(59999.99),                 // Цена
  stock: {                                 // Остаток в каждой геозоне
    "moscow": Number(150),
    "ekaterinburg": Number(50),
    "kaliningrad": Number(30)
  },
  attributes: {                            // Дополнительные атрибуты
    color: String("черный"),
    size: String("M")
  }
}
```
#### Рекомендуемый хешированный шард-ключ в данной ситуации: { product_id: "hashed" }. Обоснование:

- product_id имеет максимальную кардинальность и идеально подходит для хешированного шардирования.  
- Основные операции — поиск по категориям и фильтрация по цене — не зависят от конкретного шард-ключа и в любом случае требуют scatter-gather запросов.  
- Частые обновления остатков при покупках равномерно распределяются по всем шардам благодаря хешированию.  
- Избегаем использования category как шард-ключа — это приведёт к «горячему» шарду для категории «Электроника» (70% запросов).

#### Команда настройки шардирования:

```javascript
sh.shardCollection("mobile_world.products", { "product_id": "hashed" })

// Для поиска по категориям и фильтрации по цене
db.products.createIndex({ category: 1, price: 1 })

// Для поиска по имени (если нужно)
db.products.createIndex({ name: "text" })
```

#### Команды основных операций

```javascript

// Частое обновление остатков при покупке
db.products.updateOne(
  { product_id: ObjectId("...") },
  { $inc: { "stock.moscow": -1 } }
)

// Поиск товаров по категории с фильтрацией по цене
db.products.find({
  category: "Электроника",
  price: { $lt: 50000 }
}).sort({ price: 1 })

// Описание товара на странице продукта
db.products.findOne({ product_id: ObjectId("...") })
```

#### Риски и их минимизация

| Риск | Минимизация |
|---|---|
| Запросы по категориям требуют обращения ко всем шардам | Использовать композитные индексы: { category: 1, price: 1 } |
| Обновление остатков конкретного товара — точечный запрос по product_id | Запрос направляется на один шард (эффективно) |

### 7.3. Коллекция carts

#### Схема коллекции

```javascript
// carts collection schema
{
  _id: ObjectId("..."),                    // Уникальный идентификатор корзины
  user_id: String("user_12345"),           // Идентификатор пользователя
  session_id: String("session_abc123"),    // Session ID для гостей
  items: [                                  // Список товаров
    {
      product_id: ObjectId("..."),
      quantity: Number(2)
    }
  ],
  status: String("active"),                // "active" | "ordered" | "abandoned"
  created_at: ISODate("2026-07-16T10:00:00Z"),
  updated_at: ISODate("2026-07-16T10:30:00Z"),
  expires_at: ISODate("2026-07-23T10:00:00Z") // TTL для автоматической очистки
}
```

#### Рекомендуемый составной шард-ключ в данной ситуацимм: { user_id: "hashed", session_id: "hashed" }. Обоснование:

- user_id обеспечивает равномерное распределение данных для авторизованных пользователей.  
- session_id покрывает гостевые корзины (когда user_id отсутствует).  
- Составной ключ гарантирует, что запросы по { session_id, status: "active" } или { user_id, status: "active" } попадают на один шард.  
- Хешированное шардирование предотвращает «горячие» точки.

#### Команда настройки шардирования:

```javascript
sh.shardCollection("mobile_world.carts", { "user_id": "hashed", "session_id": "hashed" })

// Для быстрого поиска по user_id (с учётом статуса)
db.carts.createIndex({ user_id: 1, status: 1 })

// Для быстрого поиска по session_id (с учётом статуса)
db.carts.createIndex({ session_id: 1, status: 1 })

// Для TTL-очистки
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

#### Команды основных операций

```javascript

// Создание корзины для гостя
const sessionId = "session_abc123";
db.carts.insertOne(
  shard_key: sessionId,
  user_id: null,
  session_id: sessionId,
  items: [],
  status: "active",
  created_at: new Date(),
  updated_at: new Date(),
  expires_at: new Date(Date.now() + 7*24*60*60*1000)
})

// Создание корзины для авторизованного пользователя
const userId = "user_12345";
db.carts.insertOne({
  shard_key: userId,
  user_id: userId,
  session_id: null,
  items: [],
  status: "active",
  created_at: new Date(),
  updated_at: new Date(),
  expires_at: new Date(Date.now() + 7*24*60*60*1000)
})

// Получение текущей корзины по session_id
const sessionId = "session_abc123";
db.carts.findOne({
  shard_key: sessionId,
  session_id: sessionId,
  status: "active"
})

// Получение текущей корзины по user_id
const userId = "user_12345";
db.carts.findOne({
  shard_key: userId,
  user_id: userId,
  status: "active"
})

// Добавление товара в корзину для авторизованного
db.carts.updateOne(
  { shard_key: userId, user_id: userId, status: "active" },
  { $push: { items: { product_id: ObjectId("..."), quantity: 1 } },
  $set: { updated_at: new Date() } }
)

// Удаление товара из корзины
db.carts.updateOne(
  { shard_key: sessionId, session_id: sessionId, status: "active" },
  { $pull: { items: { product_id: ObjectId("...") } },
  $set: { updated_at: new Date() } }
)

// Слияние гостевой корзины в пользовательскую (после логина)
const guestSession = "session_abc123";
const userId = "user_12345";
// 1. Найти гостевую корзину
const guestCart = db.carts.findOne({
  shard_key: guestSession,
  session_id: guestSession,
  status: "active"
});
if (guestCart) {
// 2. Обновить пользовательскую корзину (добавить товары)
  db.carts.updateOne(
    { shard_key: userId, user_id: userId, status: "active" },
    { $push: { items: { $each: guestCart.items } },
    $set: { updated_at: new Date() } }
  );
// 3. Отметить гостевую как abandoned
  db.carts.updateOne(
    { shard_key: guestSession, session_id: guestSession },
    { $set: { status: "abandoned", updated_at: new Date() } }
  );
}

// Отметка корзины как заказанной
db.carts.updateOne(
  { shard_key: userId, user_id: userId, status: "active" },
  { $set: { status: "ordered", updated_at: new Date() } }
)
```

#### Риски и их минимизация

| Риск | Минимизация |
|---|---|
| Гостевые корзины без user_id могут распределяться неравномерно | Использовать составной ключ с session_id как второй компонент |
| Слияние гостевой корзины в пользовательскую требует двух запросов | Выполнять операции в транзакции |

## Задание 8. Выявление и устранение «горячих» шардов

### 8.1 Проблема

Категории «Электроника» привела к перегрузке одного из шардов MongoDB, потому что 70% запросов приходилось именно на эти товары

### 8.2 Cмягчение последствий и мониторинг

### 8.2. Метрики мониторинга состояния шардов

#### 8.2.1. Базовые метрики производительности
| Метрика | Источник | Команда получения | Порог оповещения |
|---|---|---|---|
| Количество операций (OP/s) на шард | mongostat или serverStatus | mongostat --discover | Отклонение > 30% от среднего |
| Время отклика (latency) для чтения/записи | serverStatus | db.runCommand({ serverStatus: 1 }) | p95 > 100 мс |
| Размер очереди (queued reads/writes) | serverStatus.globalLock | db.serverStatus().globalLock	> 10 |
| Загрузка CPU / Memory / IO | Системный мониторинг | top, iostat, vmstat | CPU > 80%, Memory > 85% |
| Кэш-промахи WiredTiger | serverStatus.wiredTiger.cache | db.serverStatus().wiredTiger.cache | > 10% |

#### 8.2.2. Метрики распределения данных
| Метрика | Источник | Команда получения | Порог оповещения |
|---|---|---|---|
| Количество чанков на шард | config.chunks | sh.status() или агрегация | Отклонение > 20% от среднего |
| Размер чанков (max / min) | config.chunks | db.chunks.aggregate(...) | > 2× chunkSize |
| Количество документов в чанках | config.chunks + статистика | Агрегация с $lookup | Неравномерное распределение документов |
| Частота перемещения чанков (balancer) | config.changelog | db.changelog.count({ what: "moveChunk.start" }) | > 100/час |
| Объём данных (GB) на шард | db.stats() каждого шарда | db.runCommand({ dbStats: 1 }) | Отклонение > 30% |

#### 8.2.3. Специфические метрики для «горячих» категорий
| Метрика | Источник | Команда получения | Описание |
|---|---|---|---|
| Частота запросов по категориям | Логи приложения или агрегация | Анализ логов / использование $match в профилировщике | Выявляет, какие категории создают наибольшую нагрузку |
| Время выполнения запросов по категориям | Профилировщик MongoDB | db.system.profile.find({ ns: "products" }) | Помогает найти медленные запросы к конкретным категориям |
| Распределение операций по шардам для категории | Анализ маршрутизации | Использование explain() для запросов | Показывает, на какие шарды идут запросы по категории |

#### 8.2.4. Команды для сбора метрик
```javascript
// 1. Общая статистика шардов
sh.status()

// 2. Количество чанков на шард
use config
db.chunks.aggregate([
  { $group: { _id: "$shard", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// 3. Распределение данных по шардам (размер в MB)
db.getSiblingDB("mobile_world").runCommand({ collStats: "products" }).shards

// 4. Мониторинг очередей и блокировок
db.runCommand({ serverStatus: 1 }).globalLock

// 5. Активность балансировщика
use config
db.changelog.find({ what: /moveChunk/ }).sort({ time: -1 }).limit(10)

// 6. Профилирование запросов к коллекции products (включить профилировщик)
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find({ ns: "mobile_world.products" }).sort({ ts: -1 }).limit(20)
```

## Задание 9. Настройка чтения с реплик и консистентность

### 9.1. Коллекция products
| Операция | Read Preference | maxStalenessSeconds | Обоснование |
|---|---|---|---|
| Просмотр описания товара (страница продукта) | secondaryPreferred | 4 с | Описание и характеристики меняются редко, небольшая задержка допустима. Использование secondary снижает нагрузку на primary |
| Поиск товаров по категории и фильтрация по цене (каталог) | secondaryPreferred | 4 с | Каталог читается интенсивно, обновление данных (цены, наличие) происходит не так часто. Задержка до 4 с не критична для пользовательского опыта |
| Проверка остатков при добавлении в корзину | primary | 0 (не применимо) | Критично: при добавлении в корзину нужно видеть актуальное количество. Даже несколько секунд задержки могут привести к ситуации, когда пользователь добавит товар, которого уже нет в наличии, или при оформлении заказа возникнет конфликт |
| Проверка остатков при оформлении заказа (финальное списание) | primary | 0 | Критично: списание остатков должно быть строго консистентным. Чтение с secondary может дать устаревший остаток, что приведёт к overselling (продаже больше, чем есть). Операция должна выполняться в транзакции с чтением и записью на primary |

### 9.2. Коллекция orders
| Операция | Read Preference | maxStalenessSeconds | Обоснование |
|---|---|---|---|
| История заказов пользователя (список заказов) | secondaryPreferred | 2 с | Пользователь просматривает свои прошлые заказы. Допустима небольшая задержка (до 2 с). Использование secondary разгружает primary |
| Детали конкретного заказа (просмотр) | secondaryPreferred | 2 с | Аналогично истории – чтение данных, которые не меняются. Secondary допустим |
| Статус заказа (отображение пользователю на странице заказа) | primaryPreferred | 2 с | Статус заказа меняется нечасто, но пользователь ожидает видеть его актуальным. primaryPreferred обеспечит чтение с primary, если он доступен, иначе с secondary, но с ограничением задержки 2 с – чтобы не получить сильно устаревший статус |
| Создание заказа (сама операция записи) | primary | 0 c | Это запись, всегда идёт на primary |
| Проверка дублирования заказа (например, при повторной отправке) | primary | 0 c | При создании заказа может потребоваться проверка, не был ли уже создан такой же заказ (по idempotency ключу). Чтение должно быть с primary, чтобы избежать создания дубликатов из-за задержки репликации |

### 9.3. Коллекция carts
| Операция | Read Preference | maxStalenessSeconds | Обоснование |
|---|---|---|---|
| Получение текущей корзины пользователя (при загрузке страницы корзины) | primary | 0 | Критично: корзина – интерактивный объект, пользователь ожидает видеть актуальное состояние. Если прочитать с secondary с задержкой, можно показать устаревшую корзину (например, после удаления товара). Поэтому строго primary |
| Получение корзины для отображения количества товаров в мини-корзине (header сайта) | primaryPreferred | 1 с | Эта информация часто запрашивается на каждой странице. Если secondary отстаёт не более 1 с, можно использовать его. Однако для гарантии актуальности лучше читать с primary, но допустим компромисс с primaryPreferred и малой задержкой |
| Добавление/обновление товара в корзине (сами операции записи) | primary | 0 | Все записи идут на primary |
| Слияние гостевой корзины с пользовательской после логина | primary | 0 | Требуется атомарное чтение двух корзин и их обновление. Для избежания конфликтов и потери данных – только primary |
| Проверка, есть ли активная корзина у пользователя (перед созданием новой) | primary | 0 | Если проверять на secondary, можно создать дублирующую корзину, если запись ещё не среплицировалась. Для целостности – primary |

## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

### Задание 10.1

### Задание 10.2

### Задание 10.3