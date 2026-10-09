/**
 @name: 项目构建与文档
 @Descripttion: 维护 config.rs 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: windows/codenotch/src/config.rs
 */
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

/// The Mac's notch sizes, as multiples of the designed size: Small, Medium, Large.
pub const SIZES: [f64; 3] = [0.8, 1.0, 1.25];

/// The nearest of `SIZES`, so a scale saved by the old 40–100 % slider still lands on a size that
/// exists. 0.9, halfway between Small and Medium, counts as Medium.
pub fn snap_scale(scale: f64) -> f64 {
    if scale < 0.9 {
        SIZES[0]
    } else if scale < 1.125 || !scale.is_finite() {
        SIZES[1]
    } else {
        SIZES[2]
    }
}

/// One half of the tray icon, or one ring on the notch: which provider. It shows that provider's
/// ring, so the tray and the notch can never disagree. (A `window` key from older builds is ignored.)
/// One ring on the notch: which provider. (A `window` key from older builds is ignored.)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TraySlot {
    pub provider: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(default = "default_port")]
    pub port: u16,
    /// "auto" | "zh" | "en" | "ja" | "ko" | "ru" | "uk"
    #[serde(default = "default_lang")]
    pub lang: String,
    #[serde(default)]
    pub bar_x: Option<i32>,
    #[serde(default)]
    pub bar_y: Option<i32>,
    /// Logical width of the bar (wheel-adjustable, 220-520); None = default 360
    #[serde(default)]
    pub bar_w: Option<u32>,
    /// Allow dragging + wheel resizing (tray toggle, off by default to prevent accidental drags)
    #[serde(default)]
    pub drag_enabled: bool,
    /// Vertical position of the notch: the window centre as a fraction of the primary monitor's height (0 = top, 1 = bottom), default 0.5; saved after a drag
    /// Position of the notch along its edge: the window centre as a fraction of the monitor's height
    /// (left/right edges) or width (top/bottom edges), 0 = top/left, 1 = bottom/right, default 0.5;
    /// saved after a drag. Named `notch_y` from when the right edge was the only one, so an existing
    /// config keeps its place.
    #[serde(default = "default_notch_y", skip_serializing)]
    pub notch_y: f64,
    /// Position along each edge, replacing the old shared `notch_y` value.
    #[serde(default)]
    pub notch_along: BTreeMap<String, f64>,
    /// Which screen edge the notch is pinned to: "right" (the default), "left", "top" or "bottom".
    #[serde(default = "default_notch_edge")]
    pub notch_edge: String,
    /// Which monitor the notch lives on, by the system's device name (`\\.\DISPLAY2`). None, or a
    /// name no longer attached, means the primary monitor — so unplugging a screen cannot strand it.
    #[serde(default)]
    pub notch_monitor: Option<String>,
    /// Notch size as a multiple of the designed size, one of `SIZES`. The whole notch scales: the
    /// window grows and its WebView zooms, so the rings, text and hover card keep their proportions.
    #[serde(default = "default_scale")]
    pub scale: f64,
    /// Where the weekly limit gets a ring of its own: "off", "inside" or "outside".
    #[serde(default = "default_weekly_ring")]
    pub weekly_ring: String,
    /// true = the weekly ring's track and its own arc are drawn in small dashes rather than a
    /// solid line, as the Mac's "Dashed weekly ring" switch does. Only means anything while
    /// `weekly_ring` is not "off". Off by default: an extra visual change nobody asked for.
    #[serde(default)]
    pub weekly_ring_dashed: bool,
    /// How usage colours transition: "hard_step" or "ramp".
    #[serde(default = "default_color_transition")]
    pub color_transition: String,
    /// Where a ring turns from Ample to Watch, as a fraction of the limit. The Mac's own default.
    #[serde(default = "default_watch_limit")]
    pub watch_limit: f64,
    /// Where a ring turns from Watch to Critical, as a fraction of the limit. Kept above
    /// `watch_limit` by `clamp_watch_limit`/`clamp_critical_limit`, the same order the Mac's own
    /// `didSet` pair enforces.
    #[serde(default = "default_critical_limit")]
    pub critical_limit: f64,
    /// Which appearance the pages draw in: "system", "light" or "dark".
    #[serde(default = "default_theme", deserialize_with = "deserialize_theme_or_system")]
    pub theme: String,
    /// What the tray icon draws: "off" (the plain mark, the previous behaviour and the default),
    /// "numbers" (up to two readings as digits) or "bars" (a column per reading).
    #[serde(default = "default_tray_mode")]
    pub tray_mode: String,
    /// Which providers the tray icon covers, in the order they are drawn. Ids match the page:
    /// "claude", "codex", "cursor", "gemini". Superseded by `tray_slots`; kept so an existing
    /// config still upgrades cleanly, and migrated in `load()`.
    #[serde(default = "default_tray_providers")]
    pub tray_providers: Vec<String>,
    /// What each part of the tray icon shows, in drawing order: the first entry is the top half of
    /// the digit layout, the second the bottom half, and the bar layout uses them all in order.
    #[serde(default)]
    pub tray_slots: Vec<TraySlot>,
    /// Which providers the notch itself shows, in order. Empty means every provider that has
    /// something to report — the original behaviour, and the default. Superseded by `notch_slots`,
    /// kept so an existing config migrates cleanly.
    #[serde(default)]
    pub notch_providers: Vec<String>,
    /// Which providers get a ring on the notch, in order. An empty list means every provider.
    #[serde(default)]
    pub notch_slots: Vec<TraySlot>,
    /// Antigravity's lane on the ring, as the Mac app's "Notch reads": "automatic", "5h" or "weekly"
    #[serde(default = "default_antigravity_limit")]
    pub antigravity_limit: String,
    /// The model family that choice looks at, as the Mac app's "Model data": "gemini" or "3p"
    #[serde(default = "default_antigravity_model")]
    pub antigravity_model: String,
    #[serde(default)]
    pub glm_notch_fixed: bool,
    #[serde(default)]
    pub opencode_notch_fixed: bool,
    /// The same one-shot migration for the GitHub Copilot ring.
    #[serde(default)]
    pub copilot_notch_fixed: bool,
    /// false = the pill is kept off the screen edge entirely; the tray icon is then the only way in
    #[serde(default = "yes")]
    pub notch_visible: bool,
    /// true = the Mac's Show on hover: the notch rests as a small pill at the edge and opens when the
    /// pointer reaches it. Only means anything while `notch_visible` is true. The Mac's default, and a
    /// fresh install's; a config written before this existed keeps the always-open notch it had (see
    /// `load`), so nobody's notch starts folding on an update.
    #[serde(default = "yes")]
    pub notch_on_hover: bool,
    /// false = the tray icon is hidden. Refused while the notch is also hidden, because that would
    /// leave the app running with no way to reach it.
    #[serde(default = "yes")]
    pub tray_visible: bool,
    /// Show a temporary card when any provider (Claude, Codex, Cursor, …) renews a used quota window.
    #[serde(default = "yes")]
    pub reset_notifications: bool,
    /// false = the reset card above appears silently, with no notification sound.
    #[serde(default = "yes")]
    pub reset_notification_sound: bool,
    /// false = no arc above the notch to carry it by. Nothing is lost: Appearance → Edge moves it too.
    #[serde(default = "yes")]
    pub show_move_handle: bool,
    /// 设置入口可独立隐藏，移动入口继续遵循 show_move_handle。
    #[serde(default = "yes")]
    pub show_settings_handle: bool,
    /// true = the folded pill follows what is behind it, which means reading the screen beside it
    /// (backdrop.rs). Opt-in for that reason; off, the pill takes Theme's colour.
    #[serde(default)]
    pub adaptive_pill: bool,
}

fn default_notch_y() -> f64 {
    0.5
}
fn default_notch_edge() -> String {
    "right".into()
}

/// The four edges, in the order Settings lists them.
pub const EDGES: [&str; 4] = ["left", "right", "top", "bottom"];

/// An unreadable edge means the right-hand one, the layout every earlier build used.
pub fn edge_or_right(value: &str) -> String {
    if EDGES.contains(&value) {
        value.to_string()
    } else {
        "right".into()
    }
}

/// True for the edges the notch stands upright on (the pill is a column); false for top and bottom,
/// where it lies flat (the pill is a row) and the window's width and height swap.
pub fn edge_is_vertical(edge: &str) -> bool {
    matches!(edge, "left" | "right")
}

fn keep_open_on_upgrade(cfg: &mut Config, raw: Option<&str>) {
    let saved_without_it = raw
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .is_some_and(|v| v.get("notch_on_hover").is_none());
    if saved_without_it {
        cfg.notch_on_hover = false;
    }
}

fn carry_shared_position(cfg: &mut Config) {
    if cfg.notch_along.is_empty() && (cfg.notch_y - 0.5).abs() > f64::EPSILON {
        let edge = edge_or_right(&cfg.notch_edge);
        cfg.set_along(&edge, cfg.notch_y);
    }
}

impl Config {
    pub fn along(&self, edge: &str) -> f64 {
        self.notch_along.get(edge).copied().unwrap_or(0.5).clamp(0.0, 1.0)
    }

    pub fn set_along(&mut self, edge: &str, along: f64) {
        self.notch_along.insert(edge.to_string(), along.clamp(0.0, 1.0));
    }
}

fn default_scale() -> f64 {
    1.0
}
fn default_weekly_ring() -> String {
    "off".into()
}

fn default_color_transition() -> String {
    "hard_step".into()
}
pub fn default_watch_limit() -> f64 {
    0.5
}
pub fn default_critical_limit() -> f64 {
    0.8
}

/// Keeps `watch_limit` at least 0.01 below `critical_limit`, the same range the Mac's own slider
/// (0.01...0.99, tightened against the sibling) allows.
pub fn clamp_watch_limit(watch: f64, critical: f64) -> f64 {
    watch.clamp(0.01, (critical - 0.01).max(0.01))
}

/// Keeps `critical_limit` at least 0.01 above `watch_limit`, mirroring `clamp_watch_limit`.
pub fn clamp_critical_limit(critical: f64, watch: f64) -> f64 {
    critical.clamp((watch + 0.01).min(1.0), 1.0)
}
fn default_theme() -> String {
    "system".into()
}

/// Invalid values follow Windows so a hand-edited config cannot disable the rest of the settings.
pub fn theme_or_system(value: &str) -> String {
    match value {
        "light" | "dark" => value.to_string(),
        _ => default_theme(),
    }
}

fn deserialize_theme_or_system<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Ok(Option::<serde_json::Value>::deserialize(deserializer)
        .ok()
        .flatten()
        .and_then(|value| value.as_str().map(theme_or_system))
        .unwrap_or_else(default_theme))
}

pub fn color_transition_or_step(value: &str) -> String {
    match value {
        "ramp" => value.to_string(),
        _ => default_color_transition(),
    }
}

/// A second arc changes how every reading looks, so an unreadable value means off rather than a
/// guess at what was meant.
pub fn weekly_ring_or_off(value: &str) -> String {
    match value {
        "inside" | "outside" => value.to_string(),
        _ => default_weekly_ring(),
    }
}
fn yes() -> bool {
    true
}
fn default_antigravity_limit() -> String {
    "automatic".into()
}
fn default_antigravity_model() -> String {
    "gemini".into()
}
fn default_tray_mode() -> String {
    "numbers".into()
}
fn default_tray_providers() -> Vec<String> {
    vec!["claude".into(), "codex".into()]
}

fn default_port() -> u16 {
    48666
}
fn default_lang() -> String {
    "auto".into()
}

impl Default for Config {
    fn default() -> Self {
        Self {
            port: default_port(),
            lang: default_lang(),
            bar_x: None,
            bar_y: None,
            bar_w: None,
            drag_enabled: false,
            notch_y: default_notch_y(),
            notch_along: BTreeMap::new(),
            notch_edge: default_notch_edge(),
            notch_monitor: None,
            scale: default_scale(),
            weekly_ring: default_weekly_ring(),
            weekly_ring_dashed: false,
            color_transition: default_color_transition(),
            watch_limit: default_watch_limit(),
            critical_limit: default_critical_limit(),
            theme: default_theme(),
            tray_mode: default_tray_mode(),
            tray_providers: default_tray_providers(),
            tray_slots: Vec::new(), // filled in by load(), from tray_providers
            notch_providers: Vec::new(), // empty = show them all
            notch_slots: Vec::new(),     // filled in by load(), from notch_providers
            antigravity_limit: default_antigravity_limit(),
            antigravity_model: default_antigravity_model(),
            glm_notch_fixed: true,
            opencode_notch_fixed: true,
            copilot_notch_fixed: true,
            notch_visible: true,
            notch_on_hover: true,
            tray_visible: true,
            reset_notifications: true,
            reset_notification_sound: true,
            show_move_handle: true,
            show_settings_handle: true,
            adaptive_pill: false,
        }
    }
}

pub fn config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("codenotch")
        .join("config.json")
}

pub fn load() -> Config {
    let path = config_path();
    let raw = std::fs::read_to_string(&path).ok();
    let mut cfg: Config = raw
        .as_deref()
        .and_then(|t| serde_json::from_str(t).ok())
        .unwrap_or_default();
    keep_open_on_upgrade(&mut cfg, raw.as_deref());

    // Discoverability without surprising anyone. `default_tray_mode` gives a NEW install the
    // numbers icon, but serde applies that same default to an EXISTING config that simply predates
    // the setting — which would silently change the tray icon of everyone who upgrades. So an
    // existing file with no `tray_mode` key is pinned to the plain mark it already has; only a
    // machine with no config at all gets the new default.
    let upgrading = raw
        .as_deref()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .map(|v| v.get("tray_mode").is_none())
        .unwrap_or(false);
    if upgrading {
        cfg.tray_mode = "off".into();
    }

    // Migration: before slots existed the icon was a plain provider list, one reading each. That
    // is exactly a list of slots, so nobody's choice is lost and nobody has to reconfigure anything.
    if cfg.tray_slots.is_empty() {
        cfg.tray_slots = cfg
            .tray_providers
            .iter()
            .map(|p| TraySlot { provider: p.clone() })
            .collect();
    }

    // Same migration for the notch.
    if cfg.notch_slots.is_empty() {
        cfg.notch_slots = cfg
            .notch_providers
            .iter()
            .map(|p| TraySlot { provider: p.clone() })
            .collect();
    }

    carry_shared_position(&mut cfg);
    migrate_glm_notch(&mut cfg, &raw);
    migrate_opencode_notch(&mut cfg, &raw);
    // And for GitHub Copilot.
    migrate_copilot_notch(&mut cfg, &raw);

    // Both hidden would leave the app unreachable: no pill, no tray icon, no way to open settings.
    if !cfg.notch_visible && !cfg.tray_visible {
        cfg.tray_visible = true;
    }

    // The old slider's 40–100 %, or a hand-edited file, lands on one of the three sizes
    cfg.scale = snap_scale(cfg.scale);
    cfg.weekly_ring = weekly_ring_or_off(&cfg.weekly_ring);
    cfg.color_transition = color_transition_or_step(&cfg.color_transition);
    cfg.theme = theme_or_system(&cfg.theme);
    // A stored pair that crossed over (or predates this setting) is repaired the same order the
    // Mac's own init does: critical first, then watch below it.
    cfg.critical_limit = cfg.critical_limit.clamp(0.02, 1.0);
    cfg.watch_limit = clamp_watch_limit(cfg.watch_limit, cfg.critical_limit);
    cfg
}

fn migrate_glm_notch(cfg: &mut Config, raw: &Option<String>) {
    let predates = raw
        .as_deref()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .map(|v| v.get("glm_notch_fixed").is_none())
        .unwrap_or(false);
    if predates {
        if !cfg.notch_slots.is_empty() && !cfg.notch_slots.iter().any(|s| s.provider == "glm") {
            cfg.notch_slots.push(TraySlot { provider: "glm".into() });
        }
        cfg.glm_notch_fixed = true;
    }
}

fn migrate_opencode_notch(cfg: &mut Config, raw: &Option<String>) {
    let predates = raw
        .as_deref()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .map(|v| v.get("opencode_notch_fixed").is_none())
        .unwrap_or(false);
    if predates {
        if !cfg.notch_slots.is_empty() && !cfg.notch_slots.iter().any(|s| s.provider == "opencode") {
            cfg.notch_slots.push(TraySlot { provider: "opencode".into() });
        }
        cfg.opencode_notch_fixed = true;
    }
}

fn migrate_copilot_notch(cfg: &mut Config, raw: &Option<String>) {
    let predates = raw
        .as_deref()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(t).ok())
        .map(|v| v.get("copilot_notch_fixed").is_none())
        .unwrap_or(false);
    if !predates {
        return;
    }
    if !cfg.notch_slots.is_empty() && !cfg.notch_slots.iter().any(|s| s.provider == "copilot") {
        cfg.notch_slots.push(TraySlot { provider: "copilot".into() });
    }
    cfg.copilot_notch_fixed = true;
}

pub fn save(cfg: &Config) {
    let path = config_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(txt) = serde_json::to_string_pretty(cfg) {
        let _ = std::fs::write(path, txt);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        carry_shared_position, clamp_critical_limit, clamp_watch_limit, color_transition_or_step,
        keep_open_on_upgrade, snap_scale, theme_or_system, weekly_ring_or_off, Config,
    };

    #[test]
    fn reset_switches_default_on_and_round_trip_without_changing_other_settings() {
        let old: Config = serde_json::from_str(r#"{"notch_visible":false,"theme":"light"}"#).unwrap();
        assert!(old.reset_notifications);
        assert!(old.reset_notification_sound);
        assert!(!old.notch_visible);
        assert_eq!(old.theme, "light");
        let chosen = Config { reset_notifications: false, reset_notification_sound: false, ..old };
        let saved = serde_json::to_string(&chosen).unwrap();
        let restored: Config = serde_json::from_str(&saved).unwrap();
        assert!(!restored.reset_notifications);
        assert!(!restored.reset_notification_sound);
        assert!(!restored.notch_visible);
        assert_eq!(restored.theme, "light");
    }

    /// Show on hover is the Mac's default, so a fresh install gets it — but an update must not start
    /// folding a notch whose owner has only ever known it open.
    #[test]
    fn only_a_fresh_install_starts_on_hover() {
        let mut fresh = Config::default();
        keep_open_on_upgrade(&mut fresh, None);
        assert!(fresh.notch_on_hover, "no config file: the Mac's default");

        let mut upgraded = Config::default();
        keep_open_on_upgrade(&mut upgraded, Some(r#"{"notch_visible":true}"#));
        assert!(!upgraded.notch_on_hover, "saved before the setting existed: stays open");

        for chosen in [true, false] {
            let mut c = Config { notch_on_hover: chosen, ..Default::default() };
            keep_open_on_upgrade(&mut c, Some(&format!(r#"{{"notch_on_hover":{chosen}}}"#)));
            assert_eq!(c.notch_on_hover, chosen, "a choice already made is kept");
        }
    }

    /// The Mac keeps one offset per edge; sliding the notch along one must not move it on another.
    #[test]
    fn each_edge_keeps_its_own_place() {
        let mut c = Config::default();
        assert_eq!(c.along("right"), 0.5, "an edge never slid along is centred");
        c.set_along("right", 0.2);
        assert_eq!(c.along("right"), 0.2);
        assert_eq!(c.along("top"), 0.5, "sliding it on the right left the top where it was");
        c.set_along("top", 7.0);
        assert_eq!(c.along("top"), 1.0, "and it can never be put past the end of an edge");
    }

    #[test]
    fn the_shared_position_moves_to_the_edge_the_notch_was_on() {
        let mut c = Config { notch_y: 0.3, notch_edge: "left".into(), ..Default::default() };
        carry_shared_position(&mut c);
        assert_eq!(c.along("left"), 0.3, "an existing config keeps its place");
        assert_eq!(c.along("right"), 0.5, "the edges it was not on start centred");
        // Once carried over, a later load leaves it alone even though notch_y still reads 0.3
        c.set_along("left", 0.8);
        carry_shared_position(&mut c);
        assert_eq!(c.along("left"), 0.8);
        // A centred config has nothing to carry, so nothing is written for it
        let mut centred = Config::default();
        carry_shared_position(&mut centred);
        assert!(centred.notch_along.is_empty());
    }

    #[test]
    fn the_shared_position_is_read_but_never_written_again() {
        let mut v = serde_json::to_value(Config { notch_y: 0.3, ..Default::default() }).unwrap();
        assert!(v.get("notch_y").is_none(), "{v}");
        v["notch_y"] = serde_json::json!(0.3);
        let back: Config = serde_json::from_value(v).unwrap();
        assert_eq!(back.notch_y, 0.3);
    }

    #[test]
    fn a_saved_scale_snaps_to_the_nearest_size() {
        assert_eq!(snap_scale(0.4), 0.8);
        assert_eq!(snap_scale(0.85), 0.8);
        assert_eq!(snap_scale(0.9), 1.0);
        assert_eq!(snap_scale(1.0), 1.0);
        assert_eq!(snap_scale(1.2), 1.25);
        assert_eq!(snap_scale(3.0), 1.25);
    }

    #[test]
    fn only_the_two_placements_are_kept() {
        assert_eq!(weekly_ring_or_off("inside"), "inside");
        assert_eq!(weekly_ring_or_off("outside"), "outside");
        assert_eq!(weekly_ring_or_off("Inside"), "off");
        assert_eq!(weekly_ring_or_off(""), "off");
    }

    #[test]
    fn unknown_color_transition_keeps_the_original_step() {
        assert_eq!(color_transition_or_step("ramp"), "ramp");
        assert_eq!(color_transition_or_step("gradient"), "hard_step");
    }

    #[test]
    fn malformed_theme_does_not_discard_the_rest_of_the_config() {
        let cfg: Config = serde_json::from_str(
            r#"{"port": 49001, "theme": 7, "notch_y": 0.25}"#,
        )
        .expect("invalid theme should be tolerated");
        assert_eq!(cfg.port, 49001);
        assert_eq!(cfg.theme, "system");
        assert_eq!(cfg.notch_y, 0.25);
    }

    #[test]
    fn watch_and_critical_limits_never_cross() {
        let near = |a: f64, b: f64| (a - b).abs() < 1e-9;
        assert_eq!(clamp_watch_limit(0.5, 0.7), 0.5, "inside the gap, untouched");
        assert!(near(clamp_watch_limit(0.9, 0.7), 0.69), "pushed back below critical");
        assert_eq!(clamp_watch_limit(0.0, 0.7), 0.01, "never below the floor");
        assert_eq!(clamp_watch_limit(0.5, 0.0), 0.01, "a critical of 0 still leaves a floor");

        assert_eq!(clamp_critical_limit(0.7, 0.5), 0.7, "inside the gap, untouched");
        assert!(near(clamp_critical_limit(0.4, 0.5), 0.51), "pushed back above watch");
        assert_eq!(clamp_critical_limit(2.0, 0.5), 1.0, "never past 100%");
        assert_eq!(clamp_critical_limit(0.7, 1.0), 1.0, "a watch of 100% still leaves a ceiling");
    }

    #[test]
    fn theme_preserves_the_rest_of_a_config_when_it_is_missing_or_malformed() {
        let old: Config = serde_json::from_str(r#"{"notch_visible":false}"#).unwrap();
        assert_eq!(old.theme, "system", "an existing config follows Windows");
        assert!(!old.notch_visible, "the existing choice survives");

        for (raw, expected) in [
            (r#""light""#, "light"),
            (r#""dark""#, "dark"),
            (r#""Light""#, "system"),
            ("true", "system"),
            ("[]", "system"),
            ("{}", "system"),
            ("null", "system"),
        ] {
            let cfg: Config =
                serde_json::from_str(&format!(r#"{{"theme":{raw},"notch_visible":false}}"#))
                    .unwrap();
            assert_eq!(cfg.theme, expected, "{raw} resolves safely");
            assert!(
                !cfg.notch_visible,
                "{raw} did not discard the rest of the config"
            );
        }
    }

    #[test]
    fn edge_position_is_clamped_and_defaults_to_center() {
        let mut cfg = Config::default();
        assert_eq!(cfg.along("right"), 0.5);
        cfg.set_along("right", 2.0);
        assert_eq!(cfg.along("right"), 1.0);
        cfg.set_along("left", -1.0);
        assert_eq!(cfg.along("left"), 0.0);
    }
}
