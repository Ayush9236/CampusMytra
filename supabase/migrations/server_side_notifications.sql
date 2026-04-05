-- ================================================================
-- Server-side notifications via pg_net HTTP calls from DB triggers
-- Run this in Supabase SQL Editor
-- ================================================================

-- Get the service role key and project URL from Supabase secrets
-- We use net.http_post to call the edge function server-side

-- Helper function to call the send-notification edge function
CREATE OR REPLACE FUNCTION _call_send_notification(payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url text := 'https://iukxnbifojobmerspvxn.supabase.co/functions/v1/send-notification';
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1a3huYmlmb2pvYm1lcnNwdnhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyMzAxOTgsImV4cCI6MjA4NjgwNjE5OH0.-go5he8W7NmSaJJYbkj8rHoYST0SBTuk4yZdIC7EIJg';
BEGIN
  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := payload
  );
EXCEPTION WHEN OTHERS THEN
  -- Never fail the main transaction due to notification errors
  NULL;
END;
$$;

-- ── Trigger: friendship INSERT (friend request sent) ────────────────────────
CREATE OR REPLACE FUNCTION trg_notify_friend_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sender_name text;
BEGIN
  -- Get sender username
  SELECT username INTO v_sender_name FROM profiles WHERE id = NEW.sender_id LIMIT 1;

  PERFORM _call_send_notification(jsonb_build_object(
    'type',      'friend_request',
    'toUserId',  NEW.receiver_id::text,
    'actorId',   NEW.sender_id::text,
    'actorName', COALESCE(v_sender_name, 'Someone')
  ));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_friend_request_insert ON friendships;
CREATE TRIGGER on_friend_request_insert
  AFTER INSERT ON friendships
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION trg_notify_friend_request();

-- ── Trigger: friendship UPDATE → accepted (friend request accepted) ─────────
CREATE OR REPLACE FUNCTION trg_notify_friend_accept()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_acceptor_name text;
BEGIN
  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    SELECT username INTO v_acceptor_name FROM profiles WHERE id = NEW.receiver_id LIMIT 1;

    PERFORM _call_send_notification(jsonb_build_object(
      'type',      'friend_accept',
      'toUserId',  NEW.sender_id::text,
      'actorId',   NEW.receiver_id::text,
      'actorName', COALESCE(v_acceptor_name, 'Someone')
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_friend_accept_update ON friendships;
CREATE TRIGGER on_friend_accept_update
  AFTER UPDATE ON friendships
  FOR EACH ROW
  EXECUTE FUNCTION trg_notify_friend_accept();

-- ── Trigger: buzz_likes INSERT (post liked) ─────────────────────────────────
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

DROP TRIGGER IF EXISTS on_buzz_like_insert ON buzz_likes;
CREATE TRIGGER on_buzz_like_insert
  AFTER INSERT ON buzz_likes
  FOR EACH ROW
  EXECUTE FUNCTION trg_notify_like();

-- ── Trigger: post_comments INSERT (post commented) ──────────────────────────
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

  -- Don't notify for anonymous comments
  IF NEW.is_anonymous = true THEN
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

DROP TRIGGER IF EXISTS on_post_comment_insert ON post_comments;
CREATE TRIGGER on_post_comment_insert
  AFTER INSERT ON post_comments
  FOR EACH ROW
  EXECUTE FUNCTION trg_notify_comment();

-- ── Trigger: messages INSERT (chat message sent) ────────────────────────────
CREATE OR REPLACE FUNCTION trg_notify_chat_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_other_user  uuid;
  v_sender_name text;
  v_preview     text;
BEGIN
  -- Find the other participant via conversation_members
  SELECT user_id INTO v_other_user
  FROM conversation_members
  WHERE conversation_id = NEW.conversation_id
    AND user_id != NEW.sender_id
  LIMIT 1;

  IF v_other_user IS NULL THEN RETURN NEW; END IF;

  SELECT username INTO v_sender_name FROM profiles WHERE id = NEW.sender_id LIMIT 1;

  v_preview := LEFT(NEW.content, 60);
  IF length(NEW.content) > 60 THEN v_preview := v_preview || '…'; END IF;

  PERFORM _call_send_notification(jsonb_build_object(
    'type',            'chatter_message',
    'toUserId',        v_other_user::text,
    'actorId',         NEW.sender_id::text,
    'actorName',       COALESCE(v_sender_name, 'Someone'),
    'messagePreview',  v_preview
  ));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_message_insert ON messages;
CREATE TRIGGER on_message_insert
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION trg_notify_chat_message();
