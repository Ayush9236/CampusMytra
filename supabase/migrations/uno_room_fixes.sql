-- ================================================================
-- UNO Room Fixes
-- Run this in Supabase SQL Editor
-- ================================================================

-- Fix 1: grant_dsa_cards — use correct `admins` table (not admin_access)
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

  -- Verify caller is owner using the admins table
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
    cards_remaining = dsa_room_cards.cards_remaining + p_cards,
    cards_granted   = dsa_room_cards.cards_granted   + p_cards;

  RETURN 'ok';
END;
$$;

-- Fix 2: leave_multi_room — delete room if last player leaves (no ghost rooms)
CREATE OR REPLACE FUNCTION leave_multi_room(p_room_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_remaining_count integer;
  v_host_id uuid;
  v_new_host uuid;
BEGIN
  -- Remove player's hand
  DELETE FROM multi_player_hands
  WHERE room_id = p_room_id AND player_id = p_user_id;

  -- Remove from player_order
  UPDATE multi_game_rooms
  SET player_order = array_remove(player_order, p_user_id)
  WHERE id = p_room_id;

  -- Count remaining players
  SELECT COUNT(*) INTO v_remaining_count
  FROM multi_player_hands
  WHERE room_id = p_room_id;

  IF v_remaining_count = 0 THEN
    -- Last player left — delete the room entirely
    DELETE FROM multi_game_rooms WHERE id = p_room_id;
  ELSE
    -- Reassign host if the host left
    SELECT host_id INTO v_host_id FROM multi_game_rooms WHERE id = p_room_id;
    IF v_host_id = p_user_id THEN
      SELECT player_id INTO v_new_host
      FROM multi_player_hands
      WHERE room_id = p_room_id
      ORDER BY seat_index
      LIMIT 1;
      UPDATE multi_game_rooms SET host_id = v_new_host WHERE id = p_room_id;
    END IF;
  END IF;
END;
$$;

-- Fix 3: find_public_multi_match — clean up stale hand rows for this user before matching
CREATE OR REPLACE FUNCTION find_public_multi_match(p_user_id uuid)
RETURNS TABLE(v_room_id uuid, v_room_code text, v_is_new boolean)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_room record;
  v_seat integer;
  v_is_new boolean := false;
  v_room_id uuid;
  v_room_code text;
BEGIN
  -- Remove this user from ALL existing waiting rooms before finding a new match.
  -- This prevents ghost player bug when user closed app without properly leaving.
  DELETE FROM multi_player_hands
  WHERE player_id = p_user_id;

  -- Also clean up player_order arrays in any waiting rooms
  UPDATE multi_game_rooms
  SET player_order = array_remove(player_order, p_user_id)
  WHERE status = 'waiting'
    AND player_order @> ARRAY[p_user_id];

  -- Delete any now-empty waiting rooms (host left without closing)
  DELETE FROM multi_game_rooms
  WHERE status = 'waiting'
    AND NOT EXISTS (
      SELECT 1 FROM multi_player_hands WHERE room_id = multi_game_rooms.id
    );

  -- Find an available quick match room (not full, not started)
  SELECT mgr.* INTO v_room
  FROM multi_game_rooms mgr
  WHERE mgr.status = 'waiting'
    AND mgr.room_type = 'quick'
    AND mgr.host_id != p_user_id
    AND (SELECT COUNT(*) FROM multi_player_hands WHERE room_id = mgr.id) < mgr.max_players
    AND NOT EXISTS (
      SELECT 1 FROM multi_player_hands
      WHERE room_id = mgr.id AND player_id = p_user_id
    )
  ORDER BY (SELECT COUNT(*) FROM multi_player_hands WHERE room_id = mgr.id) DESC
  LIMIT 1;

  IF v_room.id IS NOT NULL THEN
    -- Join existing room
    SELECT COUNT(*) INTO v_seat FROM multi_player_hands WHERE room_id = v_room.id;
    INSERT INTO multi_player_hands (room_id, player_id, cards, seat_index)
    VALUES (v_room.id, p_user_id, '[]', v_seat)
    ON CONFLICT (room_id, player_id) DO NOTHING;

    UPDATE multi_game_rooms
    SET player_order = array_append(player_order, p_user_id)
    WHERE id = v_room.id
      AND NOT (player_order @> ARRAY[p_user_id]);

    RETURN QUERY SELECT v_room.id, v_room.room_code::text, false;
  ELSE
    -- Create new room
    v_room_code := upper(substring(md5(random()::text) from 1 for 6));
    v_room_id := gen_random_uuid();

    INSERT INTO multi_game_rooms (id, room_code, host_id, player_order, max_players, min_players, room_type, status)
    VALUES (v_room_id, v_room_code, p_user_id, ARRAY[p_user_id], 7, 2, 'quick', 'waiting');

    INSERT INTO multi_player_hands (room_id, player_id, cards, seat_index)
    VALUES (v_room_id, p_user_id, '[]', 0);

    RETURN QUERY SELECT v_room_id, v_room_code, true;
  END IF;
END;
$$;
