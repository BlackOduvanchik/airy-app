# Запуск бекенда с нуля

## Что нужно установить

1. **Node.js** (LTS, с [nodejs.org](https://nodejs.org) или через `nvm`).
2. **PostgreSQL** — один из вариантов:
   - **Docker** (если установлен): `docker run -d --name airy-postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=airy -p 5432:5432 postgres:16`
   - **Без Docker (macOS, через Homebrew):**
     ```bash
     brew install postgresql@16
     brew services start postgresql@16
     createdb airy
     ```
     Homebrew создаёт суперпользователя с твоим логином macOS (без пароля). В `.env` укажи:
     `DATABASE_URL="postgresql://ТВОЙ_ЛОГИН@localhost:5432/airy?schema=public"` (подставь имя пользователя из `whoami`, например `oduvanchik`). Если нужен пользователь `postgres`: `createuser -s postgres`, затем `createdb -O postgres airy` и в `.env`: `DATABASE_URL="postgresql://postgres:postgres@localhost:5432/airy?schema=public"` (пароль задаётся в psql при первом подключении или через `ALTER USER postgres PASSWORD 'postgres';`).
   - Либо установи PostgreSQL с [официального сайта](https://www.postgresql.org/download/) и создай базу `airy` и пользователя `postgres`.
3. **Redis** (для очередей и кэша). Чтобы запустить **без Redis**, в `.env` задай `REDIS_URL=redis://disabled` — кэш и очереди будут отключены, API будет работать. Или установи Redis (Docker: `docker run -d --name airy-redis -p 6379:6379 redis:7`) и укажи `REDIS_URL="redis://localhost:6379"`.

## Шаги запуска

В терминале:

```bash
# 1. Перейти в папку бекенда
cd airy-app/backend

# 2. Установить зависимости
npm install

# 3. Файл .env уже создан. Если его нет — скопируй и отредактируй:
#    cp .env.example .env
#    В .env должны быть: DATABASE_URL, JWT_SECRET (минимум 16 символов), можно добавить MOCK_AI=true и MOCK_EXCHANGE_RATES=true

# 4. Сгенерировать Prisma-клиент
npx prisma generate

# 5. Применить схему БД к PostgreSQL (Postgres должен быть запущен)
npx prisma db push

# 6. Запустить сервер
npm run dev
```

Сервер будет на **http://localhost:3000**.

Проверка:

```bash
curl http://localhost:3000/health
```

Ожидается ответ с `"status":"ok"` или подобным.

## Если что-то не так

- **«Can't reach database server»** — не запущен PostgreSQL. Запусти контейнер Docker (команда выше) или свой сервер Postgres.
- **«Config validation failed» / «DATABASE_URL: Required»** — в папке `airy-app/backend` нет файла `.env` или в нём нет `DATABASE_URL`. Скопируй `.env.example` в `.env` и задай `DATABASE_URL="postgresql://postgres:postgres@localhost:5432/airy?schema=public"` (если используешь Docker-команду выше).
