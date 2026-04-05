// supabase/function/send-notification/index.ts
// Deploy: supabase functions deploy send-notification
// Secrets needed:
//   FIREBASE_SERVICE_ACCOUNT_JSON  — Firebase service account JSON (from Firebase Console → Project Settings → Service Accounts → Generate new private key)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PROJECT_ID = 'campusmytra-db600';
const FCM_URL = `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`;

// ── JWT helper to get an access token from service account ──
async function getFcmAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  };

  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const unsigned = `${encode(header)}.${encode(payload)}`;

  // Import private key
  const pemKey = serviceAccount.private_key
    .replace(/\\n/g, '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const keyData = Uint8Array.from(atob(pemKey), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', keyData,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign']
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(unsigned)
  );

  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const jwt = `${unsigned}.${sig}`;

  // Exchange JWT for access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

// ── Build notification title + body from type ──
function buildNotification(body: Record<string, unknown>): { title: string; text: string } {
  const type = body['type'] as string;
  const actor = (body['actorName'] as string | undefined) ?? 'Someone';
  const preview = body['postPreview'] as string | undefined;
  const short = preview ? (preview.length > 60 ? preview.substring(0, 57) + '…' : preview) : '';

  switch (type) {
    case 'like':
      return { title: '❤️ New Like', text: `${actor} liked your post${short ? ': ' + short : ''}` };
    case 'comment':
      return { title: '💬 New Comment', text: `${actor} commented on your post${short ? ': ' + short : ''}` };
    case 'college_buzz':
      return { title: '🏫 Campus Buzz', text: `${actor} posted: ${short}` };
    case 'friend_request':
      return { title: '👋 Friend Request', text: `${actor} sent you a friend request` };
    case 'friend_accept':
      return { title: '🎉 Friends Now!', text: `${actor} accepted your friend request` };
    case 'game_invite':
      return { title: '🎮 Game Invite', text: `${actor} challenges you to ${body['gameType'] ?? 'a game'}!` };
    case 'game_result':
      return {
        title: body['won'] ? '🏆 You Won!' : '💀 You Lost',
        text: body['won']
          ? `You won ${body['coinsChange'] ?? 0} coins in ${body['gameType'] ?? 'a game'}!`
          : `Better luck next time in ${body['gameType'] ?? 'a game'}`,
      };
    case 'chatter_message':
      return { title: `💬 ${actor}`, text: (body['messagePreview'] as string | undefined) ?? 'Sent you a message' };
    case 'coins_received':
      return { title: '🪙 Coins Received', text: `You received ${body['amount']} coins: ${body['reason'] ?? ''}` };
    case 'admin':
      return { title: (body['title'] as string | undefined) ?? '📢 Announcement', text: (body['message'] as string | undefined) ?? '' };
    default:
      return { title: 'CampusMytra', text: 'You have a new notification' };
  }
}

// ── Resolve target user ID(s) from notification body ──
async function resolveTargetUserIds(
  body: Record<string, unknown>,
  supabase: ReturnType<typeof createClient>
): Promise<string[]> {
  const type = body['type'] as string;

  // Single user targets
  const singleUserTypes = ['like', 'comment', 'friend_request', 'friend_accept', 'game_invite', 'game_result', 'coins_received', 'chatter_message'];
  if (singleUserTypes.includes(type)) {
    const id = (body['postOwnerId'] ?? body['toUserId']) as string | undefined;
    return id ? [id] : [];
  }

  // College-wide: get all users with that college_id
  if (type === 'college_buzz' || type === 'admin') {
    const collegeId = body['collegeId'] as string | undefined;
    if (!collegeId) return [];
    const { data } = await supabase
      .from('profiles')
      .select('id')
      .eq('college_id', collegeId);
    const actorId = body['actorId'] as string | undefined;
    return (data ?? []).map((r: { id: string }) => r.id).filter((id: string) => id !== actorId);
  }

  return [];
}

// ── Send one FCM message ──
async function sendFcm(token: string, accessToken: string, notif: { title: string; text: string }, data: Record<string, string>): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch(FCM_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: notif.title, body: notif.text },
        android: {
          notification: { channel_id: 'campus_mytra', color: '#818CF8' },
          priority: 'high',
        },
        data,
      },
    }),
  });
  if (res.ok) return { ok: true };
  const errBody = await res.text();
  return { ok: false, error: `HTTP ${res.status}: ${errBody}` };
}

// ── Main handler ──
Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  try {
    const body = (await req.json()) as Record<string, unknown>;

    // Load service account from secret
    const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!saJson) {
      return new Response(JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON secret not set' }), { status: 500 });
    }
    const serviceAccount = JSON.parse(saJson) as Record<string, string>;

    // Supabase admin client to look up FCM tokens
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Resolve actorName from DB if not provided
    if (!body['actorName'] && body['actorId']) {
      try {
        const { data: actorRow } = await supabase
          .from('profiles').select('username').eq('id', body['actorId']).maybeSingle();
        if (actorRow?.username) body['actorName'] = actorRow.username;
      } catch (_) {}
    }

    // Resolve target user IDs
    const userIds = await resolveTargetUserIds(body, supabase);
    if (userIds.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no targets' }), { status: 200 });
    }

    // Don't notify yourself
    const actorId = body['actorId'] as string | undefined;
    const targets = actorId ? userIds.filter(id => id !== actorId) : userIds;
    if (targets.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'only self' }), { status: 200 });
    }

    // Get FCM tokens for all target users
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, fcm_token')
      .in('id', targets)
      .not('fcm_token', 'is', null);

    const tokens = (profiles ?? []).filter((p: { fcm_token: string | null }) => p.fcm_token);
    if (tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no fcm tokens' }), { status: 200 });
    }

    // Get FCM access token
    const accessToken = await getFcmAccessToken(serviceAccount);
    const notif = buildNotification(body);

    // Build data payload (all values must be strings)
    const dataPayload: Record<string, string> = {};
    for (const [k, v] of Object.entries(body)) {
      if (v !== undefined && v !== null) dataPayload[k] = String(v);
    }

    // Send to all tokens
    let sent = 0;
    const errors: string[] = [];
    for (const profile of tokens) {
      const result = await sendFcm(profile.fcm_token, accessToken, notif, dataPayload);
      if (result.ok) sent++;
      else if (result.error) errors.push(result.error);
    }

    // Also save to in-app notifications inbox for single-user targets
    const singleUserTypes = ['like', 'comment', 'friend_request', 'friend_accept', 'game_invite', 'game_result', 'coins_received'];
    if (singleUserTypes.includes(body['type'] as string)) {
      for (const userId of targets) {
        await supabase.from('notifications').insert({
          user_id: userId,
          type: body['type'],
          title: notif.title,
          body: notif.text,
          data: body,
        }).then(() => {}).catch(() => {});
      }
    }

    return new Response(JSON.stringify({ sent, total: tokens.length, errors }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
