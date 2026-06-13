-- ============================================================
-- FITORANK — SUPABASE MIGRATION v1.0  (001_init)
-- ============================================================
-- Полная схема базы: таблицы, индексы, триггеры-счётчики, RLS,
-- стартовые данные. Это авторитетный слепок применённой схемы
-- проекта Supabase `hkwmjyvccwewbibjswtx` (зафиксировано 2026-06-12).
-- Восстановление с нуля: см. supabase/README.md.
-- Запускать в Supabase Dashboard → SQL Editor.
-- ============================================================

-- Включаем расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- для быстрого поиска по тексту

-- ============================================================
-- 1. USERS (профили пользователей)
-- Supabase Auth создаёт записи в auth.users автоматически,
-- мы делаем публичный профиль в public.users
-- ============================================================
CREATE TABLE public.users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username      TEXT UNIQUE NOT NULL,
  display_name  TEXT NOT NULL,
  avatar_url    TEXT,
  bio           TEXT,
  league        TEXT NOT NULL DEFAULT 'amateur' CHECK (league IN ('pro', 'amateur')),
  gender        TEXT CHECK (gender IN ('male', 'female', 'other')),
  birth_date    DATE,
  body_weight   NUMERIC(5,1),
  body_unit     TEXT NOT NULL DEFAULT 'kg' CHECK (body_unit IN ('kg', 'lbs')),
  country       TEXT,
  city          TEXT,
  -- счётчики (денормализованные для скорости)
  records_count     INT NOT NULL DEFAULT 0,
  followers_count   INT NOT NULL DEFAULT 0,
  following_count   INT NOT NULL DEFAULT 0,
  rating_score      NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 2. EXERCISES (справочник упражнений)
-- ============================================================
CREATE TABLE public.exercises (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ru       TEXT NOT NULL,
  name_en       TEXT NOT NULL,
  category_ru   TEXT NOT NULL,
  category_en   TEXT NOT NULL,
  emoji         TEXT,
  is_bodyweight BOOLEAN NOT NULL DEFAULT FALSE,
  is_freak      BOOLEAN NOT NULL DEFAULT FALSE, -- пользовательские упражнения
  -- нормативы [начинающий, новичок, любитель, продвинутый, КМС, МС, МСМК]
  standards_male   JSONB, -- {"kg": [40,60,90,120,145,170,200]}
  standards_female JSONB, -- {"kg": [20,35,55,75,90,110,135]}
  created_by    UUID REFERENCES public.users(id), -- NULL = системное, UUID = фрик
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 3. RECORDS (рекорды)
-- ============================================================
CREATE TABLE public.records (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  exercise_id         UUID NOT NULL REFERENCES public.exercises(id),
  -- тип рекорда
  record_type         TEXT NOT NULL CHECK (record_type IN ('1rm', 'reps')),
  -- результат
  weight_kg           NUMERIC(6,2),         -- вес отягощения в кг
  reps                INT,                   -- кол-во повторений (для reps)
  bw_mode             TEXT DEFAULT 'weight' CHECK (bw_mode IN ('bw', 'bw+extra', 'extra')),
  -- данные атлета на дату рекорда
  athlete_weight_kg   NUMERIC(5,1) NOT NULL, -- вес атлета на дату рекорда
  -- контекст
  league              TEXT NOT NULL DEFAULT 'amateur' CHECK (league IN ('pro', 'amateur')),
  unit                TEXT NOT NULL DEFAULT 'kg' CHECK (unit IN ('kg', 'lbs')),
  record_date         DATE NOT NULL,
  -- медиа
  video_url           TEXT NOT NULL,         -- обязательно
  video_platform      TEXT CHECK (video_platform IN ('tiktok', 'instagram', 'youtube')),
  comment             TEXT,
  -- модерация
  status              TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected')),
  -- голосование (денормализованные счётчики)
  believe_count       INT NOT NULL DEFAULT 0,
  notbelieve_count    INT NOT NULL DEFAULT 0,
  natural_count       INT NOT NULL DEFAULT 0,
  pharma_count        INT NOT NULL DEFAULT 0,
  -- расчётные поля
  estimated_1rm       NUMERIC(6,2),          -- расчётный 1RM (Epley formula)
  level               INT,                   -- 0-6 уровень по нормативам
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 4. VOTES (голосование)
-- ============================================================
CREATE TABLE public.votes (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  record_id   UUID NOT NULL REFERENCES public.records(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  vote_type   TEXT NOT NULL CHECK (vote_type IN ('believe', 'notbelieve', 'natural', 'pharma')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- один пользователь — один голос каждого типа на запись
  UNIQUE (record_id, user_id, vote_type)
);

-- ============================================================
-- 5. CHALLENGES (вызовы)
-- ============================================================
CREATE TABLE public.challenges (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenger_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  record_id       UUID NOT NULL REFERENCES public.records(id) ON DELETE CASCADE,
  exercise_id     UUID NOT NULL REFERENCES public.exercises(id),
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'accepted', 'completed', 'expired', 'declined')),
  result_record_id UUID REFERENCES public.records(id), -- рекорд-ответ на вызов
  expires_at      TIMESTAMPTZ,                         -- +30 дней после принятия
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- нельзя бросить вызов самому себе
  CHECK (challenger_id != target_id)
);

-- ============================================================
-- 6. FOLLOWERS (подписки)
-- ============================================================
CREATE TABLE public.followers (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  follower_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (follower_id, following_id),
  CHECK (follower_id != following_id)
);

-- ============================================================
-- 7. BADGES (бейджи — справочник)
-- ============================================================
CREATE TABLE public.badges (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code            TEXT UNIQUE NOT NULL,
  name_ru         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  description_ru  TEXT,
  description_en  TEXT,
  icon            TEXT,
  condition_type  TEXT, -- 'records_count', 'level_reached', 'votes_received', etc.
  condition_value JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 8. USER_BADGES (полученные бейджи)
-- ============================================================
CREATE TABLE public.user_badges (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  badge_id    UUID NOT NULL REFERENCES public.badges(id),
  earned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, badge_id)
);

-- ============================================================
-- 9. NOTIFICATIONS (уведомления)
-- ============================================================
CREATE TABLE public.notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN (
                'vote_believe', 'vote_notbelieve',
                'challenge_received', 'challenge_accepted', 'challenge_completed',
                'follow', 'badge_earned', 'record_beaten'
              )),
  actor_id    UUID REFERENCES public.users(id) ON DELETE SET NULL,
  record_id   UUID REFERENCES public.records(id) ON DELETE SET NULL,
  badge_id    UUID REFERENCES public.badges(id) ON DELETE SET NULL,
  is_read     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ИНДЕКСЫ
-- ============================================================

-- Users
CREATE INDEX idx_users_username ON public.users USING GIN (username gin_trgm_ops);
CREATE INDEX idx_users_league ON public.users(league);
CREATE INDEX idx_users_rating ON public.users(rating_score DESC);

-- Records — основные запросы ленты и лидерборда
CREATE INDEX idx_records_user ON public.records(user_id);
CREATE INDEX idx_records_exercise ON public.records(exercise_id);
CREATE INDEX idx_records_status ON public.records(status);
CREATE INDEX idx_records_date ON public.records(record_date DESC);
CREATE INDEX idx_records_league ON public.records(league);
-- Составной индекс для лидерборда
CREATE INDEX idx_records_leaderboard ON public.records(exercise_id, league, status, estimated_1rm DESC);
-- Составной индекс для ленты
CREATE INDEX idx_records_feed ON public.records(status, created_at DESC);

-- Votes
CREATE INDEX idx_votes_record ON public.votes(record_id);
CREATE INDEX idx_votes_user ON public.votes(user_id);

-- Followers
CREATE INDEX idx_followers_follower ON public.followers(follower_id);
CREATE INDEX idx_followers_following ON public.followers(following_id);

-- Notifications
CREATE INDEX idx_notifications_user_unread ON public.notifications(user_id, is_read, created_at DESC);

-- Challenges
CREATE INDEX idx_challenges_target ON public.challenges(target_id, status);
CREATE INDEX idx_challenges_challenger ON public.challenges(challenger_id);

-- ============================================================
-- ТРИГГЕРЫ — автообновление счётчиков
-- ============================================================

-- Обновляем updated_at автоматически
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_records_updated_at
  BEFORE UPDATE ON public.records
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Обновляем счётчики голосов в records при вставке/удалении в votes
CREATE OR REPLACE FUNCTION public.update_vote_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.records SET
      believe_count    = believe_count    + CASE WHEN NEW.vote_type = 'believe'    THEN 1 ELSE 0 END,
      notbelieve_count = notbelieve_count + CASE WHEN NEW.vote_type = 'notbelieve' THEN 1 ELSE 0 END,
      natural_count    = natural_count    + CASE WHEN NEW.vote_type = 'natural'    THEN 1 ELSE 0 END,
      pharma_count     = pharma_count     + CASE WHEN NEW.vote_type = 'pharma'     THEN 1 ELSE 0 END
    WHERE id = NEW.record_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.records SET
      believe_count    = GREATEST(0, believe_count    - CASE WHEN OLD.vote_type = 'believe'    THEN 1 ELSE 0 END),
      notbelieve_count = GREATEST(0, notbelieve_count - CASE WHEN OLD.vote_type = 'notbelieve' THEN 1 ELSE 0 END),
      natural_count    = GREATEST(0, natural_count    - CASE WHEN OLD.vote_type = 'natural'    THEN 1 ELSE 0 END),
      pharma_count     = GREATEST(0, pharma_count     - CASE WHEN OLD.vote_type = 'pharma'     THEN 1 ELSE 0 END)
    WHERE id = OLD.record_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_vote_counts
  AFTER INSERT OR DELETE ON public.votes
  FOR EACH ROW EXECUTE FUNCTION public.update_vote_counts();

-- Обновляем счётчики подписчиков
CREATE OR REPLACE FUNCTION public.update_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE public.users SET followers_count = followers_count + 1 WHERE id = NEW.following_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.users SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
    UPDATE public.users SET followers_count = GREATEST(0, followers_count - 1) WHERE id = OLD.following_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_follow_counts
  AFTER INSERT OR DELETE ON public.followers
  FOR EACH ROW EXECUTE FUNCTION public.update_follow_counts();

-- Обновляем records_count при добавлении/удалении рекорда
CREATE OR REPLACE FUNCTION public.update_records_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'approved' THEN
    UPDATE public.users SET records_count = records_count + 1 WHERE id = NEW.user_id;
  ELSIF TG_OP = 'DELETE' AND OLD.status = 'approved' THEN
    UPDATE public.users SET records_count = GREATEST(0, records_count - 1) WHERE id = OLD.user_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.status != 'approved' AND NEW.status = 'approved' THEN
    UPDATE public.users SET records_count = records_count + 1 WHERE id = NEW.user_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'approved' AND NEW.status != 'approved' THEN
    UPDATE public.users SET records_count = GREATEST(0, records_count - 1) WHERE id = NEW.user_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_records_count
  AFTER INSERT OR UPDATE OR DELETE ON public.records
  FOR EACH ROW EXECUTE FUNCTION public.update_records_count();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.users         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercises      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenges     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.followers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications  ENABLE ROW LEVEL SECURITY;

-- USERS: читают все, редактирует только владелец
CREATE POLICY "users_select_all"  ON public.users FOR SELECT USING (true);
CREATE POLICY "users_insert_own"  ON public.users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "users_update_own"  ON public.users FOR UPDATE USING (auth.uid() = id);

-- EXERCISES: читают все, создают авторизованные
CREATE POLICY "exercises_select_all"  ON public.exercises FOR SELECT USING (true);
CREATE POLICY "exercises_insert_auth" ON public.exercises FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- RECORDS: approved читают все, pending/rejected — только владелец
CREATE POLICY "records_select_approved" ON public.records FOR SELECT
  USING (status = 'approved' OR auth.uid() = user_id);
CREATE POLICY "records_insert_auth" ON public.records FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "records_update_own" ON public.records FOR UPDATE
  USING (auth.uid() = user_id);

-- VOTES: читают все, пишут авторизованные за себя
CREATE POLICY "votes_select_all"  ON public.votes FOR SELECT USING (true);
CREATE POLICY "votes_insert_auth" ON public.votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "votes_delete_own"  ON public.votes FOR DELETE
  USING (auth.uid() = user_id);

-- FOLLOWERS: читают все, пишут авторизованные за себя
CREATE POLICY "followers_select_all"  ON public.followers FOR SELECT USING (true);
CREATE POLICY "followers_insert_auth" ON public.followers FOR INSERT
  WITH CHECK (auth.uid() = follower_id);
CREATE POLICY "followers_delete_own"  ON public.followers FOR DELETE
  USING (auth.uid() = follower_id);

-- CHALLENGES: видят участники
CREATE POLICY "challenges_select_own" ON public.challenges FOR SELECT
  USING (auth.uid() = challenger_id OR auth.uid() = target_id);
CREATE POLICY "challenges_insert_auth" ON public.challenges FOR INSERT
  WITH CHECK (auth.uid() = challenger_id);
CREATE POLICY "challenges_update_target" ON public.challenges FOR UPDATE
  USING (auth.uid() = challenger_id OR auth.uid() = target_id);

-- BADGES: читают все
CREATE POLICY "badges_select_all"      ON public.badges      FOR SELECT USING (true);
CREATE POLICY "user_badges_select_all" ON public.user_badges FOR SELECT USING (true);

-- NOTIFICATIONS: только владелец
CREATE POLICY "notifications_own" ON public.notifications FOR ALL
  USING (auth.uid() = user_id);

-- ============================================================
-- СТАРТОВЫЕ ДАННЫЕ — упражнения и бейджи
-- ============================================================

INSERT INTO public.exercises (name_ru, name_en, category_ru, category_en, emoji, is_bodyweight, standards_male, standards_female) VALUES
  ('Жим лёжа',              'Bench Press',        'Грудь',   'Chest',        '🏋️', false,
   '{"kg":[40,60,90,120,145,170,200]}', '{"kg":[20,35,55,75,90,110,135]}'),
  ('Приседания со штангой', 'Barbell Squat',       'Ноги',    'Legs',         '🦵', false,
   '{"kg":[50,80,110,150,185,220,260]}', '{"kg":[30,50,75,100,125,155,185]}'),
  ('Становая тяга',         'Deadlift',            'Спина',   'Back',         '⚡', false,
   '{"kg":[60,100,140,190,230,275,320]}', '{"kg":[35,60,90,120,150,185,220]}'),
  ('Жим стоя',              'Overhead Press',      'Плечи',   'Shoulders',    '🔝', false,
   '{"kg":[25,40,60,80,100,120,145]}', '{"kg":[15,25,40,55,70,85,100]}'),
  ('Тяга штанги в наклоне', 'Barbell Row',         'Спина',   'Back',         '🔄', false,
   '{"kg":[40,65,90,120,145,170,200]}', '{"kg":[22,38,55,75,90,110,130]}'),
  ('Подтягивания',          'Pull-ups',            'Спина',   'Back',         '🔗', true,
   '{"kg":[0,5,10,15,20,25,30]}', '{"kg":[0,0,3,7,12,18,25]}'),
  ('Отжимания на брусьях',  'Dips',                'Грудь',   'Chest/Tri',    '🔃', true,
   '{"kg":[0,5,15,25,35,50,70]}', '{"kg":[0,0,5,10,18,28,40]}'),
  ('Отжимания от пола',     'Push-ups',            'Грудь',   'Chest',        '💪', true,
   '{"kg":[5,15,30,50,75,100,120]}', '{"kg":[2,8,20,35,55,75,95]}'),
  ('Румынская тяга',        'Romanian Deadlift',   'Ноги',    'Legs/Back',    '🏋️', false,
   '{"kg":[50,80,110,150,185,220,260]}', '{"kg":[28,48,70,95,120,148,175]}'),
  ('Жим на наклонной',      'Incline Bench Press', 'Грудь',   'Chest',        '📐', false,
   '{"kg":[30,50,75,100,125,150,180]}', '{"kg":[15,28,45,62,78,95,115]}'),
  ('Жим ногами',            'Leg Press',           'Ноги',    'Legs',         '🦵', false,
   '{"kg":[80,130,185,240,295,355,420]}', '{"kg":[45,80,120,160,200,245,290]}'),
  ('Фронтальные приседания','Front Squat',         'Ноги',    'Legs',         '🔆', false,
   '{"kg":[40,65,90,120,150,180,215]}', '{"kg":[22,40,60,82,105,128,155]}'),
  ('Сгибания на бицепс',    'Bicep Curl',          'Бицепс',  'Biceps',       '💪', false,
   '{"kg":[15,25,40,55,70,85,100]}', '{"kg":[7,13,22,32,42,52,62]}'),
  ('Трэп-становая',         'Trap Bar Deadlift',   'Спина',   'Back',         '🔷', false,
   '{"kg":[70,110,155,205,250,300,355]}', '{"kg":[40,65,95,130,165,200,240]}'),
  ('Уголок в висе',         'L-sit Hold',          'Кор',     'Core',         '📐', true,
   '{"kg":[3,8,15,25,35,45,60]}', '{"kg":[2,5,10,18,27,36,48]}');

INSERT INTO public.badges (code, name_ru, name_en, description_ru, description_en, icon, condition_type, condition_value) VALUES
  ('first_record',   'Первый рекорд',  'First Record',   'Добавил первый рекорд',        'Added your first record',      '🔥', 'records_count', '{"value":1}'),
  ('records_10',     '10 рекордов',    '10 Records',     'Добавил 10 рекордов',          'Added 10 records',             '💯', 'records_count', '{"value":10}'),
  ('records_25',     '25 рекордов',    '25 Records',     'Добавил 25 рекордов',          'Added 25 records',             '🏅', 'records_count', '{"value":25}'),
  ('level_kms',      'КМС',            'Near-Elite',     'Достиг уровня КМС',            'Reached Near-Elite level',     '👑', 'level_reached', '{"value":4}'),
  ('level_ms',       'Мастер спорта',  'Master',         'Достиг уровня МС',             'Reached Master level',         '🏆', 'level_reached', '{"value":5}'),
  ('top_50',         'Топ 50',         'Top 50',         'Попал в топ-50 рейтинга',      'Ranked in top 50',             '⭐', 'rating_rank',   '{"value":50}'),
  ('top_10',         'Топ 10',         'Top 10',         'Попал в топ-10 рейтинга',      'Ranked in top 10',             '🔱', 'rating_rank',   '{"value":10}'),
  ('with_video',     'С видео',        'On Camera',      'Добавил рекорд с видео',       'Posted a record with video',   '🎥', 'records_count', '{"value":1}'),
  ('challenge_won',  'Победитель',     'Challenger',     'Выиграл вызов',                'Won a challenge',              '⚔️', 'challenges_won','{"value":1}'),
  ('trusted',        'Доверие 95%',    'Trusted',        'Рекорд с рейтингом верю >95%', 'Record with >95% believe rate','✅', 'believe_rate',  '{"value":95}');
