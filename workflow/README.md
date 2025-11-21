# n8n Call Analysis Workflow - AssemblyAI + GPT + Bitrix24 (Webhook)

Автоматический анализ звонков менеджеров по продаже металлопроката через webhook Bitrix24.

## Что делает workflow

1. **Принимает webhook** от Bitrix24 при завершении звонка (ONVOXIMPLANTCALLEND)
2. **Скачивает запись звонка** из Bitrix24
3. **Загружает в Supabase Storage** для публичного доступа
4. **Транскрибирует через AssemblyAI** (speaker diarization на русском)
5. **Очищает транскрибацию** (убирает ошибки, разделяет Менеджер/Клиент)
6. **Анализирует работу менеджера** по чек-листу (баллы 0-100)
7. **Классифицирует клиента** (горячий/тёплый/холодный)
8. **Генерирует рекомендации** для менеджеров
9. **Записывает в Bitrix24** (поля лида + комментарии в тот же лид)
10. **Сохраняет идеи контента** в Supabase

**Ограничения**: Обрабатывает не более 5 записей звонков за раз.

## Быстрый старт

### 1. Создание bucket в Supabase Storage

1. Откройте Supabase → Storage
2. Создайте новый bucket: `call-recordings`
3. Настройте публичный доступ:
   - Policies → New Policy → Allow public read access

### 2. Импорт workflow

1. Откройте n8n
2. Перейдите в Workflows → Import from File
3. Выберите файл `workflow.json`

### 3. Настройка Credentials

#### AssemblyAI API
1. Settings → Credentials → Add Credential
2. Тип: **Header Auth**
3. Name: `AssemblyAI API`
4. Header Name: `Authorization`
5. Header Value: `f0310a378dd64ad495688b978d1b6992`

#### OpenAI API
1. Add Credential → OpenAI API
2. API Key: ваш ключ OpenAI

#### Supabase
1. Add Credential → Supabase API
2. Host: `https://xxxxx.supabase.co`
3. Service Role Key: ваш ключ

#### Bitrix24
1. Add Credential → HTTP Query Auth
2. Name: `bitrix24Webhook`
3. Value: `https://ваш-портал.bitrix24.ru/rest/1/xxxxxx/`

### 4. Создание таблицы Supabase

Выполните SQL из `docs/supabase_schema.sql` в Supabase SQL Editor.

### 5. Настройка Bitrix24

Создайте пользовательские поля (см. `docs/bitrix24_setup.md`):
- `UF_CRM_CALL_SCORE` (число) - оценка звонка
- `UF_CRM_CLIENT_TYPE` (строка) - тип клиента

### 6. Настройка webhook в Bitrix24

1. В n8n активируйте workflow → скопируйте Production Webhook URL
2. Bitrix24 → Настройки → Настройки REST API → Исходящие вебхуки
3. Создайте вебхук:
   - Название: `Call Analysis Webhook`
   - URL: `https://your-n8n.com/webhook/call-bitrix-incoming`
   - Событие: `ONVOXIMPLANTCALLEND`
   - Метод: POST

### 7. Замена ID Credentials

В workflow.json замените:
- `SUPABASE_CREDENTIAL_ID` → ID вашего Supabase credential
- `ASSEMBLYAI_CREDENTIAL_ID` → ID AssemblyAI credential
- `OPENAI_CREDENTIAL_ID` → ID OpenAI credential
- `BITRIX24_CREDENTIAL_ID` → ID Bitrix24 credential

### 8. Тестирование

1. Сделайте тестовый звонок через Bitrix24 (с записью)
2. После завершения звонка webhook автоматически запустит workflow
3. Проверьте:
   - Production Webhook URL получил запрос
   - Файл загрузился в Supabase Storage (`call-recordings` bucket)
   - Запись создана в таблице `calls_analysis`
   - Транскрибация получена от AssemblyAI
   - Результаты анализа в Supabase
   - Комментарии добавлены в Bitrix24 лид

## Структура workflow

```
Bitrix24 Webhook (ONVOXIMPLANTCALLEND)
    ↓
Extract Webhook Data (call_id, lead_id, record_file_id)
    ↓
Limit to 5 Records (batch processing)
    ↓
Bitrix24 Get File Info (disk.file.get)
    ↓
Download Call Recording (HTTP GET)
    ↓
Upload to Supabase Storage (публичный URL)
    ↓
Create Call Record in Supabase
    ↓
AssemblyAI Start Transcription
    ↓
Wait 10s + Check Status (polling)
    ↓
Extract Transcription Data
    ↓
AI Agent 0: Clean Transcription
    ↓
AI Agents 1-3: Manager Analysis (Parts 1-3)
    ↓
AI Agent 4: Calculate Score (O3)
    ↓
AI Agent 5: Recommendations
    ↓
AI Agent 6: Manager Bitrix Comment
    ↓
AI Agents 7-9: Client Analysis + Type + Comment
    ↓
AI Agent 10: Marketing Ideas
    ↓
Save to Supabase
    ↓
Update Bitrix24 (fields + comments в тот же лид)
```

## Система оценки менеджера (100 баллов)

| Критерий | Баллы |
|----------|-------|
| Приветствие по стандарту | 10 |
| Уточнение имени клиента | 10 |
| Озвучивание цели звонка | 10 |
| Квалификация (5-6 вопросов) | 10 |
| Работа с возражениями | 10 |
| Преимущества компании | 10 |
| Проактивная позиция | 20 |
| Завершение разговора | 20 |

## Типы клиентов

- **Горячий**: готов купить < 2 недель, конкретный проект, обсуждает цены
- **Тёплый**: 1-3 месяца, сравнивает поставщиков, готов общаться
- **Холодный**: > 3 месяцев, только изучает рынок

## Обработка ошибок

- AssemblyAI: retry 3 раза с интервалом 3 сек
- OpenAI: retry 3 раза с интервалом 5 сек
- Bitrix24: retry 3 раза с интервалом 2 сек
- При ошибке транскрибации: status = 'failed', error_message записывается

## Модели GPT

| Агент | Модель | Temperature |
|-------|--------|-------------|
| Очистка | gpt-4-turbo | 0 |
| Анализ частей 1-3 | gpt-4-turbo | 0 |
| Подсчёт баллов | o3-mini | 0 |
| Рекомендации | gpt-4o | 0.3 |
| Комментарии | gpt-4-turbo | 0-0.2 |
| Тип клиента | o3-mini | 0 |
| Маркетинг | gpt-4-turbo | 0.3 |

## Troubleshooting

### AssemblyAI возвращает error
- Проверьте формат аудио (поддерживаются MP3, WAV, FLAC, M4A)
- Проверьте доступность URL аудио
- Убедитесь, что длительность > 1 сек

### Не разделяются спикеры
- AssemblyAI может не разделить при плохом качестве
- Проверьте, что `speaker_labels: true` в запросе

### Ошибка 429 от OpenAI
- Превышен rate limit
- Увеличьте интервал между запросами в Wait нодах

### Bitrix24 не обновляется
- Проверьте права webhook
- Убедитесь, что поля UF_CRM_* созданы

## Файлы

```
workflow/
├── workflow.json              # Основной workflow
├── README.md                  # Эта документация
└── docs/
    ├── supabase_schema.sql    # SQL схема
    └── bitrix24_setup.md      # Настройка CRM
```

## Лицензия

MIT
