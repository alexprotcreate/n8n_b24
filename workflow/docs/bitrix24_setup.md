# Настройка Bitrix24 для Call Analysis Workflow

## 1. Создание Входящего Webhook (для API запросов)

1. Перейдите в **Приложения → Разработчикам → Другое → Входящий вебхук**
2. Нажмите **Добавить вебхук**
3. Выберите права:
   - `crm` - работа с CRM
   - `crm.timeline` - работа с таймлайном
   - `disk` - доступ к файлам (для скачивания записей звонков)
4. Скопируйте URL вебхука (формат: `https://your-portal.bitrix24.ru/rest/1/xxxxxx/`)

## 2. Настройка Исходящего Webhook (для отправки событий в n8n)

1. В n8n активируйте workflow → скопируйте **Production Webhook URL**
   - Формат: `https://your-n8n.com/webhook/call-bitrix-incoming`
2. Bitrix24 → **Настройки → Настройки телефонии → Интеграции**
3. Или через REST API создайте обработчик события:

```bash
curl -X POST 'https://your-portal.bitrix24.ru/rest/1/xxxxxx/event.bind' \
  -d 'event=ONVOXIMPLANTCALLEND' \
  -d 'handler=https://your-n8n.com/webhook/call-bitrix-incoming' \
  -d 'event_type=online'
```

**Альтернативный способ** (если нет доступа к настройкам телефонии):
- Используйте сторонний сервис для webhook (например, Zapier, Make.com)
- Или настройте через администратора Bitrix24

## 3. Создание пользовательских полей

### Поле: Оценка звонка (UF_CRM_CALL_SCORE)

**Для лидов:**
1. CRM → Настройки → Настройки форм и отчётов → Пользовательские поля
2. Выберите **Лид**
3. Добавить поле:
   - Тип: **Число**
   - Название: `Оценка звонка`
   - Символьный код: `UF_CRM_CALL_SCORE`
   - Обязательное: Нет
   - Показывать в фильтре: Да
   - Показывать в списке: Да

**Для сделок:**
Повторите те же шаги для сущности **Сделка**.

### Поле: Тип клиента (UF_CRM_CLIENT_TYPE)

**Для лидов:**
1. Добавить поле:
   - Тип: **Строка**
   - Название: `Тип клиента`
   - Символьный код: `UF_CRM_CLIENT_TYPE`
   - Обязательное: Нет
   - Показывать в фильтре: Да
   - Показывать в списке: Да

**Для сделок:**
Повторите те же шаги для сущности **Сделка**.

## 4. Формат webhook от Bitrix24

Когда звонок завершается, Bitrix24 отправляет POST запрос на ваш URL:

```json
{
  "event": "ONVOXIMPLANTCALLEND",
  "data": {
    "CALL_ID": "call.12345.67890",
    "CRM_ENTITY_TYPE": "LEAD",
    "CRM_ENTITY_ID": "123",
    "RECORD_FILE_ID": "789",
    "DURATION": 120,
    "PHONE_NUMBER": "+79001234567"
  },
  "ts": "1234567890",
  "auth": {
    "domain": "your-portal.bitrix24.ru"
  }
}
```

## 5. Настройка в n8n

### HTTP Query Auth Credential

1. Settings → Credentials → Add Credential
2. Тип: **HTTP Query Auth**
3. Настройки:
   - Name: `bitrix24Webhook`
   - Value: `https://your-portal.bitrix24.ru/rest/1/xxxxxx/`

### Использование в нодах

В HTTP Request нодах для Bitrix24:
- Authentication: Predefined Credential Type
- Credential Type: HTTP Query Auth
- Credential: выберите созданный credential

URL формируется как:
```
={{ $credentials.bitrix24Webhook }}crm.lead.update
```

## 6. API методы

### Обновление полей лида
```json
POST crm.lead.update
{
  "id": 123,
  "fields": {
    "UF_CRM_CALL_SCORE": 85,
    "UF_CRM_CLIENT_TYPE": "горячий"
  }
}
```

### Обновление полей сделки
```json
POST crm.deal.update
{
  "id": 456,
  "fields": {
    "UF_CRM_CALL_SCORE": 72,
    "UF_CRM_CLIENT_TYPE": "тёплый"
  }
}
```

### Добавление комментария
```json
POST crm.timeline.comment.add
{
  "fields": {
    "ENTITY_ID": 123,
    "ENTITY_TYPE": "lead",
    "COMMENT": "Текст комментария..."
  }
}
```

## 7. Проверка работы

1. Создайте тестовый лид в Bitrix24
2. Добавьте запись в Supabase с `lead_id` этого лида
3. Запустите workflow
4. Проверьте:
   - Поля лида обновились
   - В таймлайне появились комментарии

## 8. Troubleshooting

### Webhook не приходит
- Проверьте URL webhook в настройках Bitrix24
- Убедитесь, что workflow активирован в n8n
- Проверьте логи webhook в n8n (Executions)

### Ошибка при скачивании записи
- Проверьте права входящего webhook на `disk`
- Убедитесь, что запись звонка существует

## 9. Старые проблемы

### Ошибка 403 Forbidden
- Проверьте права вебхука
- Убедитесь, что URL вебхука правильный

### Поля не обновляются
- Проверьте символьные коды полей
- Убедитесь, что поля созданы для нужной сущности (лид/сделка)

### Комментарии не добавляются
- Проверьте права на `crm.timeline`
- Убедитесь, что `ENTITY_TYPE` правильный

## 10. Получение символьных кодов полей

Если поля уже созданы, получите их коды через API:

```
GET crm.lead.userfield.list
```

Ответ покажет все пользовательские поля с их кодами.
