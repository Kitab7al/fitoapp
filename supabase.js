// ============================================================
// FITORANK — SUPABASE CLIENT
// Подключать на каждой странице:
// <script src="supabase.js"></script>
// ============================================================

const SUPABASE_URL  = 'https://hkwmjyvccwewbibjswtx.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhrd21qeXZjY3dld2JpYmpzd3R4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyODI0MDIsImV4cCI6MjA4ODg1ODQwMn0.Nh_ICh8dW4707Dq9LNyIMkbUxa478_QLQcGt6yTyzZw';

// ── Лёгкий клиент без npm (через CDN внутри каждого HTML) ──
// Используем глобальный window.supabase из CDN скрипта
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>

let _sb = null;

function getSupabase() {
  if (_sb) return _sb;
  if (typeof supabase === 'undefined') {
    console.error('Supabase CDN не загружен. Добавь <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>');
    return null;
  }
  _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
  return _sb;
}

const sb = () => getSupabase();

// ============================================================
// AUTH helpers
// ============================================================

async function authSignUp(email, password, username, displayName) {
  const client = sb();
  // 1. Создаём пользователя в Auth
  const { data, error } = await client.auth.signUp({
    email,
    password,
    options: {
      data: { username, display_name: displayName }
    }
  });
  if (error) return { error };

  // 2. Создаём публичный профиль
  if (data.user) {
    const { error: profileError } = await client
      .from('users')
      .insert({
        id:           data.user.id,
        username:     username.toLowerCase().replace(/\s/g, '_'),
        display_name: displayName,
        league:       'amateur',
      });
    if (profileError) return { error: profileError };
  }
  return { data };
}

async function authSignIn(email, password) {
  return await sb().auth.signInWithPassword({ email, password });
}

async function authSignOut() {
  return await sb().auth.signOut();
}

async function authGetUser() {
  const { data: { user } } = await sb().auth.getUser();
  return user;
}

async function authGetSession() {
  const { data: { session } } = await sb().auth.getSession();
  return session;
}

// ============================================================
// USERS helpers
// ============================================================

async function getProfile(userId) {
  const { data, error } = await sb()
    .from('users')
    .select('*')
    .eq('id', userId)
    .single();
  return { data, error };
}

async function updateProfile(userId, updates) {
  const { data, error } = await sb()
    .from('users')
    .update(updates)
    .eq('id', userId)
    .select()
    .single();
  return { data, error };
}

async function searchUsers(query, limit = 20) {
  const { data, error } = await sb()
    .from('users')
    .select('id, username, display_name, avatar_url, league, records_count, rating_score')
    .ilike('username', `%${query}%`)
    .limit(limit);
  return { data, error };
}

// ============================================================
// RECORDS helpers
// ============================================================

async function getFeed({ page = 0, limit = 10, sort = 'new' } = {}) {
  let query = sb()
    .from('records')
    .select(`
      *,
      users (id, username, display_name, avatar_url, league),
      exercises (id, name_ru, name_en, category_ru, category_en, emoji)
    `)
    .eq('status', 'approved')
    .range(page * limit, (page + 1) * limit - 1);

  if (sort === 'new')  query = query.order('created_at', { ascending: false });
  if (sort === 'top')  query = query.order('believe_count', { ascending: false });
  if (sort === 'hot')  query = query.order('created_at', { ascending: false }); // TODO: hot score

  const { data, error } = await query;
  return { data, error };
}

async function getRecord(id) {
  const { data, error } = await sb()
    .from('records')
    .select(`
      *,
      users (id, username, display_name, avatar_url, league),
      exercises (id, name_ru, name_en, category_ru, category_en, emoji, standards_male, standards_female)
    `)
    .eq('id', id)
    .single();
  return { data, error };
}

async function getUserRecords(userId) {
  const { data, error } = await sb()
    .from('records')
    .select(`
      *,
      exercises (id, name_ru, name_en, category_ru, category_en, emoji)
    `)
    .eq('user_id', userId)
    .eq('status', 'approved')
    .order('record_date', { ascending: false });
  return { data, error };
}

async function createRecord(record) {
  const user = await authGetUser();
  if (!user) return { error: { message: 'Не авторизован' } };

  const { data, error } = await sb()
    .from('records')
    .insert({ ...record, user_id: user.id, status: 'pending' })
    .select()
    .single();
  return { data, error };
}

// ============================================================
// LEADERBOARD helpers
// ============================================================

async function getLeaderboard({ exerciseId, league, gender, limit = 50 } = {}) {
  let query = sb()
    .from('records')
    .select(`
      id, weight_kg, reps, estimated_1rm, athlete_weight_kg,
      record_date, believe_count, notbelieve_count, level,
      users (id, username, display_name, avatar_url, country),
      exercises (id, name_ru, name_en)
    `)
    .eq('status', 'approved')
    .order('estimated_1rm', { ascending: false })
    .limit(limit);

  if (exerciseId) query = query.eq('exercise_id', exerciseId);
  if (league)     query = query.eq('league', league);

  const { data, error } = await query;
  return { data, error };
}

// ============================================================
// VOTES helpers
// ============================================================

async function vote(recordId, voteType) {
  const user = await authGetUser();
  if (!user) return { error: { message: 'Требуется авторизация' } };

  // Проверяем существующий голос
  const { data: existing } = await sb()
    .from('votes')
    .select('id')
    .eq('record_id', recordId)
    .eq('user_id', user.id)
    .eq('vote_type', voteType)
    .single();

  if (existing) {
    // Отменяем голос
    const { error } = await sb()
      .from('votes')
      .delete()
      .eq('id', existing.id);
    return { data: { action: 'removed' }, error };
  } else {
    // Добавляем голос
    const { data, error } = await sb()
      .from('votes')
      .insert({ record_id: recordId, user_id: user.id, vote_type: voteType })
      .select()
      .single();
    return { data: { action: 'added', vote: data }, error };
  }
}

async function getUserVotes(recordIds) {
  const user = await authGetUser();
  if (!user) return { data: [] };

  const { data, error } = await sb()
    .from('votes')
    .select('record_id, vote_type')
    .eq('user_id', user.id)
    .in('record_id', recordIds);
  return { data, error };
}

// ============================================================
// CHALLENGES helpers
// ============================================================

async function sendChallenge(targetId, recordId, exerciseId) {
  const user = await authGetUser();
  if (!user) return { error: { message: 'Требуется авторизация' } };

  const { data, error } = await sb()
    .from('challenges')
    .insert({
      challenger_id: user.id,
      target_id:     targetId,
      record_id:     recordId,
      exercise_id:   exerciseId,
      status:        'pending'
    })
    .select()
    .single();
  return { data, error };
}

async function getChallenges(userId) {
  const { data, error } = await sb()
    .from('challenges')
    .select(`
      *,
      challenger:users!challenger_id (id, username, display_name, avatar_url),
      target:users!target_id (id, username, display_name, avatar_url),
      records (id, weight_kg, reps, video_url),
      exercises (id, name_ru, name_en)
    `)
    .or(`challenger_id.eq.${userId},target_id.eq.${userId}`)
    .order('created_at', { ascending: false });
  return { data, error };
}

// ============================================================
// FOLLOWERS helpers
// ============================================================

async function followUser(targetId) {
  const user = await authGetUser();
  if (!user) return { error: { message: 'Требуется авторизация' } };

  const { data: existing } = await sb()
    .from('followers')
    .select('id')
    .eq('follower_id', user.id)
    .eq('following_id', targetId)
    .single();

  if (existing) {
    const { error } = await sb().from('followers').delete().eq('id', existing.id);
    return { data: { action: 'unfollowed' }, error };
  } else {
    const { data, error } = await sb()
      .from('followers')
      .insert({ follower_id: user.id, following_id: targetId })
      .select().single();
    return { data: { action: 'followed', follow: data }, error };
  }
}

async function getFollowers(userId) {
  const { data, error } = await sb()
    .from('followers')
    .select('follower_id, users!follower_id (id, username, display_name, avatar_url)')
    .eq('following_id', userId);
  return { data, error };
}

async function getFollowing(userId) {
  const { data, error } = await sb()
    .from('followers')
    .select('following_id, users!following_id (id, username, display_name, avatar_url)')
    .eq('follower_id', userId);
  return { data, error };
}

// ============================================================
// NOTIFICATIONS helpers
// ============================================================

async function getNotifications(limit = 30) {
  const user = await authGetUser();
  if (!user) return { data: [] };

  const { data, error } = await sb()
    .from('notifications')
    .select(`
      *,
      actor:users!actor_id (id, username, display_name, avatar_url),
      records (id, weight_kg, reps)
    `)
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(limit);
  return { data, error };
}

async function markNotificationsRead() {
  const user = await authGetUser();
  if (!user) return;
  await sb().from('notifications').update({ is_read: true }).eq('user_id', user.id);
}

// ============================================================
// EXERCISES helpers
// ============================================================

async function getExercises() {
  const { data, error } = await sb()
    .from('exercises')
    .select('*')
    .order('name_ru');
  return { data, error };
}

async function createFreakExercise(nameRu, nameEn) {
  const user = await authGetUser();
  if (!user) return { error: { message: 'Требуется авторизация' } };

  const { data, error } = await sb()
    .from('exercises')
    .insert({
      name_ru:      nameRu,
      name_en:      nameEn || nameRu,
      category_ru:  'Цирк силы',
      category_en:  'Circus of Strength',
      emoji:        '🎪',
      is_freak:     true,
      created_by:   user.id
    })
    .select()
    .single();
  return { data, error };
}

// ============================================================
// REALTIME — подписка на обновления ленты
// ============================================================

function subscribeToFeed(onNewRecord) {
  return sb()
    .channel('feed')
    .on('postgres_changes', {
      event:  'UPDATE',
      schema: 'public',
      table:  'records',
      filter: 'status=eq.approved'
    }, payload => onNewRecord(payload.new))
    .subscribe();
}

function unsubscribe(channel) {
  sb().removeChannel(channel);
}

// ============================================================
// UTILS
// ============================================================

function getVideoPlatform(url) {
  if (!url) return null;
  if (url.includes('tiktok.com'))  return 'tiktok';
  if (url.includes('instagram.com') || url.includes('instagr.am')) return 'instagram';
  if (url.includes('youtube.com') || url.includes('youtu.be'))     return 'youtube';
  return null;
}

function calculate1RM(weight, reps) {
  if (reps <= 1) return weight;
  return Math.round(weight * (1 + reps / 30) * 10) / 10;
}

function getLevel(estimated1rm, standards) {
  if (!standards || !standards.kg) return 0;
  const norms = standards.kg;
  let level = 0;
  for (let i = 0; i < norms.length; i++) {
    if (estimated1rm >= norms[i]) level = i + 1;
  }
  return level;
}

function getBelievePct(believeCount, notbelieveCount) {
  const total = believeCount + notbelieveCount;
  if (total === 0) return null;
  return Math.round((believeCount / total) * 100);
}

// Экспортируем всё в глобальный объект для использования без модулей
window.FR = {
  sb,
  auth: { signUp: authSignUp, signIn: authSignIn, signOut: authSignOut, getUser: authGetUser, getSession: authGetSession },
  users: { getProfile, updateProfile, searchUsers },
  records: { getFeed, getRecord, getUserRecords, createRecord },
  leaderboard: { get: getLeaderboard },
  votes: { vote, getUserVotes },
  challenges: { send: sendChallenge, getAll: getChallenges },
  followers: { follow: followUser, getFollowers, getFollowing },
  notifications: { get: getNotifications, markRead: markNotificationsRead },
  exercises: { getAll: getExercises, createFreak: createFreakExercise },
  realtime: { subscribe: subscribeToFeed, unsubscribe },
  utils: { getVideoPlatform, calculate1RM, getLevel, getBelievePct },
};

console.log('✅ FitoRank × Supabase connected:', SUPABASE_URL);
