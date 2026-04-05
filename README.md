# CampusMytra — Complete App Documentation

**Version:** 1.0.12+13
**Platform:** Android (Flutter)
**Backend:** Supabase + Firebase
**OTA Updates:** Shorebird Code Push
**Developer:** Kaarma Techis

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [Tech Stack](#2-tech-stack)
3. [App Architecture](#3-app-architecture)
4. [Features & Screens](#4-features--screens)
   - [Auth](#41-auth)
   - [Home](#42-home)
   - [Buzz](#43-buzz--college-feed)
   - [Chatter](#44-chatter--messaging)
   - [Playground — UNO](#45-playground--uno)
   - [Playground — DSA Combat](#46-playground--dsa-combat)
   - [Fitness Buddy](#47-fitness-buddy)
   - [Profile & Friends](#48-profile--friends)
   - [Search](#49-search)
   - [Notifications](#410-notifications)
   - [Settings & About](#411-settings--about)
   - [Admin Panel](#412-admin-panel)
5. [Services](#5-services)
6. [Supabase Edge Functions](#6-supabase-edge-functions)
7. [Database Tables](#7-database-tables)
8. [Database RPCs (Stored Functions)](#8-database-rpcs-stored-functions)
9. [Navigation & Routing](#9-navigation--routing)
10. [Real-time Features](#10-real-time-features)
11. [Push Notifications](#11-push-notifications)
12. [Dynamic App Icons](#12-dynamic-app-icons)
13. [Key Dependencies](#13-key-dependencies)
14. [Assets](#14-assets)
15. [Build & Release](#15-build--release)

---

## 1. App Overview

CampusMytra is a campus social platform built exclusively for AKGEC (and partner colleges). It brings together:

- **Social feed** (Buzz) for college-specific posts
- **Games** (UNO card game + DSA Combat coding battles)
- **AI Fitness Buddy** with personalized plans and chat
- **Messaging** (1-on-1 DMs + group chats)
- **Coin economy** rewarding engagement and wins
- **Admin panel** for content moderation and college management

---

## 2. Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | Flutter (Dart) |
| Backend / Database | Supabase (PostgreSQL + Realtime + Storage) |
| Authentication | Supabase Auth (email/password) |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Local Notifications | flutter_local_notifications |
| AI (Fitness Buddy) | Groq API — `llama-3.1-8b-instant` via Edge Function proxy |
| Code Execution (DSA) | Judge0 CE API via Edge Function proxy |
| OTA Updates | Shorebird Code Push |
| State Management | Provider (theme) + setState (local) |
| Local Storage | SharedPreferences |

---

## 3. App Architecture

```
lib/
├── main.dart                          # Entry point, Supabase init, SplashScreen
├── app_colors.dart                    # Theme-aware color system (light/dark)
├── features/
│   ├── admin/                         # Admin panel
│   ├── auth/                          # Login, signup, OTP
│   ├── badges/                        # Badge/achievement system
│   ├── buzz/                          # College feed & posts
│   ├── chatter/                       # DMs & group chats
│   ├── fitness/                       # AI fitness buddy
│   ├── home/                          # Main hub (6-tab nav)
│   ├── notifications/                 # In-app notifications
│   ├── playground/                    # UNO + DSA Combat games
│   ├── profile/                       # User profiles & friends
│   ├── search/                        # Search users/content
│   └── settings/                      # App settings & theme
└── services/
    └── app_icon_service.dart          # Dynamic launcher icon switching

supabase/functions/
├── gemini-proxy/index.ts              # Groq AI proxy (fitness buddy)
├── judge0-proxy/index.ts              # Code execution proxy (DSA)
└── send-notification/index.ts         # FCM push notification dispatcher
```

---

## 4. Features & Screens

### 4.1 Auth

| File | Description |
|------|-------------|
| `auth/login_screen.dart` | Email/password login with animated gradient background |
| `auth/signup_screen.dart` | Registration with college/branch selection |
| `auth/otp_verification_screen.dart` | OTP verification for new accounts |
| `auth/college_picker_widget.dart` | Searchable dropdown for college and branch |
| `auth/college_update_sheet.dart` | Update college/branch from profile settings |

**Key functions:**
- `Supabase.instance.client.auth.signInWithPassword()` — login
- `Supabase.instance.client.auth.signUp()` — registration
- `supabase.from('profiles').upsert()` — create/update profile on signup

---

### 4.2 Home

| File | Description |
|------|-------------|
| `home/home_screen.dart` | Main hub with 6-tab bottom navigation |
| `home/widgets/leaderboard_widget.dart` | DSA + UNO leaderboard preview |

**Tabs:** Home Feed · Playground · Buzz · Chatter · Fitness · Profile

**Key functions:**
- Realtime subscription to unread message counts
- `supabase.rpc('get_dsa_leaderboard')` — leaderboard data
- FCM token registration on login
- Notification routing on app launch from background

---

### 4.3 Buzz — College Feed

| File | Description |
|------|-------------|
| `buzz/buzz_screen.dart` | Main college feed — create, view, like, comment, delete posts |
| `buzz/comment_poll.dart` | Poll/voting widget embedded in posts |
| `buzz/image_viewer.dart` | Full-screen image viewer for post attachments |
| `buzz/moderation.dart` | Report posts; mod tools for admins |
| `buzz/notification_service.dart` | FCM token management and notification permission requests |

**Key functions:**
- `supabase.from('buzz_posts').select()` — fetch feed
- `supabase.from('buzz_likes').upsert()` — like/unlike post
- `supabase.rpc('can_post_buzz')` — rate-limit check before posting
- `supabase.storage.from('buzz-images').upload()` — image attachments
- Realtime subscription on `buzz_posts` for live updates

---

### 4.4 Chatter — Messaging

| File | Description |
|------|-------------|
| `chatter/chatter_screen.dart` | Inbox — all 1-on-1 conversations |
| `chatter/group_chat_screen.dart` | Group chat with member management |

**Key functions:**
- `supabase.rpc('get_my_inbox')` — fetch conversation list
- `supabase.rpc('get_or_create_conversation')` — start new DM
- `supabase.rpc('send_message')` — send DM
- `supabase.rpc('mark_messages_read')` — mark conversation as read
- `supabase.rpc('create_group_conversation')` — create group chat
- `supabase.rpc('get_group_members')` — list group members
- `supabase.rpc('add_group_member')` / `remove_group_member` — manage members
- Realtime subscription on `messages` for live chat

---

### 4.5 Playground — UNO

| File | Description |
|------|-------------|
| `playground/screens/uno_lobby_screen.dart` | Game lobby — mode selection, coins display |
| `playground/screens/uno_match_makingscreen.dart` | Matchmaking queue |
| `playground/screens/uno_waiting_screen.dart` | Waiting room showing joined players |
| `playground/screens/uno_game_screen.dart` | Live UNO card game with real-time state |
| `playground/models/uno_card.dart` | UNO card data model |
| `playground/services/uno_services.dart` | UNO game logic (draw, play, shuffle, turn management) |
| `playground/services/sound_services.dart` | Sound effects for card plays |
| `playground/screens/playground_leaderboard_screen.dart` | Combined UNO + DSA leaderboard |

**Key functions:**
- `supabase.rpc('find_public_multi_match')` — find/create UNO room
- `supabase.rpc('deduct_coins')` — entry fee deduction
- `supabase.rpc('player_finished_uno')` — record game result and award coins
- `supabase.rpc('leave_multi_room')` — exit game gracefully
- `supabase.rpc('get_uno_leaderboard')` — leaderboard data
- Realtime subscription on game room state for live gameplay

---

### 4.6 Playground — DSA Combat

| File | Description |
|------|-------------|
| `playground/screens/dsa_lobby_screen.dart` | Main DSA hub — Quick Match, Room, Daily, History, Progress, Ranks |
| `playground/screens/dsa_battle_screen.dart` | Real-time 1v1 coding battle |
| `playground/screens/dsa_game_screen.dart` | Live problem solving with code editor |
| `playground/screens/dsa_practice_screen.dart` | Practice DSA problems offline |
| `playground/screens/dsa_daily_screen.dart` | Daily challenge problem |
| `playground/screens/dsa_room_waiting_screen.dart` | Waiting for opponent to join room |
| `playground/screens/vibe_coding_screen.dart` | Casual coding mode |
| `playground/screens/dsa_leaderboard_screen.dart` | DSA-only leaderboard |
| `playground/models/dsa_problem.dart` | DSA problem data model |
| `playground/services/dsa_service.dart` | DSA logic — problem fetch, submission, result processing |

**Room Cards System:**
- Every user gets **3 room cards per day** (auto-initialized on first use)
- Each Quick Match or Room game costs **1 card**
- Card count shown in AppBar top-right — color: white (≥2), orange (1), red (0)
- Buttons disabled when cards = 0
- Owner can grant extra cards via Admin Panel → DSA Cards tab

**Key functions:**
- `supabase.rpc('find_dsa_match')` — matchmaking for Quick Match
- `supabase.rpc('get_or_init_dsa_cards')` — load today's card count
- `supabase.rpc('use_dsa_card')` — atomic card deduction (server-side, FOR UPDATE lock)
- `supabase.rpc('grant_dsa_cards')` — owner grants extra cards by username
- `supabase.rpc('get_daily_challenge')` — fetch today's problem
- `supabase.rpc('update_user_coins')` — award/deduct coins post-match
- `supabase.rpc('record_game_result')` — save match history
- `supabase.rpc('get_dsa_leaderboard')` — leaderboard
- Judge0 CE via `judge0-proxy` Edge Function — execute submitted code

---

### 4.7 Fitness Buddy

| File | Description |
|------|-------------|
| `fitness/fitness_onboarding_screen.dart` | First-time setup: age, weight, height, goal |
| `fitness/fitness_buddy_screen.dart` | Buddy home with stats and navigation |
| `fitness/buddy_chat_screen.dart` | AI chat interface with Groq Llama 3.1 |
| `fitness/fitness_plan_screen.dart` | View personalized workout/diet plan |
| `fitness/fitness_progress_screen.dart` | Progress charts and history |
| `fitness/daily_checkin_screen.dart` | Daily workout + meal check-in |
| `fitness/exercise_customizer_screen.dart` | Customize exercise sets/reps |
| `fitness/exercise_library.dart` | Browse all exercises |
| `fitness/food_selection_screen.dart` | Select meals, track calories |
| `fitness/widgets/buddy_character.dart` | Animated mascot character (Lottie) |
| `fitness/data/food_database.dart` | Local food database with calorie data |
| `fitness/services/fitness_service.dart` | Save/load fitness profile and logs |
| `fitness/services/fitness_ai_service.dart` | AI proxy calls to gemini-proxy Edge Function |
| `fitness/services/fitness_notification_service.dart` | Daily workout reminders |

**Key functions:**
- `http.post(gemini-proxy-url)` — send prompt to Groq AI, receive response
- `supabase.from('profiles').update()` — save fitness profile data
- `flutter_local_notifications` — schedule daily reminders
- Groq API model: `llama-3.1-8b-instant` (14,400 req/day free tier)

---

### 4.8 Profile & Friends

| File | Description |
|------|-------------|
| `profile/profile_screen.dart` | Own profile — avatar, stats, coins, posts, friends list |
| `profile/user_profile_screen.dart` | View any other user's profile |
| `profile/friends_screen.dart` | Friends list with add/remove/pending requests |

**Key functions:**
- `supabase.rpc('get_user_profile')` — full profile data
- `supabase.rpc('get_friends')` — friend list
- `supabase.rpc('get_friendship_status')` — check if friends/pending
- `supabase.from('friendships').insert()` — send friend request
- `supabase.storage.from('avatars').upload()` — update profile picture
- `supabase.rpc('get_user_badge_data')` — fetch earned badges

---

### 4.9 Search

| File | Description |
|------|-------------|
| `search/search_screen.dart` | Search users by name or username |

**Key functions:**
- `supabase.from('profiles').select().ilike('username', '%query%')` — fuzzy search

---

### 4.10 Notifications

| File | Description |
|------|-------------|
| `notifications/notifications_screen.dart` | Full notification history/inbox |

**Notification types handled:**
- `like` — someone liked your post
- `comment` — someone commented on your post
- `college_buzz` — new buzz in your college
- `friend_request` / `friend_accept` — friend activity
- `game_invite` / `game_result` — game activity
- `coins_received` — coin transaction
- `admin` — admin announcement

**Key functions:**
- `supabase.from('notifications').select()` — fetch inbox
- `supabase.from('notifications').update({'read': true})` — mark as read
- Deep link routing based on notification `type`

---

### 4.11 Settings & About

| File | Description |
|------|-------------|
| `settings/setting_screen.dart` | Theme toggle (dark/light), account options |
| `settings/about_screen.dart` | App version, credits |
| `settings/privacy_screen.dart` | Privacy policy |
| `settings/theme_provider.dart` | ThemeProvider (ChangeNotifier) — persisted via SharedPreferences |

---

### 4.12 Admin Panel

| File | Description |
|------|-------------|
| `admin/admin_panel_screen.dart` | Full admin dashboard (owner + moderator roles) |

**Owner-only tabs (7):**
1. **Users** — search users, ban/unban
2. **Content** — delete buzz posts, manage reports
3. **Admins** — manage admin roles, approve admin requests
4. **Colleges** — create colleges, approve verification requests
5. **Announcements** — post college-wide announcements
6. **App Icon** — switch seasonal launcher icon (14 variants)
7. **DSA Cards** — grant extra room cards to any user by username

**Moderator tabs (3):**
1. Content moderation
2. Report management
3. Admin requests

**Key functions:**
- `supabase.from('admins').select()` — verify admin status
- `supabase.from('admin_otps').select()` — OTP-based login
- `supabase.from('banned_users').upsert()` — ban/unban users
- `supabase.rpc('grant_dsa_cards')` — grant room cards (owner only)
- `AppIconService.changeIcon()` — switch app launcher icon
- `supabase.from('announcements').insert()` — create announcement

---

## 5. Services

### `lib/services/app_icon_service.dart`

Manages dynamic app launcher icon switching via Android Activity Aliases.

```dart
enum AppIconVariant {
  defaultIcon, christmas, diwali, holi, newYear2027,
  newYear2028, newYear2029, newYear2030, newYear2031,
  rakhi, ramNavami, spring, summers, winters
}
```

**Methods:**
- `AppIconService.changeIcon(AppIconVariant variant)` — enables the selected alias, disables all others via `MethodChannel('com.campusmytra/app_icon')`
- `AppIconService.getCurrentIcon()` — returns the currently active variant name

**Android implementation:** `MainActivity.kt` uses `PackageManager.setComponentEnabledSetting()` with `DONT_KILL_APP` to switch icons at runtime without reinstalling.

---

## 6. Supabase Edge Functions

### `gemini-proxy` (AI Fitness Buddy)

- **Deployed with:** `--no-verify-jwt` (bypasses JWT check)
- **Backend:** Groq API — `llama-3.1-8b-instant`
- **Input:** `{ prompt: string, temperature?: number, maxTokens?: number }`
- **Output:** `{ text: string }`
- **Used by:** `fitness_ai_service.dart` for buddy chat responses

### `judge0-proxy` (DSA Code Execution)

- **Backend:** Judge0 CE public API
- **Input:** `{ code: string, language_id: number, stdin?: string }`
- **Output:** `{ stdout, stderr, compile_output, status }`
- **Used by:** `dsa_service.dart` to run user-submitted code solutions

### `send-notification` (Push Notifications)

- **Backend:** Firebase Admin SDK → FCM
- **Input:** `{ type, actorId, actorName, targetUserId(s), metadata }`
- **Actions:**
  1. Looks up target user's FCM token from `profiles`
  2. Sends FCM push notification
  3. Inserts row into `notifications` table for in-app inbox
- **Used by:** Multiple features after game results, likes, friend requests, etc.

---

## 7. Database Tables

### Auth & Users

| Table | Purpose |
|-------|---------|
| `profiles` | User profiles — username, avatar, college_id, coins, fcm_token, is_banned |
| `admins` | Admin user mappings with role (owner/moderator) |
| `admin_otps` | Temporary OTPs for admin panel login |
| `admin_requests` | Pending requests to become admin |
| `banned_users` | Banned user records with reason |

### College Management

| Table | Purpose |
|-------|---------|
| `colleges` | College list with name, location metadata |
| `branches` | Branches/departments per college |
| `college_verification_requests` | User-submitted requests to verify college affiliation |

### Social

| Table | Purpose |
|-------|---------|
| `friendships` | Friend connections — status: pending/accepted |
| `messages` | DM messages with sender, receiver, content, read_at |
| `notifications` | In-app notification inbox with type, read status |
| `announcements` | Admin-posted college announcements |

### Buzz / Posts

| Table | Purpose |
|-------|---------|
| `buzz_posts` | Posts — content, college_id, likes_count, reports_count, status |
| `buzz_feed` | Denormalized feed view for efficient queries |
| `buzz_images` | Images attached to posts |
| `buzz_likes` | Like tracking (user_id + post_id) |
| `post_polls` | Poll options in posts |
| `buzz_reports` | User-submitted reports on posts |

### Games

| Table | Purpose |
|-------|---------|
| `game_stats` | Aggregate player stats (wins, losses, coins earned) |
| `match_history` | Individual match records |
| `dsa_problems` | DSA problem bank with title, difficulty, test cases |
| `dsa_battle_rooms` | Real-time battle room state |
| `dsa_rooms` | DSA room sessions (create/join flow) |
| `dsa_room_cards` | Daily room cards per user (user_id + date = PK, default 3) |
| `user_solved_problems` | Which problems each user has solved |
| `user_daily_completions` | Daily challenge completion tracking |

---

## 8. Database RPCs (Stored Functions)

### User & Profile

| RPC | Parameters | Returns |
|-----|-----------|---------|
| `get_user_profile` | `p_user_id` | Full profile object |
| `get_user_badge_data` | `p_user_id` | Badges array |

### Friends & Social

| RPC | Parameters | Returns |
|-----|-----------|---------|
| `get_friends` | `p_user_id` | Friends list |
| `get_my_friends` | `p_user_id` | Friends list (alt) |
| `get_friendship_status` | `p_user_id, p_target_id` | Status string |
| `get_or_create_conversation` | `p_user_id, p_target_id` | Conversation ID |
| `get_my_inbox` | `p_user_id` | Conversations with last message |
| `get_my_groups` | `p_user_id` | Group chat list |
| `create_group_conversation` | `p_creator_id, p_name, p_member_ids` | Group ID |

### Messages

| RPC | Parameters | Returns |
|-----|-----------|---------|
| `send_message` | `p_sender_id, p_receiver_id, p_content` | Message ID |
| `save_message` | `p_sender_id, p_group_id, p_content` | Message ID |
| `mark_messages_read` | `p_user_id, p_conversation_id` | void |
| `track_group_read` | `p_user_id, p_group_id, p_last_read_at` | void |
| `get_group_members` | `p_group_id` | Members array |
| `update_group_name` | `p_group_id, p_name` | void |
| `add_group_member` | `p_user_id, p_group_id` | void |
| `remove_group_member` | `p_user_id, p_group_id` | void |

### Buzz

| RPC | Parameters | Returns |
|-----|-----------|---------|
| `can_post_buzz` | `p_user_id` | boolean |

### DSA Games

| RPC | Parameters | Returns | Security |
|-----|-----------|---------|---------|
| `find_dsa_match` | `p_user_id, p_difficulty` | Room ID | Standard |
| `get_daily_challenge` | `p_user_id` | Problem object | Standard |
| `get_dsa_leaderboard` | `p_limit` | Leaderboard array | Standard |
| `get_or_init_dsa_cards` | `p_user_id` | Card count (int) | Standard |
| `use_dsa_card` | `p_user_id` | New count, or -1 if empty | SECURITY DEFINER + FOR UPDATE lock |
| `grant_dsa_cards` | `p_username, p_cards_to_add` | void | SECURITY DEFINER — verifies owner role |
| `get_dsa_room` | `p_room_id` | Room state | Standard |
| `update_user_coins` | `p_user_id, p_amount, p_reason` | New balance | Standard |
| `record_game_result` | `p_user_id, p_opponent_id, p_won, p_coins_change, p_game_type` | void | Standard |

### UNO Games

| RPC | Parameters | Returns |
|-----|-----------|---------|
| `find_public_multi_match` | `p_user_id, p_entry_fee` | Room ID |
| `player_finished_uno` | `p_room_id, p_user_id, p_position, p_coins_won` | void |
| `deduct_coins` | `p_user_id, p_amount, p_reason` | New balance |
| `leave_multi_room` | `p_user_id, p_room_id` | void |
| `get_uno_leaderboard` | — | Leaderboard array |

---

## 9. Navigation & Routing

```
SplashScreen (main.dart)
├── Connected + Authenticated  →  HomeScreen
├── Connected + Not Authenticated  →  LoginScreen
└── Not Connected  →  ServiceDownScreen (3 retries, 12s timeout each)

LoginScreen  →  SignupScreen  →  OtpVerificationScreen  →  HomeScreen

HomeScreen (6 tabs via BottomNavigationBar)
├── Tab 0: Home Feed + Leaderboard
├── Tab 1: PlaygroundScreen
│   ├── UnoLobbyScreen → UnoMatchmakingScreen → UnoWaitingScreen → UnoGameScreen
│   └── DsaLobbyScreen
│       ├── Quick Match  →  DsaGameScreen (1v1)
│       ├── Room  →  DsaRoomWaitingScreen  →  DsaBattleScreen
│       ├── Daily  →  DsaDailyScreen
│       ├── Progress  →  (inline tab)
│       ├── History  →  (inline tab)
│       └── Ranks  →  DsaLeaderboardScreen
├── Tab 2: BuzzScreen
├── Tab 3: ChatterScreen  →  GroupChatScreen
├── Tab 4: FitnessBuddyScreen  →  BuddyChatScreen / FitnessPlanScreen / etc.
└── Tab 5: ProfileScreen
    ├── FriendsScreen
    ├── UserProfileScreen
    └── SettingsScreen  →  AboutScreen / PrivacyScreen

HomeScreen (global overlays)
├── SearchScreen (modal)
├── NotificationsScreen
└── AdminPanelScreen (admin users only)
```

---

## 10. Real-time Features

Supabase Realtime (WebSocket) subscriptions active throughout the app:

| Feature | Table Subscribed | Events |
|---------|-----------------|--------|
| Unread message badge | `messages` | INSERT |
| Buzz feed live updates | `buzz_posts` | INSERT, UPDATE |
| UNO game state | `uno_rooms` | UPDATE |
| DSA battle state | `dsa_battle_rooms` | UPDATE |
| DSA room waiting | `dsa_rooms` | UPDATE |
| Group chat messages | `group_messages` | INSERT |

---

## 11. Push Notifications

**Flow:**
1. App registers FCM token on login → saved to `profiles.fcm_token`
2. Triggering events (like, comment, game result, friend request, etc.) call `send-notification` Edge Function
3. Edge Function sends FCM push + inserts into `notifications` table
4. On notification tap → app routes to relevant screen based on `type`

**Android permissions:**
- `POST_NOTIFICATIONS` (Android 13+)
- `RECEIVE_BOOT_COMPLETED` (reschedule after reboot)
- `WAKE_LOCK` (delivery reliability)

---

## 12. Dynamic App Icons

14 seasonal launcher icon variants bundled in the APK:

| Variant | Occasion |
|---------|---------|
| Default | Standard |
| Christmas | Christmas |
| Diwali | Diwali |
| Holi | Holi |
| NewYear2027–2031 | New Year (5 variants) |
| Rakhi | Raksha Bandhan |
| RamNavami | Ram Navami |
| Spring | Spring season |
| Summers | Summer season |
| Winters | Winter season |

**How it works:**
- All variants bundled as mipmap PNGs at build time (48/72/96/144/192px)
- Android Activity Aliases in `AndroidManifest.xml` — one per variant
- `PackageManager.setComponentEnabledSetting()` enables/disables aliases at runtime
- Switched via Admin Panel → App Icon tab (owner only)
- No reinstall required

---

## 13. Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `supabase_flutter` | ^2.3.4 | Database, auth, realtime, storage |
| `firebase_core` | ^3.6.0 | Firebase initialization |
| `firebase_messaging` | ^15.1.3 | FCM push notifications |
| `flutter_local_notifications` | ^17.2.2 | Local/scheduled notifications |
| `provider` | ^6.0.0 | Theme state management |
| `shared_preferences` | ^2.2.2 | Persist theme, sound preferences |
| `image_picker` | ^1.0.4 | Camera/gallery for profile pics and posts |
| `flutter_image_compress` | ^2.1.0 | Compress images before upload |
| `http` | ^1.2.0 | HTTP calls to Edge Functions |
| `audioplayers` | ^6.0.0 | Game sound effects |
| `url_launcher` | ^6.3.0 | Open external links |
| `share_plus` | ^7.0.0 | Share content externally |
| `lottie` | ^3.1.0 | Fitness buddy animations |
| `timezone` | ^0.9.4 | Timezone-aware notification scheduling |
| `shorebird_code_push` | ^2.0.3 | OTA Dart-only updates |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |

---

## 14. Assets

```
assets/
├── sound/                   # Game sound effects (card plays, win/loss, etc.)
├── animations/
│   └── buddy/               # Lottie animation files for fitness buddy mascot
└── images/
    ├── app_icon.png                  # Main app icon
    ├── kaarma_techis_logo.png        # Company logo (shown on splash screen)
    ├── ic_launcher_christmas.png     # Seasonal icon sources
    ├── ic_launcher_diwali.png
    └── ... (all other seasonal icon variants)
```

---

## 15. Build & Release

### Full Release (required for native/asset changes)
```bash
shorebird release android
```

### OTA Patch (Dart-only changes, instant delivery)
```bash
shorebird patch android --release-version=1.0.12+13 --allow-asset-diffs
```

### Release History

| Version | Patches | Notable Changes |
|---------|---------|----------------|
| 1.0.12+13 | 1–6 | Dynamic icons (14 variants), splash fixes (app icon + logo), Groq AI backend, server retry logic, DSA Room Cards system, cards moved to AppBar top-right |

### Shorebird Patch Limitations
- Only Dart code changes are included in patches
- Native changes (Kotlin, AndroidManifest, new image assets) require a full new release
- Font/asset changes are not included in patches (use `--allow-asset-diffs` to bypass warning)

---

*Documentation for CampusMytra v1.0.12+13 — Kaarma Techis*
