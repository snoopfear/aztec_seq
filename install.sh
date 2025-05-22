#!/bin/bash

set -euo pipefail

echo "==============================="
echo "     AZTEC NODE INSTALLER"
echo "==============================="

# --- Ввод переменных пользователем ---
read -rp "Введите приватный ключ валидатора: " PRIVATE_KEY
read -rp "Введите адрес coinbase кошелька (например 0x...): " COINBASE_ADDRESS

# --- Проверка и установка Docker ---
if ! command -v docker &> /dev/null; then
  echo "[🔧] Устанавливаем Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  systemctl enable docker
  systemctl start docker
else
  echo "[✓] Docker уже установлен"
fi

# --- Проверка и установка UFW ---
if ! command -v ufw &> /dev/null; then
  echo "[🔧] Устанавливаем UFW..."
  apt update
  apt install ufw -y
fi

echo "[✓] UFW уже установлен"

# --- Добавим путь AZTEC в ~/.bashrc, если нужно ---
PROFILE_FILE="$HOME/.bashrc"
AZTEC_PATH_LINE='export PATH=$PATH:/root/.aztec/bin'

if ! grep -Fxq "$AZTEC_PATH_LINE" "$PROFILE_FILE"; then
  echo "$AZTEC_PATH_LINE" >> "$PROFILE_FILE"
  echo "[✓] Добавлен путь в $PROFILE_FILE"
fi

# --- Загрузка переменных пути (без source может не примениться) ---
export PATH=$PATH:/root/.aztec/bin

# --- Установка AZTEC CLI ---
echo "[⬇️] Устанавливаем AZTEC CLI..."
yes y | bash -i <(curl -s https://install.aztec.network)

# Ждём немного после установки
sleep 10

echo "[⬆️] Запускаем aztec-up alpha-testnet..."
/root/.aztec/bin/aztec-up alpha-testnet

# --- Настройка UFW ---
echo "[🌐] Настраиваем UFW..."
ufw allow ssh
ufw allow 40400/tcp
ufw allow 40400/udp
ufw allow 8080
ufw --force enable
ufw status

# --- Получение публичного IP ---
MY_IP=$(curl -s ifconfig.me)
if [[ -z "$MY_IP" ]]; then
  echo "[⚠️] Не удалось получить публичный IP"
  exit 1
fi

# --- Создание systemd-сервиса ---
cat > /etc/systemd/system/aztec.service <<EOF
[Unit]
Description=Aztec Alpha Testnet Node
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
WorkingDirectory=/root/aztec-node
Environment="PATH=/root/.aztec/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/.aztec/bin/aztec start \\
  --node \\
  --archiver \\
  --sequencer \\
  --network alpha-testnet \\
  --l1-rpc-urls http://65.109.123.206:58545 \\
  --l1-consensus-host-urls http://65.109.123.206:5051 \\
  --sequencer.validatorPrivateKey=$PRIVATE_KEY \\
  --sequencer.coinbase $COINBASE_ADDRESS \\
  --sequencer.governanceProposerPayload 0x54F7fe24E349993b363A5Fa1bccdAe2589D5E5Ef \\
  --p2p.p2pIp $MY_IP \\
  --port 8080 \\
  --admin-port 8880

[Install]
WantedBy=multi-user.target
EOF

# --- Перезапуск systemd и запуск сервиса ---
echo "[🚀] Запускаем aztec.service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable aztec
systemctl restart aztec

# --- Вывод логов ---
echo "==============================="
echo "    ЛОГИ AZTEC НОДЫ (INFO)"
echo "==============================="
journalctl -fu aztec | grep INFO
