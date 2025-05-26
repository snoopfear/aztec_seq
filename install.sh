#!/bin/bash

set -e

echo "==============================="
echo "     AZTEC NODE INSTALLER"
echo "==============================="

echo "Выберите действие:"
echo "1. Установить зависимости и AZTEC CLI"
echo "2. Настроить ноду и запустить"
read -p "Введите 1 или 2: " CHOICE

if [[ "$CHOICE" == "1" ]]; then

  # --- Установка Docker ---
  if ! command -v docker &> /dev/null; then
    echo "[🔧] Устанавливаем Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
  else
    echo "[✓] Docker уже установлен"
  fi

  # --- Установка UFW ---
  if ! command -v ufw &> /dev/null; then
    echo "[🔧] Устанавливаем ufw..."
    apt update
    apt install jq -y
    apt install ufw -y
  else
    echo "[✓] UFW уже установлен"
  fi

  # --- Добавление пути Aztec в bashrc ---
  PROFILE_FILE=~/.bashrc
  if ! grep -q "/root/.aztec/bin" "$PROFILE_FILE"; then
    echo 'export PATH=$PATH:/root/.aztec/bin' >> "$PROFILE_FILE"
    echo "[✓] Добавлен путь /root/.aztec/bin в $PROFILE_FILE"
  fi

  # --- Установка AZTEC CLI ---
  echo "[⬇️] Устанавливаем AZTEC CLI..."
  (yes y | bash <(curl -s https://install.aztec.network))

  echo "[✅] Установка завершена. Перезапустите терминал или выполните:"
  echo "source ~/.bashrc"
  echo "Теперь выполните скрипт снова и выберите пункт 2."

  exit 0
fi

if [[ "$CHOICE" == "2" ]]; then
  # --- Ввод переменных пользователем ---
  read -p "Введите приватный ключ валидатора: " PRIVATE_KEY
  read -p "Введите адрес coinbase кошелька (например 0x...): " COINBASE_ADDRESS

  # --- Проверка доступности aztec-up ---
  if ! command -v aztec-up &> /dev/null; then
    echo "[❌] Команда 'aztec-up' не найдена. Сначала выполните пункт 1."
    exit 1
  fi

  echo "[⬆️] Запускаем aztec-up alpha-testnet..."
  aztec-up alpha-testnet

  # --- Загрузка переменных окружения ---
  source ~/.bashrc

  # --- Настройка firewall ---
  echo "[🌐] Настраиваем UFW..."
  ufw allow ssh
  ufw allow 40400/tcp
  ufw allow 40400/udp
  ufw allow 8080
  ufw --force enable
  ufw status

  # --- Получение IP для p2p ---
  MY_IP=$(curl -4 ifconfig.me)

  # --- Создание systemd unit ---
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

  echo "[🚀] Запускаем aztec.service..."
  mkdir -p /root/aztec-node
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable aztec
  systemctl restart aztec

  echo "==============================="
  echo "    ЛОГИ AZTEC НОДЫ (INFO)"
  echo "journalctl -fu aztec | grep INFO"
  journalctl -fu aztec | grep INFO
else
  echo "Неверный выбор. Введите 1 или 2."
fi
