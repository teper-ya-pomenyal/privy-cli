# privy-cli — управление стеком Privy Stream одной командой

Bash-скрипт, который после установки на сервер позволяет из любой папки делать:

```sh
sudo privy-cli install           # поставить всё с GitHub: клон + .env + сборка + запуск
sudo privy-cli update            # обновить всё: git pull + пересборка + перезапуск
sudo privy-cli update backend    # только одно приложение (backend | client | admin | all)
sudo privy-cli uninstall admin   # снять приложение
sudo privy-cli start             # запустить всё
sudo privy-cli stop              # остановить всё
sudo privy-cli restart           # перезапустить всё
sudo privy-cli status            # на каких коммитах и что крутится
sudo privy-cli logs backend      # журналы docker compose (можно с сервисом: logs backend gateway)
```

Без указания приложения команда применяется ко всем трём.

## Требования

- Linux с docker и плагином `docker compose` (подойдёт и старый `docker-compose`);
- git (репозитории клонируются и обновляются им);
- для админки — node/npm. Если node стоит через nvm, скрипт сам найдёт его
  даже под sudo, у которого урезанный PATH.

## Установка

### Через .deb (apt)

```sh
git clone https://github.com/teper-ya-pomenyal/privy-cli.git
cd privy-cli
./build-deb.sh                              # нужен только dpkg-deb, он есть в любой Ubuntu
sudo apt install ./privy-cli_*_all.deb
```

Пакет кладёт команду в `/usr/bin/privy-cli`; обновление — собрать новую версию
и повторить `apt install`. Если раньше ставили через `install.sh`, один раз удалите
старую копию, чтобы она не затеняла пакетную: `sudo rm /usr/local/bin/privy-cli`
(PATH ищет в `/usr/local/bin` раньше, чем в `/usr/bin`).

GitHub Actions (`.github/workflows/deb.yml`) собирает `.deb` на каждый тег `v*`
и прикладывает его к release — готовые пакеты можно скачивать со страницы Releases.
Если захочется настоящее `sudo apt install privy-cli` без файла — тот же пакет
загружается в PPA на Launchpad (`ppa:вы/privy`), после чего работает
`sudo add-apt-repository ppa:вы/privy && sudo apt install privy-cli`.

### Автоматом, силами самого cli

Сначала сам cli, если ещё не стоит:

```sh
git clone https://github.com/teper-ya-pomenyal/privy-cli.git
sudo ./privy-cli/install.sh
```

Затем приложения — каждое клонируется с GitHub в `/opt/privy-stream`,
собирается и запускается:

```sh
sudo privy-cli install backend   # клон + .env со случайными паролями + compose up, gateway на :8080
sudo privy-cli install admin     # клон + npm build + контейнер privy-admin на :8082
sudo PRIVY_NODE_URL=https://адрес-узла privy-cli install client   # веб-версия на :8081
```

или всё сразу (`install all`) — клиент остановится с подсказкой, если адрес узла не передан:

```sh
sudo privy-cli install all
```

Что делает `install` для каждого приложения:

- **backend** — клонирует репозиторий, из `.env.example` создаёт `.env`, генерируя
  случайные `POSTGRES_PASSWORD` и `USER_CACHE_PASSWORD`, и поднимает `docker compose`
  (миграции прогоняются сами — это сервисы compose). Домен веб-клиента потом
  впишите в `CORS_ALLOWED_ORIGINS` в `/opt/privy-stream/privy-server/.env`.
- **client** — клонирует репозиторий, создаёт `.env` веб-версии с переданным
  `PRIVY_NODE_URL` (без него установка останавливается с подсказкой — веб-версии
  нужно знать адрес узла), поднимает `docker compose`.
- **admin** — клонирует репозиторий, собирает `dist/` через npm и создаёт контейнер
  `privy-admin`: nginx:alpine, порт `ADMIN_PORT` (8082), конфиг с `try_files` для SPA
  лежит рядом в `privy-admin.nginx.conf`. Если контейнер уже существует — просто рестарт.

Повторный `install` на уже установленном приложении безвреден: он сообщает, что всё
стоит, и напоминает про `update`. Упавшая установка откатывает клон — исправьте
причину и запустите снова.

### Или руками

Если раскладку хотите свою, репозитории можно разложить самому — остальные
команды (update/start/stop/…) работают по тем же правилам:

```sh
sudo mkdir -p /opt/privy-stream && cd /opt/privy-stream
sudo git clone https://github.com/teper-ya-pomenyal/privy-server.git
sudo git clone https://github.com/teper-ya-pomenyal/privy-stream.git
sudo git clone https://github.com/teper-ya-pomenyal/privy-admin.git
```

## Удаление

```sh
sudo privy-cli uninstall backend   # или client | admin | all
```

`uninstall` гасит и удаляет контейнеры приложения и удаляет его каталог
из `/opt/privy-stream`. Данные backend (postgres, треки) при этом **остаются**
в томах `privy-server_*` — команда их полного удаления печатается после выполнения.
Повторный `install` ставит приложение заново с нуля.

## Пути по умолчанию

| Приложение | Каталог |
|---|---|
| `backend` | `/opt/privy-stream/privy-server` |
| `client` | `/opt/privy-stream/privy-stream` |
| `admin` | `/opt/privy-stream/privy-admin` |

`CLIENT_DIR` у клиента — это корень клона репозитория: само приложение с
`docker-compose.yml` лежит внутри него, во вложенной папке `privy-stream`
(скрипт находит её сам).

Если разложили иначе — создайте `/etc/privy-cli.conf`, он перекрывает значения
из скрипта, и править сам скрипт не придётся:

```sh
sudo tee /etc/privy-cli.conf >/dev/null <<'EOF'
BACKEND_DIR=/opt/privy-stream/privy-server
CLIENT_DIR=/opt/privy-stream/privy-stream
ADMIN_DIR=/opt/privy-stream/privy-admin
ADMIN_CONTAINER=privy-admin
ADMIN_PORT=8082

# откуда install клонирует репозитории (для форка достаточно GITHUB_ORG)
#GITHUB_ORG=teper-ya-pomenyal
#BACKEND_REPO=https://github.com/teper-ya-pomenyal/privy-server.git

# необязательно: команда после сборки админки без контейнера
#ADMIN_AFTER_BUILD_CMD=systemctl reload nginx

# если node не виден под sudo и не стоит через nvm:
#PATH=/home/<user>/.nvm/versions/node/vX/bin:$PATH
EOF
```

## Что делает `update` для каждого приложения

| Приложение | Действия |
|---|---|
| `backend` | `git pull --ff-only`, затем `docker compose up -d --build` — пересобирает и поднимает все сервисы, старые образы подчищаются |
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
git -C ~/privy-cli pull
sudo ~/privy-cli/install.sh   # install.sh идемпотентен, просто перезапишите бинарник
```

Если ставили `.deb`-пакетом — обновляйте пакетом: скачайте/соберите новый `.deb`
и `sudo apt install ./privy-cli_*_all.deb` поверх старого.

## Если что-то не так

- **«npm: command not found» под sudo** — node поставлен через nvm, а у root под sudo
  урезанный PATH. Скрипт сам ищет npm в `~/.nvm` пользователя, который вызвал sudo.
  Если не находит — поставьте node системно (`apt install nodejs npm`) или добавьте
  строку `PATH=…` в `/etc/privy-cli.conf` (пример выше).
- **«dubious ownership in repository»** — репозитории принадлежат одному пользователю,
  а скрипт запущен через sudo от root. Лечится один раз на каждый репозиторий:
  ```sh
  sudo git config --global --add safe.directory /opt/privy-stream/privy-server
  sudo git config --global --add safe.directory /opt/privy-stream/privy-stream
  sudo git config --global --add safe.directory /opt/privy-stream/privy-admin
  ```
- **«insufficient permission for adding an object to repository database»** — репозиторий
  обновлялся попеременно то с sudo, то без: часть `.git` принадлежит root, часть вам.
  Выберите один режим: либо всегда запускайте privy-cli с sudo, либо один раз
  верните каталоги себе и запускайте без sudo (docker умеет работать без него,
  если вы в группе `docker`):
  ```sh
  sudo chown -R $USER /opt/privy-stream
  ```
- **Локальные правки на сервере мешают `git pull`** — скрипт тянет только fast-forward,
  чтобы случайно не получить merge-коммит. Если pull упал, разберите локальные изменения
  руками и повторите команду.
- **Старый docker** — скрипт сам использует `docker-compose`, если плагина `docker compose` нет.
- **Поменялось имя папки/репозитория** — достаточно поправить `/etc/privy-cli.conf`.
