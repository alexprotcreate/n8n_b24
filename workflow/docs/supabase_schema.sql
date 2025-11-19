-- Supabase Schema for Call Analysis Workflow
-- Таблица для хранения звонков и результатов анализа

CREATE TABLE calls_analysis (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Идентификаторы
  call_id TEXT NOT NULL UNIQUE,
  lead_id TEXT,
  deal_id TEXT,

  -- Данные звонка
  call_date TIMESTAMP WITH TIME ZONE,
  audio_url TEXT NOT NULL,                -- URL записи звонка (для AssemblyAI)
  audio_duration_seconds INTEGER,         -- Длительность звонка

  -- Транскрибация (AssemblyAI)
  assemblyai_transcript_id TEXT,          -- ID транскрибации в AssemblyAI
  transcription_status TEXT DEFAULT 'pending', -- pending/processing/completed/failed
  transcript_raw JSONB,                   -- Полный ответ AssemblyAI (с utterances, speakers)
  transcript TEXT,                        -- Текст транскрибации (объединённый)
  clean_transcript TEXT,                  -- Очищенная транскрибация
  speakers_detected INTEGER,              -- Количество обнаруженных спикеров

  -- Анализ менеджера (части)
  seller_part1 TEXT,
  seller_part2 TEXT,
  seller_part3 TEXT,
  seller_score_total INTEGER,             -- Итоговая оценка (баллы 0-100)
  seller_recommendations TEXT,            -- Рекомендации для менеджера
  seller_comment TEXT,                    -- Итоговый комментарий для Bitrix24

  -- Анализ клиента
  client_analysis TEXT,                   -- Подробный анализ клиента
  client_type TEXT,                       -- горячий/тёплый/холодный
  client_comment TEXT,                    -- Комментарий по клиенту для Bitrix24

  -- Маркетинг (хранится в Supabase)
  marketing_pains TEXT,                   -- Боли клиента
  marketing_questions TEXT,               -- Вопросы клиента
  marketing_stories TEXT,                 -- Истории и факапы
  marketing_ideas TEXT,                   -- Идеи для контента

  -- Флаги обработки
  analysis_start BOOLEAN DEFAULT FALSE,
  analysis_complete BOOLEAN DEFAULT FALSE,
  bitrix_updated BOOLEAN DEFAULT FALSE,

  -- Служебные поля
  error_message TEXT,
  retry_count INTEGER DEFAULT 0,
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Индексы для быстрого поиска
CREATE INDEX idx_transcription_status ON calls_analysis(transcription_status)
  WHERE transcription_status IN ('pending', 'processing');

CREATE INDEX idx_analysis_start ON calls_analysis(analysis_start)
  WHERE analysis_start = FALSE AND transcription_status = 'completed';

CREATE INDEX idx_call_id ON calls_analysis(call_id);
CREATE INDEX idx_call_date ON calls_analysis(call_date);
CREATE INDEX idx_lead_id ON calls_analysis(lead_id);
CREATE INDEX idx_client_type ON calls_analysis(client_type);

-- Триггер для обновления last_updated
CREATE OR REPLACE FUNCTION update_last_updated()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_updated = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_calls_analysis_last_updated
BEFORE UPDATE ON calls_analysis
FOR EACH ROW
EXECUTE FUNCTION update_last_updated();

-- Пример добавления тестовой записи
-- INSERT INTO calls_analysis (call_id, audio_url, lead_id)
-- VALUES ('test-001', 'https://example.com/audio.mp3', '123');
