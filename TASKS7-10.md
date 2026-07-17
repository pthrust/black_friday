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

## Задание 9. Настройка чтения с реплик и консистентность

## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

### Задание 10.1

### Задание 10.2

### Задание 10.3