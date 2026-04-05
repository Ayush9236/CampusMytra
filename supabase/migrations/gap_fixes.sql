-- ================================================================
-- Gap fixes migration
-- Run in Supabase SQL Editor
-- ================================================================

-- ── 1. Ensure pg_net is enabled ──────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ── 2. Add solution column to dsa_problems ───────────────────────
ALTER TABLE dsa_problems ADD COLUMN IF NOT EXISTS solution TEXT;

-- ── 3. Blocked users table ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS blocked_users (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  blocked_id  uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (blocker_id, blocked_id)
);

ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;

-- Users can only see/manage their own blocks
CREATE POLICY "own blocks" ON blocked_users
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

-- ── 4. Rate limiting: update notification triggers ───────────────
-- Replace trg_notify_like with cooldown (skip if notified in last 10 min)
CREATE OR REPLACE FUNCTION trg_notify_like()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_post_owner  uuid;
  v_liker_name  text;
  v_preview     text;
BEGIN
  SELECT user_id, LEFT(content, 80) INTO v_post_owner, v_preview
  FROM buzz_posts WHERE id = NEW.post_id LIMIT 1;

  -- Don't notify yourself
  IF v_post_owner IS NULL OR v_post_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Rate limit: skip if already sent a like notification for this post in the last 10 minutes
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_post_owner
      AND type = 'like'
      AND (data->>'postId') = NEW.post_id::text
      AND created_at > NOW() - INTERVAL '10 minutes'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_liker_name FROM profiles WHERE id = NEW.user_id LIMIT 1;

  PERFORM _call_send_notification(jsonb_build_object(
    'type',        'like',
    'postOwnerId', v_post_owner::text,
    'postId',      NEW.post_id::text,
    'actorId',     NEW.user_id::text,
    'actorName',   COALESCE(v_liker_name, 'Someone'),
    'postPreview', COALESCE(v_preview, '')
  ));
  RETURN NEW;
END;
$$;

-- Replace trg_notify_comment with cooldown (1 comment notif per post per 5 min)
CREATE OR REPLACE FUNCTION trg_notify_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_post_owner    uuid;
  v_commenter     text;
  v_preview       text;
BEGIN
  SELECT user_id, LEFT(content, 80) INTO v_post_owner, v_preview
  FROM buzz_posts WHERE id = NEW.post_id LIMIT 1;

  IF v_post_owner IS NULL OR v_post_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  IF NEW.is_anonymous = true THEN
    RETURN NEW;
  END IF;

  -- Rate limit: 1 comment notification per post per 5 minutes
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_post_owner
      AND type = 'comment'
      AND (data->>'postId') = NEW.post_id::text
      AND created_at > NOW() - INTERVAL '5 minutes'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_commenter FROM profiles WHERE id = NEW.user_id LIMIT 1;

  PERFORM _call_send_notification(jsonb_build_object(
    'type',        'comment',
    'postOwnerId', v_post_owner::text,
    'postId',      NEW.post_id::text,
    'actorId',     NEW.user_id::text,
    'actorName',   COALESCE(v_commenter, 'Someone'),
    'postPreview', COALESCE(v_preview, '')
  ));
  RETURN NEW;
END;
$$;

-- Replace trg_notify_chat_message with cooldown (1 per conversation per minute)
CREATE OR REPLACE FUNCTION trg_notify_chat_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_other_user  uuid;
  v_sender_name text;
  v_preview     text;
BEGIN
  SELECT user_id INTO v_other_user
  FROM conversation_members
  WHERE conversation_id = NEW.conversation_id
    AND user_id != NEW.sender_id
  LIMIT 1;

  IF v_other_user IS NULL THEN RETURN NEW; END IF;

  -- Rate limit: 1 chat notification per conversation per 60 seconds
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_other_user
      AND type = 'chatter_message'
      AND (data->>'conversationId') = NEW.conversation_id::text
      AND created_at > NOW() - INTERVAL '60 seconds'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_sender_name FROM profiles WHERE id = NEW.sender_id LIMIT 1;

  v_preview := LEFT(NEW.content, 60);
  IF length(NEW.content) > 60 THEN v_preview := v_preview || '…'; END IF;

  PERFORM _call_send_notification(jsonb_build_object(
    'type',              'chatter_message',
    'toUserId',          v_other_user::text,
    'actorId',           NEW.sender_id::text,
    'actorName',         COALESCE(v_sender_name, 'Someone'),
    'messagePreview',    v_preview,
    'conversationId',    NEW.conversation_id::text
  ));
  RETURN NEW;
END;
$$;
