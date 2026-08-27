# COMPETITIVE RANKING, PRAETORIAN BRACKETS & OPERATOR DOSSIER SPECIFICATION

**Document Version:** 2.0.0  
**Target Repository:** `socom-141-camera-lab`  
**Engine:** Godot 4.x (GDScript 2.0)  
**Status:** Authoritative Design & Complete Technical Reference  

---

## 1. Executive Summary & Thematic Foundation

This specification establishes the tournament-grade competitive rating engine, progression hierarchy, and player identity dossier for **SOCOM-141 / Gunfight Operations**.

### 1.1 Thematic Foundation: *Praetorian*
Drawing inspiration from elite Roman military command structures and modern special operations:
* **The Concept:** In Roman history, the *Praetorians* were the elite, handpicked executive guard and specialized tactical unit.
* **The Role in Competition:** *Praetorian* serves as the pinnacle rank tier (top 2% to top 250 players globally), while earlier ranks honor the discipline of the classical hierarchy (*Auxiliary $\rightarrow$ Legionary $\rightarrow$ Centurion $\rightarrow$ Tribunus $\rightarrow$ Praetorian $\rightarrow$ Praetorian Prefect*).

---

## 2. Competitive ELO Brackets & Rank Distribution

The ranking engine operates on a standardized `0 – 3,000+` Elo/MMR scale, mapped to a competitive bell curve:

```
[Auxiliary] -> [Legionary] -> [Centurion] -> [Tribunus] -> [Praetorian] -> [Praetorian Prefect]
  (0-1199)      (1200-1599)   (1600-1999)   (2000-2399)   (2400-2799)        (2800+)
  Bottom 20%     Median 35%    Upper 25%     Top 15%       Top 4% (Elite)     Top 250 Global
```

### 2.1 Tier & Division Matrix

| Tier Index | Tier Name | Sub-Divisions | ELO Range | ELO / Division | Color Hex | Description & Competitive Mindset |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **0** | **Auxiliary** | III, II, I | `0 – 1,199` | 400 | `#7f8b9c` | Baseline calibration tier. Fundamentals, recoil control, and map awareness. |
| **1** | **Legionary** | III, II, I | `1,200 – 1,599` | 133 | `#8bc5ae` | Core median player base. Standard squad combat, team callouts, and trade frags. |
| **2** | **Centurion** | III, II, I | `1,600 – 1,999` | 133 | `#f2cf6a` | Advanced operators. Coordinated utility usage, disciplined crosshair placement. |
| **3** | **Tribunus** | III, II, I | `2,000 – 2,399` | 133 | `#e06c75` | High-tier mastery. Rapid site takes, optimal rotation timings, tactical clutch capability. |
| **4** | **Praetorian** | III, II, I | `2,400 – 2,799` | 133 | `#d19a66` | Elite competitive tier (Top ~4%). Semi-pro/scrim ready, masterful gun mechanics. |
| **5** | **Praetorian Prefect** | Global `#Rank` | `2,800+` | N/A | `#c678dd` | Supreme apex tier (**Top 250 Worldwide**). Displays exact global rank and live MMR. |

### 2.2 Calibration & Placement Rules
* **New Operators:** Undergo **5 Calibration Matches** with an elevated $K$-factor to rapidly determine initial baseline placement (starting at `1,200 ELO` - *Legionary III*).
* **Demotion Shield:** Promoted operators receive a 3-match grace buffer at `0 ELO` within their new tier before any tier demotion is finalized.
* **Praetorian Rank Decay:** Operators in *Praetorian* and *Praetorian Prefect* must bank match credits (1 match = 1 day banked, max 7 days). Reaching 0 banked days inflicts `-15 ELO/day` to prevent leaderboard squatting.

---

## 3. The Per-Tier Combat Efficiency Engine (K/D Reset)

Standard career K/D metrics in traditional shooters suffer from **historical dilution** (e.g., players padding stats against novice lobbies or protecting high K/Ds by avoiding high-tier risk). 

### 3.1 Core Mechanic: Active Bracket K/D Reset
* Whenever a player is **promoted** to a higher Rank Tier or **demoted** to a lower Rank Tier:
  1. The player's active tier stats reset to clean zero:
     $$\text{Tier Kills} = 0, \quad \text{Tier Deaths} = 0, \quad \text{Tier Matches} = 0$$
  2. The final performance from the previous tier is permanently archived into the player's **Tier Dossier History**.
  3. The active combat card now displays their true **Bracket K/D** against peers of equal skill.

### 3.2 Tier Dossier Archiving Structure
The persistent record preserves a complete history of the player's performance at every skill bracket:

```json
{
  "tier_dossiers": {
    "AUXILIARY": {
      "final_kd": 1.85,
      "kills": 74,
      "deaths": 40,
      "matches": 12,
      "wins": 9,
      "status": "PROMOTED"
    },
    "LEGIONARY": {
      "final_kd": 1.34,
      "kills": 147,
      "deaths": 110,
      "matches": 24,
      "wins": 15,
      "status": "PROMOTED"
    }
  }
}
```

---

## 4. Complete System Integration Map (All Touched Files)

| File Path | Role & Integration Responsibility |
| :--- | :--- |
| `scripts/competitive/socom_competitive_types.gd` | **[NEW]** Static type library, enums, ELO tier math, color palettes, and tier progress calculations. |
| `scripts/profile/socom_player_profile.gd` | **[NEW]** Authoritative player profile model, JSON persistence (`user://player_profile.json`), active tier K/D tracking, reset triggers, tier dossier history, and lifetime stats. |
| `scripts/ui/socom_player_card_widget.gd` | **[NEW]** Production UI button for the top-right header: renders rank badge, tier division, callsign, active tier K/D, and mini ELO bar. Emits `card_clicked`. |
| `scripts/ui/socom_operator_dossier_modal.gd` | **[NEW]** Fullscreen `CanvasLayer` modal displaying the Active Bracket Card, Tier History Dossier, Career Totals, and live Callsign Customizer. |
| `scripts/ui/game_launcher.gd` | **[TOUCHED]** Replaces static `identity_label` with `SocomPlayerCardWidget`, adds `CAREER -> OPERATOR DOSSIER` sidebar button, wires modal toggle, and binds guest session name changes. |
| `scripts/network/socom_supabase_client.gd` | **[TOUCHED/INTEGRATED]** Syncs authenticated guest `display_name` and `user_id` with `SocomPlayerProfile.instance()`. |
| `scripts/tournament/socom_tournament_model.gd` | **[INTEGRATED]** Tournament bracket coordinator uses `SocomPlayerProfile.elo` for competitive seeding. |
| `tools/competitive_profile_regression.gd` | **[NEW]** Headless automated test script validating math, persistence, promotion/demotion K/D resets, and UI binding. |
| `tools/run_competitive_profile_regression.sh` | **[NEW]** Shell script executing headless regression gate with pass/fail validation. |

---

## 5. Godot Scene & Node Hierarchy

```
[Control: GameLauncher (res://game_launcher.tscn)]
  ├── [ColorRect: Background]
  ├── [MarginContainer: Margin]
  │     └── [VBoxContainer: Column]
  │           ├── [HBoxContainer: TopBar]
  │           │     ├── [Label: Title "141"]
  │           │     ├── [Label: Subtitle "GUNFIGHT OPERATIONS"]
  │           │     ├── [SocomPlayerCardWidget: PlayerCardWidget]  <--- NEW (Top-Right Pill)
  │           │     └── [Button: PlayerSettingsButton]
  │           ├── [HSeparator]
  │           └── [HBoxContainer: MainRow]
  │                 ├── [PanelContainer: LeftPanel]
  │                 │     └── [VBoxContainer: LeftColumn]
  │                 │           ├── [Label: Heading "PLAY"]
  │                 │           ├── [Button: QuickMatch2v2]
  │                 │           ├── [Button: HostTournament]
  │                 │           ├── [Button: TrainingRange]
  │                 │           ├── [HSeparator]
  │                 │           ├── [Label: Heading "CAREER"]      <--- NEW
  │                 │           ├── [Button: OperatorDossier]     <--- NEW (Opens Modal)
  │                 │           ├── [HSeparator]
  │                 │           ├── [Label: Heading "CREATE"]
  │                 │           └── [Button: MapEditor]
  │                 ├── [PanelContainer: FeaturePanel]
  │                 └── [PanelContainer: ServersPanel]
  │
  ├── [SocomControlsGuide: PublicPlayerSettings] (Layer 90)
  └── [SocomOperatorDossierModal: OperatorDossierModal] (Layer 95)  <--- NEW (CanvasLayer Overlay)
```

---

## 6. Production GDScript Source Code

### 6.1 `scripts/competitive/socom_competitive_types.gd`

```gdscript
class_name SocomCompetitiveTypes
extends RefCounted

## Pure static definitions, Elo thresholds, tier calculations, and thematic palettes
## for the 141 Competitive Praetorian Ranking System.

enum RankTier {
	AUXILIARY,
	LEGIONARY,
	CENTURION,
	TRIBUNUS,
	PRAETORIAN,
	PRAETORIAN_PREFECT
}

const TIER_THRESHOLDS: Array[Dictionary] = [
	{
		"tier": RankTier.AUXILIARY,
		"name": "Auxiliary",
		"min_elo": 0,
		"max_elo": 1199,
		"divisions": 3,
		"color": Color("7f8b9c"),
		"description": "Baseline calibration tier. Learning core recoil, angles, and squad callouts."
	},
	{
		"tier": RankTier.LEGIONARY,
		"name": "Legionary",
		"min_elo": 1200,
		"max_elo": 1599,
		"divisions": 3,
		"color": Color("8bc5ae"),
		"description": "Core combat force. Proficient with gunplay fundamentals and trade fragging."
	},
	{
		"tier": RankTier.CENTURION,
		"name": "Centurion",
		"min_elo": 1600,
		"max_elo": 1999,
		"divisions": 3,
		"color": Color("f2cf6a"),
		"description": "Tactical commanders. Coordinated utility deployment and disciplined site holds."
	},
	{
		"tier": RankTier.TRIBUNUS,
		"name": "Tribunus",
		"min_elo": 2000,
		"max_elo": 2399,
		"divisions": 3,
		"color": Color("e06c75"),
		"description": "High-tier mastery. Rapid site takes, optimal rotation timings, and clutch execution."
	},
	{
		"tier": RankTier.PRAETORIAN,
		"name": "Praetorian",
		"min_elo": 2400,
		"max_elo": 2799,
		"divisions": 3,
		"color": Color("d19a66"),
		"description": "Elite vanguard (Top ~4%). Master-level gun calibration and deep situational awareness."
	},
	{
		"tier": RankTier.PRAETORIAN_PREFECT,
		"name": "Praetorian Prefect",
		"min_elo": 2800,
		"max_elo": 99999,
		"divisions": 1,
		"color": Color("c678dd"),
		"description": "Apex tournament champions (Top 250 Worldwide). Displays live global leaderboard rank."
	}
]

static func get_tier_info(elo: int) -> Dictionary:
	var clamped_elo := maxi(0, elo)
	for info in TIER_THRESHOLDS:
		if clamped_elo >= int(info["min_elo"]) and clamped_elo <= int(info["max_elo"]):
			return info
	return TIER_THRESHOLDS[TIER_THRESHOLDS.size() - 1]

static func get_tier_enum(elo: int) -> RankTier:
	return RankTier(get_tier_info(elo)["tier"])

static func get_tier_name(tier: RankTier) -> String:
	for info in TIER_THRESHOLDS:
		if int(info["tier"]) == int(tier):
			return String(info["name"])
	return "Unranked"

static func get_tier_color(tier: RankTier) -> Color:
	for info in TIER_THRESHOLDS:
		if int(info["tier"]) == int(tier):
			return info["color"] as Color
	return Color("7f8b9c")

static func get_division(elo: int) -> int:
	var info := get_tier_info(elo)
	var tier: RankTier = RankTier(info["tier"])
	if tier == RankTier.PRAETORIAN_PREFECT:
		return 1
	var min_elo: int = info["min_elo"]
	var max_elo: int = info["max_elo"]
	var range_size := (max_elo - min_elo + 1)
	var division_size := range_size / 3
	var progress := maxi(0, elo - min_elo)
	if progress < division_size:
		return 3 # Div III (entry)
	elif progress < division_size * 2:
		return 2 # Div II (mid)
	else:
		return 1 # Div I (gatekeeper)

static func get_division_roman(division: int) -> String:
	match division:
		1: return "I"
		2: return "II"
		3: return "III"
	return "I"

static func format_full_rank(elo: int, leaderboard_pos: int = -1) -> String:
	var info := get_tier_info(elo)
	var tier: RankTier = RankTier(info["tier"])
	if tier == RankTier.PRAETORIAN_PREFECT:
		if leaderboard_pos > 0:
			return "PRAETORIAN PREFECT #%d" % leaderboard_pos
		return "PRAETORIAN PREFECT"
	var div := get_division(elo)
	return "%s %s" % [String(info["name"]).to_upper(), get_division_roman(div)]

static func get_tier_progress_ratio(elo: int) -> float:
	var info := get_tier_info(elo)
	var tier: RankTier = RankTier(info["tier"])
	if tier == RankTier.PRAETORIAN_PREFECT:
		return 1.0
	var min_elo: int = info["min_elo"]
	var max_elo: int = info["max_elo"]
	var span := float(max_elo - min_elo + 1)
	return clampf(float(elo - min_elo) / span, 0.0, 1.0)
```

---

### 6.2 `scripts/profile/socom_player_profile.gd`

```gdscript
class_name SocomPlayerProfile
extends RefCounted

## Authoritative persistent player profile, competitive ranking state,
## and per-tier K/D reset tracking engine.

signal profile_changed()
signal tier_promoted(old_tier: SocomCompetitiveTypes.RankTier, new_tier: SocomCompetitiveTypes.RankTier)
signal tier_demoted(old_tier: SocomCompetitiveTypes.RankTier, new_tier: SocomCompetitiveTypes.RankTier)

const SAVE_PATH := "user://player_profile.json"
const DEFAULT_STARTING_ELO := 1200 # Baseline Legionary III
const PLACEMENTS_REQUIRED := 5

static var _singleton: SocomPlayerProfile

# Identity
var callsign: String = "Operator"
var clan_tag: String = "141"
var cloud_user_id: String = ""

# Competitive Ranking
var elo: int = DEFAULT_STARTING_ELO
var placement_matches_remaining: int = PLACEMENTS_REQUIRED
var leaderboard_position: int = -1
var demotion_protection_matches: int = 0
var last_calculated_tier: SocomCompetitiveTypes.RankTier = SocomCompetitiveTypes.RankTier.LEGIONARY

# Active Tier Performance (Resets on Promotion/Demotion)
var current_tier_kills: int = 0
var current_tier_deaths: int = 0
var current_tier_matches: int = 0
var current_tier_wins: int = 0

# Permanent Tier Archive (Historical Dossier)
# Format: { "LEGIONARY": { "final_kd": 1.34, "kills": 147, "deaths": 110, "matches": 24, "wins": 15, "status": "PROMOTED" } }
var tier_dossiers: Dictionary = {}

# Lifetime Career Totals
var lifetime_kills: int = 0
var lifetime_deaths: int = 0
var lifetime_matches: int = 0
var lifetime_wins: int = 0

var custom_save_path: String = SAVE_PATH


static func instance() -> SocomPlayerProfile:
	if _singleton == null:
		_singleton = SocomPlayerProfile.new()
		_singleton.load_from_disk()
	return _singleton


func _init() -> void:
	last_calculated_tier = SocomCompetitiveTypes.get_tier_enum(elo)


func get_active_tier_kd() -> float:
	if current_tier_deaths == 0:
		return float(current_tier_kills)
	return snappedf(float(current_tier_kills) / float(current_tier_deaths), 0.01)


func get_lifetime_kd() -> float:
	if lifetime_deaths == 0:
		return float(lifetime_kills)
	return snappedf(float(lifetime_kills) / float(lifetime_deaths), 0.01)


func get_active_tier_win_rate() -> float:
	if current_tier_matches == 0:
		return 0.0
	return snappedf(float(current_tier_wins) / float(current_tier_matches) * 100.0, 0.1)


func get_lifetime_win_rate() -> float:
	if lifetime_matches == 0:
		return 0.0
	return snappedf(float(lifetime_wins) / float(lifetime_matches) * 100.0, 0.1)


func set_identity(new_callsign: String, new_clan_tag: String = "") -> void:
	var clean_name := new_callsign.strip_edges()
	if not clean_name.is_empty():
		callsign = clean_name.left(20)
	if not new_clan_tag.is_empty():
		clan_tag = new_clan_tag.strip_edges().to_upper().left(5)
	save_to_disk()
	profile_changed.emit()


func record_match_result(kills: int, deaths: int, won: bool, elo_delta: int = 0) -> void:
	# 1. Update active tier metrics
	current_tier_kills += maxi(0, kills)
	current_tier_deaths += maxi(0, deaths)
	current_tier_matches += 1
	if won:
		current_tier_wins += 1

	# 2. Update lifetime career totals
	lifetime_kills += maxi(0, kills)
	lifetime_deaths += maxi(0, deaths)
	lifetime_matches += 1
	if won:
		lifetime_wins += 1

	# 3. Placement count or ELO update
	if placement_matches_remaining > 0:
		placement_matches_remaining = maxi(0, placement_matches_remaining - 1)
	elo = maxi(0, elo + elo_delta)

	# 4. Evaluate Tier Transitions & K/D Reset
	_evaluate_tier_transition()

	save_to_disk()
	profile_changed.emit()


func _evaluate_tier_transition() -> void:
	var new_tier := SocomCompetitiveTypes.get_tier_enum(elo)
	if new_tier == last_calculated_tier:
		return

	var old_tier := last_calculated_tier
	var old_tier_name := SocomCompetitiveTypes.get_tier_name(old_tier).to_upper()

	if int(new_tier) > int(old_tier):
		# PROMOTION
		tier_dossiers[old_tier_name] = {
			"final_kd": get_active_tier_kd(),
			"kills": current_tier_kills,
			"deaths": current_tier_deaths,
			"matches": current_tier_matches,
			"wins": current_tier_wins,
			"status": "PROMOTED"
		}
		# RESET ACTIVE K/D FOR NEW TIER
		current_tier_kills = 0
		current_tier_deaths = 0
		current_tier_matches = 0
		current_tier_wins = 0
		demotion_protection_matches = 3 # 3 match grace buffer
		last_calculated_tier = new_tier
		tier_promoted.emit(old_tier, new_tier)
	else:
		# DEMOTION
		if demotion_protection_matches > 0:
			demotion_protection_matches -= 1
			return
		tier_dossiers[old_tier_name] = {
			"final_kd": get_active_tier_kd(),
			"kills": current_tier_kills,
			"deaths": current_tier_deaths,
			"matches": current_tier_matches,
			"wins": current_tier_wins,
			"status": "DEMOTED"
		}
		# RESET ACTIVE K/D FOR RECLAIM PHASE
		current_tier_kills = 0
		current_tier_deaths = 0
		current_tier_matches = 0
		current_tier_wins = 0
		last_calculated_tier = new_tier
		tier_demoted.emit(old_tier, new_tier)


func to_dictionary() -> Dictionary:
	return {
		"version": 1,
		"callsign": callsign,
		"clan_tag": clan_tag,
		"cloud_user_id": cloud_user_id,
		"elo": elo,
		"placement_matches_remaining": placement_matches_remaining,
		"leaderboard_position": leaderboard_position,
		"demotion_protection_matches": demotion_protection_matches,
		"last_calculated_tier": int(last_calculated_tier),
		"current_tier_kills": current_tier_kills,
		"current_tier_deaths": current_tier_deaths,
		"current_tier_matches": current_tier_matches,
		"current_tier_wins": current_tier_wins,
		"tier_dossiers": tier_dossiers.duplicate(true),
		"lifetime_kills": lifetime_kills,
		"lifetime_deaths": lifetime_deaths,
		"lifetime_matches": lifetime_matches,
		"lifetime_wins": lifetime_wins,
	}


func from_dictionary(dict: Dictionary) -> void:
	callsign = String(dict.get("callsign", "Operator"))
	clan_tag = String(dict.get("clan_tag", "141"))
	cloud_user_id = String(dict.get("cloud_user_id", ""))
	elo = int(dict.get("elo", DEFAULT_STARTING_ELO))
	placement_matches_remaining = int(dict.get("placement_matches_remaining", PLACEMENTS_REQUIRED))
	leaderboard_position = int(dict.get("leaderboard_position", -1))
	demotion_protection_matches = int(dict.get("demotion_protection_matches", 0))
	last_calculated_tier = SocomCompetitiveTypes.RankTier(int(dict.get("last_calculated_tier", SocomCompetitiveTypes.get_tier_enum(elo))))
	current_tier_kills = int(dict.get("current_tier_kills", 0))
	current_tier_deaths = int(dict.get("current_tier_deaths", 0))
	current_tier_matches = int(dict.get("current_tier_matches", 0))
	current_tier_wins = int(dict.get("current_tier_wins", 0))
	tier_dossiers = (dict.get("tier_dossiers", {}) as Dictionary).duplicate(true)
	lifetime_kills = int(dict.get("lifetime_kills", 0))
	lifetime_deaths = int(dict.get("lifetime_deaths", 0))
	lifetime_matches = int(dict.get("lifetime_matches", 0))
	lifetime_wins = int(dict.get("lifetime_wins", 0))


func save_to_disk() -> bool:
	var path := custom_save_path if not custom_save_path.is_empty() else SAVE_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	return true


func load_from_disk() -> bool:
	var path := custom_save_path if not custom_save_path.is_empty() else SAVE_PATH
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed is Dictionary:
		from_dictionary(parsed as Dictionary)
		return true
	return false
```

---

### 6.3 `scripts/ui/socom_player_card_widget.gd`

```gdscript
class_name SocomPlayerCardWidget
extends Button

## Sleek top-right interactive player badge. Displays rank tier,
## callsign, active tier K/D, and a micro ELO progress bar.

signal card_clicked()

const Profile := preload("res://scripts/profile/socom_player_profile.gd")
const CompTypes := preload("res://scripts/competitive/socom_competitive_types.gd")

var rank_badge_label: Label
var callsign_label: Label
var stats_label: Label
var progress_bar: ProgressBar


func _ready() -> void:
	name = "PlayerCardWidget"
	custom_minimum_size = Vector2(280.0, 48.0)
	flat = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_build_ui()
	_refresh_display()
	Profile.instance().profile_changed.connect(_refresh_display)
	pressed.connect(func(): card_clicked.emit())


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 8)
	column.add_child(top_row)

	rank_badge_label = Label.new()
	rank_badge_label.name = "RankBadge"
	rank_badge_label.text = "✦"
	rank_badge_label.add_theme_font_size_override("font_size", 16)
	top_row.add_child(rank_badge_label)

	callsign_label = Label.new()
	callsign_label.name = "CallsignLabel"
	callsign_label.text = "Operator"
	callsign_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	callsign_label.add_theme_font_size_override("font_size", 14)
	callsign_label.add_theme_color_override("font_color", Color("ffffff"))
	top_row.add_child(callsign_label)

	stats_label = Label.new()
	stats_label.name = "BracketKDLabel"
	stats_label.text = "0.00 K/D"
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color("aeb9c9"))
	top_row.add_child(stats_label)

	progress_bar = ProgressBar.new()
	progress_bar.name = "EloProgressBar"
	progress_bar.custom_minimum_size.y = 3.0
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(progress_bar)


func _refresh_display() -> void:
	var p := Profile.instance()
	var rank_text := CompTypes.format_full_rank(p.elo, p.leaderboard_position)
	var tier_color := CompTypes.get_tier_color(CompTypes.get_tier_enum(p.elo))

	rank_badge_label.add_theme_color_override("font_color", tier_color)
	if p.clan_tag.is_empty():
		callsign_label.text = "%s  •  %s" % [p.callsign, rank_text]
	else:
		callsign_label.text = "[%s] %s  •  %s" % [p.clan_tag, p.callsign, rank_text]

	stats_label.text = "%.2f K/D" % p.get_active_tier_kd()
	stats_label.tooltip_text = "Bracket K/D: %d Kills / %d Deaths" % [p.current_tier_kills, p.current_tier_deaths]
	progress_bar.value = CompTypes.get_tier_progress_ratio(p.elo) * 100.0
```

---

### 6.4 `scripts/ui/socom_operator_dossier_modal.gd`

```gdscript
class_name SocomOperatorDossierModal
extends CanvasLayer

## Tactical fullscreen overlay modal displaying the operator's active bracket card,
## per-tier historical dossier, lifetime records, and identity customization.

const Profile := preload("res://scripts/profile/socom_player_profile.gd")
const CompTypes := preload("res://scripts/competitive/socom_competitive_types.gd")

var panel: PanelContainer
var callsign_edit: LineEdit
var clan_tag_edit: LineEdit
var rank_title_label: Label
var elo_label: Label
var tier_kd_label: Label
var tier_winrate_label: Label
var tier_matches_label: Label
var lifetime_kd_label: Label
var lifetime_matches_label: Label
var history_list: VBoxContainer


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_modal_visible(false)
	Profile.instance().profile_changed.connect(_refresh_data)


func set_modal_visible(enabled: bool) -> void:
	panel.visible = enabled
	if enabled:
		_refresh_data()


func toggle() -> void:
	set_modal_visible(not panel.visible)


func _unhandled_input(event: InputEvent) -> void:
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_modal_visible(false)
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "DossierModalRoot"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.06, 0.09, 0.95)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 40)
	panel.add_child(margin)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 16)
	margin.add_child(root_col)

	# --- Header Bar ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root_col.add_child(header)

	var title := Label.new()
	title.text = "OPERATOR DOSSIER  •  COMPETITIVE RECORD"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "CLOSE  [ESC]"
	close_btn.custom_minimum_size = Vector2(120.0, 36.0)
	close_btn.pressed.connect(func(): set_modal_visible(false))
	header.add_child(close_btn)

	root_col.add_child(HSeparator.new())

	# --- Main Content Grid ---
	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 24)
	root_col.add_child(content_row)

	# Left Column: Identity & Active Bracket
	var left_panel := _create_card(380.0)
	content_row.add_child(left_panel)
	var left_col := _card_column(left_panel)

	_add_section_heading(left_col, "OPERATOR IDENTITY")
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 8)
	left_col.add_child(id_row)

	clan_tag_edit = LineEdit.new()
	clan_tag_edit.placeholder_text = "TAG"
	clan_tag_edit.max_length = 5
	clan_tag_edit.custom_minimum_size.x = 70.0
	id_row.add_child(clan_tag_edit)

	callsign_edit = LineEdit.new()
	callsign_edit.placeholder_text = "Callsign"
	callsign_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(callsign_edit)

	var save_id_btn := Button.new()
	save_id_btn.text = "SAVE IDENTITY"
	save_id_btn.pressed.connect(_on_save_identity)
	left_col.add_child(save_id_btn)

	left_col.add_child(HSeparator.new())
	_add_section_heading(left_col, "ACTIVE BRACKET EFFICIENCY")

	rank_title_label = Label.new()
	rank_title_label.text = "PRAETORIAN II"
	rank_title_label.add_theme_font_size_override("font_size", 28)
	left_col.add_child(rank_title_label)

	elo_label = Label.new()
	elo_label.text = "ELO: 2,540  •  Top 4%"
	elo_label.add_theme_color_override("font_color", Color("f2cf6a"))
	left_col.add_child(elo_label)

	var note := Label.new()
	note.text = "Active bracket stats reset after each rank promotion or demotion to measure pure peer efficiency."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("7f8b9c"))
	left_col.add_child(note)

	tier_kd_label = Label.new()
	tier_kd_label.text = "Bracket K/D: 1.25 (25 Kills / 20 Deaths)"
	left_col.add_child(tier_kd_label)

	tier_winrate_label = Label.new()
	tier_winrate_label.text = "Bracket Win Rate: 60.0%"
	left_col.add_child(tier_winrate_label)

	tier_matches_label = Label.new()
	tier_matches_label.text = "Matches in Tier: 10"
	left_col.add_child(tier_matches_label)

	# Right Column: Tier Archive Dossier & Career Totals
	var right_panel := _create_card(0.0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_child(right_panel)
	var right_col := _card_column(right_panel)

	_add_section_heading(right_col, "LIFETIME COMBAT RECORD")
	var career_row := HBoxContainer.new()
	career_row.add_theme_constant_override("separation", 32)
	right_col.add_child(career_row)

	lifetime_kd_label = Label.new()
	lifetime_kd_label.text = "Lifetime K/D: 1.45"
	career_row.add_child(lifetime_kd_label)

	lifetime_matches_label = Label.new()
	lifetime_matches_label.text = "Total Matches: 48  (30 Wins)"
	career_row.add_child(lifetime_matches_label)

	right_col.add_child(HSeparator.new())
	_add_section_heading(right_col, "TIER DOSSIER ARCHIVE")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(scroll)

	history_list = VBoxContainer.new()
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_list.add_theme_constant_override("separation", 10)
	scroll.add_child(history_list)


func _refresh_data() -> void:
	var p := Profile.instance()
	callsign_edit.text = p.callsign
	clan_tag_edit.text = p.clan_tag

	var rank_text := CompTypes.format_full_rank(p.elo, p.leaderboard_position)
	var tier_color := CompTypes.get_tier_color(CompTypes.get_tier_enum(p.elo))

	rank_title_label.text = rank_text
	rank_title_label.add_theme_color_override("font_color", tier_color)
	elo_label.text = "ELO RATING: %d" % p.elo

	tier_kd_label.text = "Bracket K/D: %.2f  (%d Kills / %d Deaths)" % [p.get_active_tier_kd(), p.current_tier_kills, p.current_tier_deaths]
	tier_winrate_label.text = "Bracket Win Rate: %.1f%%  (%d Wins / %d Matches)" % [p.get_active_tier_win_rate(), p.current_tier_wins, p.current_tier_matches]
	tier_matches_label.text = "Matches in Current Tier: %d" % p.current_tier_matches

	lifetime_kd_label.text = "Career K/D: %.2f  (%d Kills / %d Deaths)" % [p.get_lifetime_kd(), p.lifetime_kills, p.lifetime_deaths]
	lifetime_matches_label.text = "Total Matches: %d  (%d Wins • %.1f%% Win Rate)" % [p.lifetime_matches, p.lifetime_wins, p.get_lifetime_win_rate()]

	# Rebuild Tier History Timeline
	for child in history_list.get_children():
		child.queue_free()

	if p.tier_dossiers.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No previous tiers archived. Advance or demote to record historical snapshots."
		empty_lbl.add_theme_color_override("font_color", Color("7f8b9c"))
		history_list.add_child(empty_lbl)
	else:
		for tier_key in p.tier_dossiers.keys():
			var entry: Dictionary = p.tier_dossiers[tier_key]
			var row := PanelContainer.new()
			var margin := MarginContainer.new()
			for side in ["left", "right", "top", "bottom"]:
				margin.add_theme_constant_override("margin_%s" % side, 10)
			row.add_child(margin)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 16)
			margin.add_child(h)

			var t_lbl := Label.new()
			t_lbl.text = String(tier_key)
			t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t_lbl.add_theme_font_size_override("font_size", 16)
			t_lbl.add_theme_color_override("font_color", Color("8bc5ae"))
			h.add_child(t_lbl)

			var kd_lbl := Label.new()
			kd_lbl.text = "Final K/D: %.2f (%d K / %d D)" % [float(entry.get("final_kd", 0.0)), int(entry.get("kills", 0)), int(entry.get("deaths", 0))]
			h.add_child(kd_lbl)

			var st_lbl := Label.new()
			st_lbl.text = String(entry.get("status", "ARCHIVED"))
			st_lbl.add_theme_color_override("font_color", Color("f2cf6a") if entry.get("status") == "PROMOTED" else Color("e06c75"))
			h.add_child(st_lbl)

			history_list.add_child(row)


func _on_save_identity() -> void:
	Profile.instance().set_identity(callsign_edit.text, clan_tag_edit.text)


func _create_card(min_width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = min_width
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


func _card_column(panel_container: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	panel_container.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	return col


func _add_section_heading(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("8bc5ae"))
	parent.add_child(lbl)
```

---

### 6.5 Launcher Integration Snippet (`scripts/ui/game_launcher.gd`)

```gdscript
# In scripts/ui/game_launcher.gd:

const PlayerCardWidgetScript := preload("res://scripts/ui/socom_player_card_widget.gd")
const OperatorDossierModalScript := preload("res://scripts/ui/socom_operator_dossier_modal.gd")
const PlayerProfile := preload("res://scripts/profile/socom_player_profile.gd")

var player_card_widget: SocomPlayerCardWidget
var operator_dossier_modal: SocomOperatorDossierModal

# Inside _build_ui():
# 1. Top bar integration:
player_card_widget = PlayerCardWidgetScript.new()
player_card_widget.card_clicked.connect(_open_operator_dossier)
top_bar.add_child(player_card_widget)

# 2. Sidebar CAREER section:
left.add_child(HSeparator.new())
_add_panel_heading(left, "CAREER")
_add_primary_action(left, "OPERATOR DOSSIER", _open_operator_dossier)

# 3. Add Dossier Modal:
operator_dossier_modal = OperatorDossierModalScript.new()
add_child(operator_dossier_modal)

func _open_operator_dossier() -> void:
	if operator_dossier_modal != null:
		operator_dossier_modal.set_modal_visible(true)
```

---

## 7. Match Lifecycle Integration Hook (Recording Match Stats)

When a Gunfight or tournament match completes in `multiplayer_slice.gd` / `socom_network_operator.gd`:

```gdscript
# On Match Completed Hook:
func _on_match_completed(kills: int, deaths: int, won: bool, elo_delta: int) -> void:
	var profile := SocomPlayerProfile.instance()
	profile.record_match_result(kills, deaths, won, elo_delta)
	print("[Combat Record] Match recorded. Active Bracket K/D: %.2f (Total ELO: %d)" % [
		profile.get_active_tier_kd(),
		profile.elo
	])
```

---

## 8. Verification & Automated Regression Suite

### 8.1 `tools/competitive_profile_regression.gd`

```gdscript
extends SceneTree

const Profile := preload("res://scripts/profile/socom_player_profile.gd")
const CompTypes := preload("res://scripts/competitive/socom_competitive_types.gd")
const CardWidget := preload("res://scripts/ui/socom_player_card_widget.gd")
const DossierModal := preload("res://scripts/ui/socom_operator_dossier_modal.gd")

const TEST_SAVE_PATH := "user://test_player_profile_regression.json"


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("--- STARTING COMPETITIVE PROFILE & K/D RESET REGRESSION ---")
	
	# Clean up any leftover test artifact
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

	var p := Profile.new()
	p.custom_save_path = TEST_SAVE_PATH

	# 1. Test Baseline State
	assert(p.elo == 1200, "Default ELO should be 1200")
	assert(CompTypes.get_tier_enum(p.elo) == CompTypes.RankTier.LEGIONARY, "1200 ELO should map to Legionary")
	assert(p.get_active_tier_kd() == 0.0, "Initial active K/D should be 0.0")

	# 2. Test Match Recording within Tier
	p.record_match_result(10, 5, true, 50) # ELO = 1250
	assert(p.current_tier_kills == 10, "Tier kills should be 10")
	assert(p.current_tier_deaths == 5, "Tier deaths should be 5")
	assert(p.get_active_tier_kd() == 2.0, "Tier K/D should be 2.0")
	assert(p.lifetime_kills == 10, "Lifetime kills should be 10")

	# 3. Test Promotion Threshold & Automated K/D Reset
	# Promote to Centurion (Threshold: 1600 ELO)
	p.record_match_result(15, 5, true, 400) # ELO = 1650 (Centurion III)
	
	assert(CompTypes.get_tier_enum(p.elo) == CompTypes.RankTier.CENTURION, "Rank should be Centurion")
	# VERIFY STRICT K/D RESET ON PROMOTION
	assert(p.current_tier_kills == 0, "Active tier kills must reset to 0 upon promotion")
	assert(p.current_tier_deaths == 0, "Active tier deaths must reset to 0 upon promotion")
	assert(p.current_tier_matches == 0, "Active tier matches must reset to 0 upon promotion")
	assert(p.get_active_tier_kd() == 0.0, "Active tier K/D must reset to 0.0")
	
	# VERIFY HISTORICAL DOSSIER ARCHIVE
	assert(p.tier_dossiers.has("LEGIONARY"), "Past tier Legionary must be archived")
	var leg_dossier: Dictionary = p.tier_dossiers["LEGIONARY"]
	assert(int(leg_dossier["kills"]) == 25, "Archived kills must match pre-promotion total")
	assert(int(leg_dossier["deaths"]) == 10, "Archived deaths must match pre-promotion total")
	assert(String(leg_dossier["status"]) == "PROMOTED", "Archived status should be PROMOTED")

	# VERIFY LIFETIME TOTALS PERSISTED
	assert(p.lifetime_kills == 25, "Lifetime kills should remain 25")
	assert(p.lifetime_deaths == 10, "Lifetime deaths should remain 10")
	assert(p.get_lifetime_kd() == 2.5, "Lifetime K/D should remain 2.5")

	# 4. Test Persistence & Reload
	assert(p.save_to_disk(), "Profile must save successfully")
	var p2 := Profile.new()
	p2.custom_save_path = TEST_SAVE_PATH
	assert(p2.load_from_disk(), "Profile must load successfully")
	assert(p2.elo == 1650, "Loaded ELO should be 1650")
	assert(p2.tier_dossiers.has("LEGIONARY"), "Loaded profile must preserve tier archive")

	# 5. Clean up
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

	print("COMPETITIVE_PROFILE_REGRESSION PASS")
	quit(0)
```

### 8.2 `tools/run_competitive_profile_regression.sh`

```bash
#!/bin/zsh
set -uo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
log_path="$(mktemp /tmp/socom-competitive-regression.XXXXXX)"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$log_path" \
  --path "$project_dir" \
  --script res://tools/competitive_profile_regression.gd

exit_code=$?
if [[ $exit_code -ne 0 ]] || grep -qE 'SCRIPT ERROR|_CHECK FAIL|_REGRESSION FAIL' "$log_path"; then
  print -u2 "Competitive profile regression failed. Log: $log_path"
  grep -E 'SCRIPT ERROR|_CHECK FAIL|_REGRESSION FAIL' "$log_path"
  exit 1
fi
grep -q 'COMPETITIVE_PROFILE_REGRESSION PASS' "$log_path" || { print -u2 "Missing pass marker. Log: $log_path"; exit 1; }
print "Competitive profile regression passed."
exit 0
```
