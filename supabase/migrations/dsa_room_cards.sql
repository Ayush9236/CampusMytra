-- ================================================================
-- DSA Room Cards System
-- Run this in Supabase SQL Editor
-- ================================================================

-- 1. Table: one row per user per day
CREATE TABLE IF NOT EXISTS dsa_room_cards (
  user_id         uuid    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date            date    NOT NULL DEFAULT CURRENT_DATE,
  cards_remaining integer NOT NULL DEFAULT 3,
  cards_granted   integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date)
);

-- 2. RLS: users can only read their own row (writes go through RPCs)
ALTER TABLE dsa_room_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own_cards_select"
  ON dsa_room_cards FOR SELECT
  USING (auth.uid() = user_id);

-- 3. get_or_init_dsa_cards
--    Returns today's cards_remaining, creating the row (3 cards) if it doesn't exist.
CREATE OR REPLACE FUNCTION get_or_init_dsa_cards(p_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_cards integer;
BEGIN
  INSERT INTO dsa_room_cards (user_id, date, cards_remaining, cards_granted)
  VALUES (p_user_id, CURRENT_DATE, 3, 0)
  ON CONFLICT (user_id, date) DO NOTHING;

  SELECT cards_remaining INTO v_cards
  FROM dsa_room_cards
  WHERE user_id = p_user_id AND date = CURRENT_DATE;

  RETURN COALESCE(v_cards, 3);
END;
$$;

-- 4. use_dsa_card
--    Atomically deducts 1 card using FOR UPDATE.
--    Returns new cards_remaining, or -1 if no cards left.
CREATE OR REPLACE FUNCTION use_dsa_card(p_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_cards integer;
BEGIN
  -- Ensure row exists for today
  INSERT INTO dsa_room_cards (user_id, date, cards_remaining, cards_granted)
  VALUES (p_user_id, CURRENT_DATE, 3, 0)
  ON CONFLICT (user_id, date) DO NOTHING;

  -- Lock the row to prevent race conditions
  SELECT cards_remaining INTO v_cards
  FROM dsa_room_cards
  WHERE user_id = p_user_id AND date = CURRENT_DATE
  FOR UPDATE;

  IF v_cards <= 0 THEN
    RETURN -1;  -- caller should block the action
  END IF;

  UPDATE dsa_room_cards
  SET cards_remaining = cards_remaining - 1
  WHERE user_id = p_user_id AND date = CURRENT_DATE;

  RETURN v_cards - 1;
END;
$$;

-- 5. grant_dsa_cards (owner-only)
--    Looks up a user by username and adds p_cards to their today total.
--    Returns: 'ok' | 'error:not_authenticated' | 'error:not_authorized' | 'error:user_not_found'
CREATE OR REPLACE FUNCTION grant_dsa_cards(p_username text, p_cards integer)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_requester_id uuid;
  v_target_id    uuid;
  v_is_owner     boolean;
BEGIN
  v_requester_id := auth.uid();
  IF v_requester_id IS NULL THEN
    RETURN 'error:not_authenticated';
  END IF;

  -- Verify caller is owner (uses the admins table)
  SELECT is_owner INTO v_is_owner
  FROM admins
  WHERE user_id = v_requester_id AND is_owner = true
  LIMIT 1;

  IF v_is_owner IS NOT TRUE THEN
    RETURN 'error:not_authorized';
  END IF;

  -- Find target user
  SELECT id INTO v_target_id
  FROM profiles
  WHERE username = p_username
  LIMIT 1;

  IF v_target_id IS NULL THEN
    RETURN 'error:user_not_found';
  END IF;

  -- Upsert today's row and grant
  INSERT INTO dsa_room_cards (user_id, date, cards_remaining, cards_granted)
  VALUES (v_target_id, CURRENT_DATE, 3 + p_cards, p_cards)
  ON CONFLICT (user_id, date)
  DO UPDATE SET
    cards_remaining = dsa_room_cards.cards_remaining + EXCLUDED.cards_granted,
    cards_granted   = dsa_room_cards.cards_granted   + EXCLUDED.cards_granted;

  RETURN 'ok';
END;
$$;
