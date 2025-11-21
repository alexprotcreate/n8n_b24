# n8n Bitrix24 Call Transcription & AI Analysis Workflow

Автоматическая транскрибация и AI-анализ звонков из Bitrix24 с использованием AssemblyAI, OpenAI GPT-4 и Supabase.

## Быстрый старт (5 минут)

### 1. Импорт workflow в n8n

1. Откройте n8n (локально или cloud)
2. Нажмите **Import from File**
3. Выберите файл `workflow.json`
4. Workflow появится в вашем списке

### 2. Настройка Credentials

Настройте следующие credentials в n8n:

#### AssemblyAI API
1. В n8n: **Settings → Credentials → New**
2. Выберите **HTTP Header Auth**
3. Название: `AssemblyAI API`
4. Header Name: `Authorization`
5. Header Value: ваш API ключ AssemblyAI (получить на https://www.assemblyai.com/)

#### OpenAI API
1. **Settings → Credentials → New**
2. Выберите **OpenAI API**
3. Название: `OpenAI API`
4. API Key: ваш ключ OpenAI (получить на https://platform.openai.com/api-keys)

#### Supabase API
1. **Settings → Credentials → New**
2. Выберите **Supabase API**
3. Название: `Supabase API`
4. Host: `https://YOUR_PROJECT.supabase.co`
5. Service Role Secret: ваш service_role key из Supabase Dashboard

#### Bitrix24 API
1. **Settings → Credentials → New**
2. Создайте Generic Credential для Bitrix24
3. Сохраните ваш Bitrix24 domain и access token

#### Bitrix24 Recording Auth (опционально)
Если записи звонков защищены Basic Auth:
1. **Settings → Credentials → New**
2. Выберите **HTTP Basic Auth**
3. Username и Password для доступа к записям

### 3. Получить Webhook URL в n8n

1. Откройте workflow в редакторе
2. Кликните на ноду **Webhook Bitrix24** (первая нода)
3. Нажмите **Execute Node** или **Test**
4. Скопируйте **Webhook URL**, он будет выглядеть так:
   ```
   https://your-n8n-instance.com/webhook/call-bitrix-incoming
   ```

### 4. Создать Webhook в Bitrix24

#### Вариант А: Через REST API (рекомендуется)

Выполните POST запрос:
```bash
curl -X POST "https://YOUR_DOMAIN.bitrix24.ru/rest/YOUR_USER_ID/YOUR_ACCESS_TOKEN/event.bind" \
  -d "event=ONVOXIMPLANTCALLEND" \
  -d "handler=https://your-n8n-instance.com/webhook/call-bitrix-incoming"
```

#### Вариант Б: Через интерфейс Bitrix24

1. Откройте **Настройки → Разработчикам → Вебхуки**
2. Создайте **Входящий вебхук**
3. Выберите права: `telephony` (минимум)
4. Настройте обработчик события `ONVOXIMPLANTCALLEND`
5. URL обработчика: ваш webhook URL из n8n

### 5. Настроить Supabase Tables

Создайте две таблицы в Supabase:

#### Таблица `call_transcriptions`
```sql
CREATE TABLE call_transcriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  call_id TEXT NOT NULL,
  phone_number TEXT,
  call_duration INTEGER,
  call_type TEXT,
  recording_url TEXT,
  transcript TEXT,
  transcript_id TEXT,
  sentiment JSONB,
  ai_analysis JSONB,
  crm_entity_type TEXT,
  crm_entity_id TEXT,
  portal_user_id TEXT,
  processed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_call_id ON call_transcriptions(call_id);
CREATE INDEX idx_crm_entity ON call_transcriptions(crm_entity_type, crm_entity_id);
```

#### Таблица `error_logs`
```sql
CREATE TABLE error_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  call_id TEXT,
  error_message TEXT,
  error_node TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_error_call_id ON error_logs(call_id);
```

### 6. Активировать Workflow

1. Откройте workflow в n8n
2. Нажмите переключатель **Active** в правом верхнем углу
3. Workflow готов к работе!

## Архитектура Workflow

```
┌─────────────────┐
│ Webhook Bitrix24│ ← Событие ONVOXIMPLANTCALLEND от Bitrix24
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Parse Data      │ ← Извлечение call_id, recording_url, и др.
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Check Recording │ ← Проверка наличия записи (>5 сек)
└────┬───────┬────┘
     │       │ NO
     │       └──→ [Skip Response]
     │ YES
     ▼
┌─────────────────┐
│ Download Audio  │ ← Скачивание MP3/WAV файла
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Upload to       │ ← Загрузка в AssemblyAI
│ AssemblyAI      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Start           │ ← Запуск транскрибации (RU, sentiment)
│ Transcription   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Wait (10s loop) │ ← Ожидание завершения
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Check Status    │ ← Проверка статуса
└────┬───────┬────┘
     │       │ processing
     │       └──→ [Continue Waiting]
     │ completed
     ▼
┌─────────────────┐
│ Analyze with    │ ← AI-анализ через GPT-4
│ ChatGPT         │   (summary, sentiment, action items)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Prepare Final   │ ← Объединение всех данных
│ Data            │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Save to         │ ← Сохранение в Supabase
│ Supabase        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Update Bitrix24 │ ← Обновление CRM (lead/deal)
│ CRM             │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Send            │ ← Уведомление менеджеру
│ Notification    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Success Response│ ← Ответ webhook
└─────────────────┘

[Error Handler] → Log to Supabase → Error Response
```

## Структура данных

### Входящий Webhook (от Bitrix24)

Bitrix24 отправляет событие `ONVOXIMPLANTCALLEND` со следующей структурой:

```json
{
  "event": "ONVOXIMPLANTCALLEND",
  "data": {
    "CALL_ID": "12345678",
    "RECORD_URL": "https://domain.bitrix24.ru/disk/downloadFile/...",
    "CALL_DURATION": "180",
    "PHONE_NUMBER": "+79991234567",
    "PORTAL_USER_ID": "1",
    "CRM_ENTITY_TYPE": "LEAD",
    "CRM_ENTITY_ID": "42",
    "CALL_TYPE": "1",
    "CALL_START_DATE": "2025-01-15 14:30:00",
    "PORTAL_NUMBER": "+74951234567",
    "CRM_ACTIVITY_ID": "567"
  },
  "auth": {
    "domain": "your-domain.bitrix24.ru",
    "member_id": "..."
  }
}
```

#### Описание полей:

| Поле | Тип | Описание |
|------|-----|----------|
| `CALL_ID` | string | Уникальный ID звонка в Bitrix24 |
| `RECORD_URL` | string | Прямая ссылка на аудиозапись (.mp3) |
| `CALL_DURATION` | integer | Длительность звонка в секундах |
| `PHONE_NUMBER` | string | Номер телефона клиента |
| `PORTAL_USER_ID` | integer | ID сотрудника в Bitrix24 |
| `CRM_ENTITY_TYPE` | string | Тип CRM-сущности: `LEAD`, `DEAL`, `CONTACT`, `COMPANY` |
| `CRM_ENTITY_ID` | integer | ID сущности в CRM |
| `CALL_TYPE` | string | `1` - входящий, `2` - исходящий, `3` - входящий с перенаправлением, `4` - обратный звонок |
| `CALL_START_DATE` | datetime | Дата и время начала звонка |
| `PORTAL_NUMBER` | string | Номер вашей компании |
| `CRM_ACTIVITY_ID` | integer | ID активности (звонка) в CRM |

### Результат AI-анализа (ChatGPT)

GPT-4 возвращает JSON со структурой:

```json
{
  "summary": "Клиент интересовался тарифами на корпоративное обслуживание. Менеджер предложил пакет Premium, клиент запросил коммерческое предложение.",
  "key_topics": [
    "Корпоративные тарифы",
    "Пакет Premium",
    "Коммерческое предложение",
    "Срок действия скидки"
  ],
  "sentiment": "positive",
  "client_needs": [
    "Корпоративное обслуживание на 50 человек",
    "Скидка для постоянных клиентов",
    "КП с детализацией услуг"
  ],
  "action_items": [
    "Отправить КП на email до 17:00",
    "Уточнить список дополнительных услуг",
    "Запланировать встречу на следующую неделю"
  ],
  "call_quality_score": 8,
  "recommendations": [
    "Сократить время ожидания ответа на вопросы",
    "Более четко озвучивать условия скидок",
    "Предложить демо-версию сервиса"
  ]
}
```

### Данные в Supabase

#### Таблица `call_transcriptions`

```json
{
  "id": "uuid",
  "call_id": "12345678",
  "phone_number": "+79991234567",
  "call_duration": 180,
  "call_type": "1",
  "recording_url": "https://...",
  "transcript": "Полный текст транскрипции...",
  "transcript_id": "assemblyai_id",
  "sentiment": {
    "overall": "POSITIVE",
    "results": [...]
  },
  "ai_analysis": {
    "summary": "...",
    "key_topics": [...],
    "sentiment": "positive",
    "client_needs": [...],
    "action_items": [...],
    "call_quality_score": 8,
    "recommendations": [...]
  },
  "crm_entity_type": "LEAD",
  "crm_entity_id": "42",
  "portal_user_id": "1",
  "processed_at": "2025-01-15T14:35:22Z",
  "created_at": "2025-01-15T14:35:22Z"
}
```

## Настройка пользовательских полей в Bitrix24

Для сохранения результатов анализа в CRM создайте пользовательские поля:

1. Откройте **CRM → Настройки → Настройка → Пользовательские поля**
2. Создайте следующие поля для Lead/Deal:

| Название поля | Код поля | Тип |
|---------------|----------|-----|
| Транскрипт звонка | `UF_CRM_CALL_TRANSCRIPT` | Текст (множественный) |
| Краткое содержание | `UF_CRM_CALL_SUMMARY` | Текст |
| Настроение клиента | `UF_CRM_CALL_SENTIMENT` | Список (positive/neutral/negative) |
| Качество звонка | `UF_CRM_CALL_QUALITY` | Число |

## Troubleshooting

### Webhook не срабатывает

**Проблема:** Bitrix24 не отправляет события в n8n

**Решения:**
1. Проверьте, что workflow **активен** (зеленый переключатель)
2. Убедитесь, что webhook URL доступен извне (для локального n8n используйте ngrok)
3. Проверьте права вебхука в Bitrix24: должно быть включено `telephony`
4. Проверьте логи событий в Bitrix24: **Приложения → Журнал событий**
5. Убедитесь, что событие `ONVOXIMPLANTCALLEND` зарегистрировано:
   ```bash
   curl "https://YOUR_DOMAIN.bitrix24.ru/rest/YOUR_USER_ID/YOUR_TOKEN/event.get"
   ```

### AssemblyAI возвращает ошибку

**Проблема:** Ошибка при загрузке или транскрибации

**Решения:**
1. Проверьте баланс аккаунта AssemblyAI
2. Убедитесь, что API ключ корректный в credentials
3. Проверьте формат аудиофайла (поддерживаются: mp3, wav, flac, m4a)
4. Убедитесь, что файл записи доступен (URL не истек)
5. Для защищенных записей настройте Basic Auth credentials

### Транскрипция застряла в статусе "processing"

**Проблема:** Нода "Wait" работает бесконечно

**Решения:**
1. Увеличьте время ожидания в ноде "Wait for Transcription" (по умолчанию 10 сек)
2. Для длинных звонков (>10 мин) установите интервал 20-30 сек
3. Проверьте статус вручную через API:
   ```bash
   curl "https://api.assemblyai.com/v2/transcript/{transcript_id}" \
     -H "Authorization: YOUR_API_KEY"
   ```
4. Проверьте, что у вас нет лимита на одновременные транскрибации в AssemblyAI

### ChatGPT не возвращает структурированный JSON

**Проблема:** AI-анализ возвращает текст вместо JSON

**Решения:**
1. Убедитесь, что используется модель `gpt-4o` или `gpt-4-turbo`
2. Проверьте temperature (должен быть 0.3 для более детерминированных ответов)
3. Уточните system prompt, добавив: "Верни ТОЛЬКО валидный JSON, без markdown форматирования"
4. Добавьте ноду "Parse JSON" после ChatGPT для валидации

### Supabase возвращает ошибку 401

**Проблема:** Нет доступа к Supabase

**Решения:**
1. Проверьте, что используется **service_role** ключ, а не anon key
2. Убедитесь, что RLS (Row Level Security) отключен для таблиц или настроены правильные policies
3. Проверьте URL проекта: должен быть `https://PROJECT_ID.supabase.co`
4. Проверьте, что таблицы созданы (см. раздел "Настроить Supabase Tables")

### Bitrix24 CRM не обновляется

**Проблема:** Данные не попадают в Lead/Deal

**Решения:**
1. Проверьте, что пользовательские поля созданы (см. "Настройка пользовательских полей")
2. Убедитесь, что коды полей совпадают: `UF_CRM_CALL_TRANSCRIPT`, `UF_CRM_CALL_SUMMARY`, и т.д.
3. Проверьте права доступа для вебхука: должно быть `crm` (write)
4. Проверьте, что `CRM_ENTITY_ID` и `CRM_ENTITY_TYPE` корректны
5. Для отладки выведите лог запроса в n8n (Enable Debug Mode)

### Ошибка "No recording available or call too short"

**Проблема:** Звонок пропускается

**Объяснение:** Это нормальное поведение. Workflow пропускает звонки:
- Без записи (`RECORD_URL` пустой)
- Короче 5 секунд

**Решения:**
1. Если нужно обрабатывать короткие звонки, измените условие в ноде "Check Recording Exists" (строка с `call_duration > 5`)
2. Убедитесь, что запись звонков включена в Bitrix24: **Настройки → Телефония → Запись разговоров**

### Высокая стоимость API

**Проблема:** Большие расходы на AssemblyAI и OpenAI

**Решения:**
1. **AssemblyAI:** Отключите ненужные features в "Start Transcription":
   - `sentiment_analysis: false` (если не нужен sentiment)
   - `auto_highlights: false`
   - `entity_detection: false`
2. **OpenAI:** Используйте более дешевую модель:
   - `gpt-4o-mini` вместо `gpt-4o` (в 15 раз дешевле)
   - Уменьшите `maxTokens` до 1000-1500
3. Добавьте фильтр по типу звонков (обрабатывать только входящие)
4. Пропускайте звонки короче 30 секунд

## Расширения и доработки

### 1. Добавить Email-уведомления

Добавьте ноду **Send Email** после "Prepare Final Data":

```
→ Prepare Final Data
  → Send Email (Gmail/SMTP)
    To: manager@company.com
    Subject: "Анализ звонка {{ $json.call_id }}"
    Body: {{ $json.ai_analysis.summary }}
```

### 2. Интеграция с Telegram

Добавьте ноду **Telegram** для отправки уведомлений:

```
→ Prepare Final Data
  → Telegram (Send Message)
    Chat ID: your_chat_id
    Text: "Новый звонок от {{ $json.phone_number }}\nОценка: {{ $json.ai_analysis.call_quality_score }}/10"
```

### 3. Автоматическое создание задач в Bitrix24

На основе action_items создавайте задачи:

```
→ Prepare Final Data
  → Split In Batches (action_items)
    → HTTP Request: crm.task.add
      Fields: {
        TITLE: {{ $json.action_item }},
        RESPONSIBLE_ID: {{ $json.portal_user_id }},
        DEADLINE: {{ $now.plus({days: 1}).toISO() }}
      }
```

### 4. Dashboard в Grafana/Metabase

Используйте Supabase как источник данных для визуализации:
- Средняя оценка качества звонков
- Топ-5 тем разговоров
- Sentiment distribution
- Количество звонков по менеджерам

### 5. Мультиязычная поддержка

Измените `language_code` в "Start Transcription":
```json
{
  "language_code": "auto",  // автоопределение
  // или конкретный язык: en, es, fr, de...
}
```

## Безопасность

### Рекомендации:

1. **Используйте HTTPS** для webhook URL
2. **Не храните credentials в hardcode** - используйте n8n Credentials Manager
3. **Настройте IP whitelist** в Bitrix24 (если возможно)
4. **Включите Rate Limiting** в n8n (Settings → Rate Limit)
5. **Регулярно ротируйте API ключи** (AssemblyAI, OpenAI)
6. **Настройте RLS в Supabase** для ограничения доступа к данным
7. **Логируйте все ошибки** в `error_logs` (уже реализовано)

## Мониторинг

### Метрики для отслеживания:

1. **Успешность обработки:** процент успешных workflow runs
2. **Время обработки:** среднее время от webhook до завершения
3. **Ошибки:** количество записей в `error_logs`
4. **Стоимость:** траты на AssemblyAI + OpenAI API

### Настройка алертов в n8n:

Добавьте Error Trigger для отправки уведомлений при ошибках:

```
Error Trigger
  → Slack/Telegram/Email
    Message: "Ошибка в workflow: {{ $json.error.message }}"
```

## API ключи и стоимость

### AssemblyAI
- **Регистрация:** https://www.assemblyai.com/
- **Бесплатно:** $50 в кредитах (примерно 500 минут аудио)
- **Тарифы:** $0.10/мин для базовой транскрибации
- **Документация:** https://www.assemblyai.com/docs

### OpenAI
- **Регистрация:** https://platform.openai.com/signup
- **GPT-4o:** $2.50 / 1M input tokens, $10.00 / 1M output tokens
- **GPT-4o-mini:** $0.150 / 1M input tokens, $0.600 / 1M output tokens
- **Калькулятор:** https://openai.com/pricing

### Supabase
- **Регистрация:** https://supabase.com/
- **Бесплатно:** 500 MB хранилища, 2GB bandwidth
- **Тарифы:** От $25/мес для продакшн
- **Документация:** https://supabase.com/docs

## Поддержка

### Если возникли проблемы:

1. Проверьте **логи n8n** (Executions → Failed)
2. Изучите **Troubleshooting** выше
3. Проверьте **error_logs** в Supabase
4. Убедитесь, что все credentials настроены корректно

### Полезные ссылки:

- **n8n Documentation:** https://docs.n8n.io/
- **Bitrix24 REST API:** https://dev.1c-bitrix.ru/rest_help/
- **AssemblyAI Docs:** https://www.assemblyai.com/docs
- **OpenAI API Docs:** https://platform.openai.com/docs

## Лицензия

MIT License

---

**Версия:** 1.0.0
**Последнее обновление:** 2025-01-21
**Автор:** AI-архитектор n8n
