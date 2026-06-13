# Supabase — база FitoRank

Здесь хранится схема базы данных под контролем версий. Это страховка: если
проект Supabase будет потерян (удалён, не восстановлен после паузы), базу можно
поднять заново одним файлом.

## Текущий проект
- Project ref: `hkwmjyvccwewbibjswtx`
- URL: `https://hkwmjyvccwewbibjswtx.supabase.co`
- anon-ключ (публичный) лежит во фронтенде и в `keepalive` workflow.
- `service_role`-ключ нигде в репозитории не хранится и не должен.

## Файлы
- `migrations/001_init.sql` — полная начальная схема: 9 таблиц
  (`users, exercises, records, votes, challenges, followers, badges,
  user_badges, notifications`), индексы, триггеры-счётчики, RLS-политики,
  стартовые данные (15 упражнений + 10 бейджей).

## Восстановление базы с нуля
1. Создать новый проект на supabase.com (регион ближе к СНГ, напр. eu-central-1).
2. Dashboard → **SQL Editor** → вставить содержимое `migrations/001_init.sql` → **Run**.
3. **Authentication → Providers → Email** → выключить «Confirm email»
   (для MVP — чтобы регистрация пускала сразу, без писем-подтверждений).
4. Если ref проекта изменился — обновить `SUPABASE_URL` / `SUPABASE_ANON`
   в файлах фронтенда и в `.github/workflows/keepalive.yml`.

## Правила
- Новые изменения схемы — отдельным файлом `migrations/002_*.sql`, `003_*.sql` …
  (не править `001_init.sql` задним числом).
- Профиль в `public.users` создаётся клиентом после регистрации
  (`signUp` → `insert`), RLS-политика `users_insert_own` это разрешает.
