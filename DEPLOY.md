# Запуск стека Privy Stream на чистом сервере

Пошаговая инструкция: свежая Ubuntu (22.04/24.04) → работающий стек.
Понадобится: доступ по SSH, IP сервера; для TLS — домен(ы) с A-записями на этот IP.

Итог раскладки после инструкции:

| Что | Где | Порт |
|---|---|---|
| gateway (API) | `privy-server` | 8080 |
| веб-клиент | `privy-stream` | 8081 |
| админка | `privy-admin` | 8082 |
| Caddy (TLS, обратный прокси) | системный сервис | 80, 443 |

## 1. Подготовка системы

```sh
sudo apt update && sudo apt -y upgrade

# docker + compose-плагин
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# node/npm — нужны для сборки админки, git — для обновлений
sudo apt install -y nodejs npm git
```

Перезайдите по SSH, чтобы применилась группа docker, и проверьте:

```sh
docker ps && echo "docker ok"
npm -v
```

### Если на сервере мало памяти (примерно до 2 ГБ)

Сборка бэкенда — четыре Go-сервиса параллельно, и на маленькой VPS её убивает
OOM-killer: `failed to execute bake: signal: killed`. Добавьте 2 ГБ подкачки
и повторите установку:

```sh
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 2. Установка privy-cli

```sh
wget https://github.com/teper-ya-pomenyal/privy-cli/releases/download/v1.2.0/privy-cli_1.2.0_all.deb
sudo apt install ./privy-cli_1.2.0_all.deb
privy-cli version
```

Ключи GitHub не нужны — репозитории стека публичные.

## 3. Установка приложений

```sh
sudo privy-cli install backend    # клон + .env со случайными паролями → gateway на :8080
sudo privy-cli install admin      # клон + npm build → админка на :8082
sudo PRIVY_NODE_URL=http://ВАШ_IP:8080 privy-cli install client   # веб-версия на :8081
```

или всё сразу (`sudo privy-cli install all`) — клиент потребует `PRIVY_NODE_URL`.

Проверка:

```sh
privy-cli status        # все три приложения + коммиты
privy-cli logs backend  # журналы, Ctrl+C — выход
```

## 4. Домены и TLS (рекомендуется для продакшена)

Браузер не пускает https-страницу на http-узел, поэтому финально весь трафик
стоит закрыть через TLS. Проще всего — Caddy: сам получает и обновляет сертификаты.

DNS: создайте три A-записи на IP сервера: `api.example.com`, `app.example.com`,
`admin.example.com` (имена, разумеется, свои).

```sh
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

`/etc/caddy/Caddyfile`:

```caddy
api.example.com {
    reverse_proxy 127.0.0.1:8080
}
app.example.com {
    reverse_proxy 127.0.0.1:8081
}
admin.example.com {
    reverse_proxy 127.0.0.1:8082
}
```

```sh
sudo systemctl reload caddy
```

## 5. Перевод стека на домены

```sh
# веб-клиент: адрес узла теперь https
sudo sed -i 's|^PRIVY_NODE_URL=.*|PRIVY_NODE_URL=https://api.example.com|' \
  /opt/privy-stream/privy-stream/privy-stream/.env

# бэкенд: CORS — домены веб-клиента и админки
sudo sed -i 's|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com|' \
  /opt/privy-stream/privy-server/.env

sudo privy-cli update client     # пересоберёт веб-версию с новым адресом узла
sudo privy-cli update backend    # перезапустит gateway с новым CORS
```

Десктопный клиент (Tauri) разрешён всегда, домен ему не нужен.

## 6. Файрвол

```sh
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
```

Нюанс: docker публикует порты в обход ufw, поэтому 8080–8082 формально остаются
доступны снаружи напрямую (мимо TLS). Если это важно — в compose-файлах приложений
публикуйте порты на `127.0.0.1` (например, `"127.0.0.1:8080:8080"`) и перезапустите
`privy-cli update` соответствующего приложения; через Caddy всё продолжит работать.

## 7. Повседневные команды

```sh
sudo privy-cli update             # обновить всё: git pull + пересборка + перезапуск
sudo privy-cli update backend     # только одно приложение
sudo privy-cli start|stop|restart # управление
privy-cli status                  # что крутится и на каких коммитах
sudo privy-cli logs backend       # журналы
sudo privy-cli uninstall all      # снять всё (данные postgres/треков остаются)
```

Без sudo тоже работает, если ваш пользователь в группе `docker` и владеет
каталогами `/opt/privy-stream` — но не смешивайте режимы.

## Обновления

- **Приложения**: `sudo privy-cli update` — тянет изменения из GitHub и перекатывает сервисы.
- **Сам privy-cli**: новый `.deb` из [релизов](https://github.com/teper-ya-pomenyal/privy-cli/releases)
  → `sudo apt install ./privy-cli_X.Y.Z_all.deb` (конфиг `/etc/privy-cli.conf` не трогается).

Если обновление сломало прод — откат одной командой:

```sh
sudo privy-cli rollback            # все приложения к версиям до последнего update
sudo privy-cli rollback backend    # или одно приложение
sudo privy-cli rollback cli        # или сам privy-cli
```

`update` запоминает коммит, на котором всё работало; `rollback` возвращает его,
пересобирает и поднимает. Следующий `update` снова вытянет свежее. Подробности —
в README, раздел «Откат».

## Где что лежит

- Приложения: `/opt/privy-stream/{privy-server, privy-stream, privy-admin}`
- Конфиг утилиты: `/etc/privy-cli.conf` (пути, имя контейнера админки, порт)
- Пароли бэкенда: `/opt/privy-stream/privy-server/.env` (сгенерированы при установке)
- Адрес узла веб-клиента: `/opt/privy-stream/privy-stream/privy-stream/.env`
