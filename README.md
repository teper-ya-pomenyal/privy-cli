# privy-client — управление стеком Privy Stream одной командой

Bash-скрипт, который после установки на сервер позволяет из любой папки делать:

```sh
sudo privy-client update            # обновить все три приложения: git pull + пересборка + перезапуск
sudo privy-client update backend    # только одно приложение (backend | client | admin | all)
sudo privy-client start             # запустить всё
sudo privy-client stop              # остановить всё
sudo privy-client restart           # перезапустить всё
sudo privy-client status            # на каких коммитах и что крутится
sudo privy-client logs backend      # журналы docker compose (можно с сервисом: logs backend gateway)
```

Без указания приложения команда применяется ко всем трём.

## Требования

- Linux с docker и плагином `docker compose` (подойдёт и старый `docker-compose`);
- git (репозитории обновляются `git pull --ff-only`);
- для админки — node/npm. Если node стоит через nvm, скрипт сам найдёт его
  даже под sudo, у которого урезанный PATH.

## Установка

Скрипт по умолчанию ждёт стандартную раскладку — все репозитории стека
в `/opt/privy-stream`:

```sh
sudo mkdir -p /opt/privy-stream && cd /opt/privy-stream
sudo git clone https://github.com/teper-ya-pomenyal/privy_stream.git
sudo git clone https://github.com/teper-ya-pomenyal/privy_stream_client.git
sudo git clone https://github.com/teper-ya-pomenyal/privy_stream_admin.git

git clone https://github.com/teper-ya-pomenyal/privy-client.git
sudo ./privy-client/install.sh
```

`install.sh` просто копирует скрипт в `/usr/local/bin` с правами на запуск —
после этого команда доступна из любой папки.

## Пути по умолчанию

| Приложение | Каталог |
|---|---|
| `backend` | `/opt/privy-stream/privy_stream` |
| `client` | `/opt/privy-stream/privy_stream_client/privy-stream` |
| `admin` | `/opt/privy-stream/privy_stream_admin` |

У клиента путь глубже, потому что `docker-compose.yml` лежит во вложенной папке
`privy-stream` репозитория клиента.

Если разложили иначе — создайте `/etc/privy-client.conf`, он перекрывает значения
из скрипта, и править сам скрипт не придётся:

```sh
sudo tee /etc/privy-client.conf >/dev/null <<'EOF'
BACKEND_DIR=/opt/privy-stream/privy_stream
CLIENT_DIR=/opt/privy-stream/privy_stream_client/privy-stream
ADMIN_DIR=/opt/privy-stream/privy_stream_admin
ADMIN_CONTAINER=privy-admin

# необязательно: команда после сборки админки без контейнера
#ADMIN_AFTER_BUILD_CMD=systemctl reload nginx

# если node не виден под sudo и не стоит через nvm:
#PATH=/home/<user>/.nvm/versions/node/vX/bin:$PATH
EOF
```

## Что делает `update` для каждого приложения

| Приложение | Действия |
|---|---|
| `backend` | `git pull --ff-only`, затем `docker compose up -d --build` — пересобирает и поднимает все сервисы, миграции прогоняются сами (это сервисы compose), старые образы подчищаются |
| `client` | `git pull --ff-only`, затем `docker compose up -d --build` (nginx + статика) |
| `admin` | `git pull --ff-only`, затем `npm ci && npm run build` |

Для админки скрипт сам определяет режим по тому, что есть на сервере:

- есть `docker-compose.yml` в папке — управление через compose;
- есть контейнер `privy-admin` (имя настраивается в конфиге) — после сборки
  делается `docker restart`, а `start`/`stop`/`restart`/`logs` управляют контейнером;
- нет ни того ни другого — админка считается статикой: сборка просто обновляет
  `dist/`, который отдаёт ваш веб-сервер (nginx/Caddy).

Если сборка упала или `git pull` не смог сделать fast-forward, перезапуск сервисов
не выполняется — не задеплоится сломанное.

## Обновление самого cli

```sh
git -C ~/privy-client pull
sudo ~/privy-client/install.sh   # install.sh идемпотентен, просто перезапишите бинарник
```

## Если что-то не так

- **«npm: command not found» под sudo** — node поставлен через nvm, а у root под sudo
  урезанный PATH. Скрипт сам ищет npm в `~/.nvm` пользователя, который вызвал sudo.
  Если не находит — поставьте node системно (`apt install nodejs npm`) или добавьте
  строку `PATH=…` в `/etc/privy-client.conf` (пример выше).
- **«dubious ownership in repository»** — репозитории принадлежат одному пользователю,
  а скрипт запущен через sudo от root. Лечится один раз на каждый репозиторий:
  ```sh
  sudo git config --global --add safe.directory /opt/privy-stream/privy_stream
  sudo git config --global --add safe.directory /opt/privy-stream/privy_stream_client/privy-stream
  sudo git config --global --add safe.directory /opt/privy-stream/privy_stream_admin
  ```
- **Локальные правки на сервере мешают `git pull`** — скрипт тянет только fast-forward,
  чтобы случайно не получить merge-коммит. Если pull упал, разберите локальные изменения
  руками и повторите команду.
- **Старый docker** — скрипт сам использует `docker-compose`, если плагина `docker compose` нет.
- **Поменялось имя папки/репозитория** — достаточно поправить `/etc/privy-client.conf`.
