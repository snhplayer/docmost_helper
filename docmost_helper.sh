#!/bin/bash

# Цвета для красивого вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для получения приглашения
get_invite() {
    clear
    echo -e "${BLUE}=== Получение ссылки на приглашение ===${NC}\n"
    
    # Проверка количества аргументов
    if [[ $# -ne 2 ]]; then
        echo -e "${RED}Использование: $0 <ваш сайт> <username>${NC}"
        echo -e "${YELLOW}Пример: $0 https://yoursite.com foo@bar.com${NC}"
        return 1
    fi

    # Проверка контейнера
    if ! docker ps --filter "name=docmost-db-1" --format "{{.Names}}" | grep -q "docmost-db-1"; then
        echo -e "${RED}Ошибка: контейнер 'docmost-db-1' не запущен.${NC}"
        echo -e "${YELLOW}Убедитесь, что приложение 'docmost' настроено и работает.${NC}"
        return 1
    fi

    # Получение токена
    token=$(docker exec -it docmost-db-1 psql -U docmost -c 'select email,token from workspace_invitations;' 2>/dev/null | grep "${2}" | awk -F'|' '{print $2}' | sed 's/ //g;s/\r//g;s/\$//g')

    # Получение id_key
    id_key=$(docker exec -it docmost-db-1 psql -U docmost -c 'select email,id from workspace_invitations;' 2>/dev/null | grep "${2}" | awk -F'|' '{print $2}' | sed 's/ //g;s/\r//g;s/\$//g')

    # Проверка токена
    if [[ -z ${token} ]]; then
        echo -e "${RED}Ошибка: токен для пользователя '${2}' не найден.${NC}"
        echo -e "${YELLOW}Убедитесь, что пользователь существует в таблице 'workspace_invitations'.${NC}"
        return 1
    fi

    # Проверка id_key
    if [[ -z ${id_key} ]]; then
        echo -e "${RED}Ошибка: ID для пользователя '${2}' не найден.${NC}"
        echo -e "${YELLOW}Убедитесь, что пользователь существует в таблице 'workspace_invitations'.${NC}"
        return 1
    fi

    # Вывод ссылки
    echo -e "${GREEN}Ссылка на приглашение:${NC} ${1}/invites/${id_key}?token=${token}"
}

# Функция удаления пользователя
delete_user() {
    clear
    echo -e "${BLUE}=== Удаление пользователя ===${NC}\n"
    
    DB_USER="docmost"
    DB_NAME="docmost"
    DB_CONTAINER="docmost-db-1"

    # Проверка аргумента email
    if [ -z "$1" ]; then
        echo -e "${RED}Ошибка: Укажите email пользователя для удаления!${NC}"
        echo -e "${YELLOW}Пример: user@example.com${NC}"
        return 1
    fi
    EMAIL="$1"

    echo -e "${BLUE}Поиск ID пользователя с email: $EMAIL ...${NC}"

    # Получение ID пользователя
    USER_ID=$(docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -A -c "SELECT id FROM users WHERE email = '$EMAIL';")

    if [ -z "$USER_ID" ]; then
        echo -e "${RED}Ошибка: Пользователь с email '$EMAIL' не найден!${NC}"
        return 1
    fi

    echo -e "${GREEN}ID пользователя: $USER_ID${NC}"

    # Проверка связанных данных
    echo -e "${BLUE}🔍 Проверка связанных данных ...${NC}"
    RELATED_DATA=$(docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -A -c "
    SELECT 'groups' AS table_name, id FROM groups WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'spaces', id FROM spaces WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'pages', id FROM pages WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'pages_last_updated', id FROM pages WHERE last_updated_by_id = '$USER_ID'
    UNION ALL
    SELECT 'pages_deleted', id FROM pages WHERE deleted_by_id = '$USER_ID'
    UNION ALL
    SELECT 'workspace_invitations', id FROM workspace_invitations WHERE invited_by_id = '$USER_ID';
    ")

    if [ -n "$RELATED_DATA" ]; then
        echo -e "${YELLOW}Внимание: Найдены связанные данные!${NC}"
        echo "$RELATED_DATA"
    else
        echo -e "${GREEN}Связанные данные не найдены.${NC}"
    fi

    # Обновление ссылок на NULL
    echo -e "${BLUE}Обновление ссылок на NULL ...${NC}"
    docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    UPDATE groups SET creator_id = NULL WHERE creator_id = '$USER_ID';
    UPDATE spaces SET creator_id = NULL WHERE creator_id = '$USER_ID';
    UPDATE pages SET creator_id = NULL WHERE creator_id = '$USER_ID';
    UPDATE pages SET last_updated_by_id = NULL WHERE last_updated_by_id = '$USER_ID';
    UPDATE pages SET deleted_by_id = NULL WHERE deleted_by_id = '$USER_ID';
    UPDATE workspace_invitations SET invited_by_id = NULL WHERE invited_by_id = '$USER_ID';
    "

    # Удаление пользователя
    echo -e "${BLUE}Удаление пользователя с ID: $USER_ID ...${NC}"
    docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c "DELETE FROM users WHERE id = '$USER_ID';"

    # Финальная проверка
    echo -e "${BLUE}Финальная проверка после удаления ...${NC}"
    REMAINING_DATA=$(docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -t -A -c "
    SELECT 'groups' AS table_name, id FROM groups WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'spaces', id FROM spaces WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'pages', id FROM pages WHERE creator_id = '$USER_ID'
    UNION ALL
    SELECT 'pages_last_updated', id FROM pages WHERE last_updated_by_id = '$USER_ID'
    UNION ALL
    SELECT 'pages_deleted', id FROM pages WHERE deleted_by_id = '$USER_ID'
    UNION ALL
    SELECT 'workspace_invitations', id FROM workspace_invitations WHERE invited_by_id = '$USER_ID';
    ")

    if [ -n "$REMAINING_DATA" ]; then
        echo -e "${YELLOW}Внимание: Некоторые связанные данные остались после удаления!${NC}"
        echo "$REMAINING_DATA"
    else
        echo -e "${GREEN}Пользователь успешно удалён!${NC}"
    fi
}

# Функция установки
install_docmost() {
    clear
    echo -e "${BLUE}=== Установка Docmost ===${NC}\n"

    # Шаг 1: Установка Docker
    echo -e "${BLUE}Установка Docker...${NC}"
    sudo apt-get update -qqy
    sudo apt-get install ca-certificates curl -qqy
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qqy
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -qqy

    # Шаг 2: Создание директории и загрузка docker-compose.yml
    echo -e "${BLUE}Настройка docmost...${NC}"
    mkdir -p docmost
    cd docmost || { echo -e "${RED}Ошибка: не удалось войти в директорию docmost${NC}"; return 1; }
    curl -O https://raw.githubusercontent.com/docmost/docmost/main/docker-compose.yml

    # Проверка наличия файла
    if [ ! -f docker-compose.yml ]; then
        echo -e "${RED}Ошибка: docker-compose.yml не найден!${NC}"
        return 1
    fi

    # Генерация APP_SECRET
    APP_SECRET=$(openssl rand -hex 32)

    # Запрос домена
    echo -e "${YELLOW}Введите ваш домен (например, https://example.com) [Enter для http://localhost:3000]:${NC}"
    read APP_URL
    APP_URL=${APP_URL:-http://localhost:3000}

    if [[ -z "$APP_URL" ]]; then
        echo -e "${GREEN}Используется домен по умолчанию: $APP_URL${NC}"
    else
        if ! [[ "$APP_URL" =~ ^https?://.* ]]; then
            echo -e "${YELLOW}Предупреждение: Домен должен начинаться с 'http://' или 'https://'. Используется '$APP_URL' как указано.${NC}"
        fi
    fi

    # Запрос пароля для PostgreSQL
    while true; do
        echo -e "${YELLOW}Введите надёжный пароль для PostgreSQL (только a-zA-Z0-9):${NC}"
        read POSTGRES_PASSWORD
        if [[ "$POSTGRES_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
            break
        else
            echo -e "${RED}Ошибка: Пароль должен содержать только буквенно-цифровые символы (a-zA-Z0-9).${NC}"
        fi
    done

    # Обновление docker-compose.yml
    sed -i "s|APP_URL=.*|APP_URL=$APP_URL|" docker-compose.yml
    sed -i "s|APP_SECRET:.*|APP_SECRET: \"$APP_SECRET\"|" docker-compose.yml
    sed -i "s|STRONG_DB_PASSWORD|$POSTGRES_PASSWORD|g" docker-compose.yml

    # Запуск приложения
    echo -e "${BLUE}Запуск docmost...${NC}"
    docker compose up -d
    echo -e "${GREEN}Docmost успешно установлен! Логи можно посмотреть командой: docker compose logs -f${NC}"
}

# Главное меню
while true; do
    clear
    echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Docmost Управление              ║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${GREEN} [1] Получить ссылку на приглашение ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN} [2] Удалить пользователя           ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN} [3] Установить Docmost             ${BLUE}║${NC}"
    echo -e "${BLUE}║${RED} [4] Выход                          ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
    echo -e "\n${YELLOW}Выберите опцию:${NC} "
    read -p "" choice

    case $choice in
        1)
            echo -e "\n${YELLOW}Введите URL сайта (например, https://yoursite.com):${NC}"
            read site_url
            echo -e "${YELLOW}Введите email пользователя:${NC}"
            read username
            get_invite "$site_url" "$username"
            echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
            read
            ;;
        2)
            echo -e "\n${YELLOW}Введите email пользователя для удаления:${NC}"
            read email
            delete_user "$email"
            echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
            read
            ;;
        3)
            install_docmost
            echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
            read
            ;;
        4)
            echo -e "${GREEN}До свидания!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор! Попробуйте снова.${NC}"
            sleep 2
            ;;
    esac
done
