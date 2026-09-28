/**
 @name: 项目构建与文档
 @Descripttion: 维护 tray.rs 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: windows/codenotch/src/tray.rs
 */
use crate::i18n::tr;
use crate::traymenu;
use tauri::menu::{Menu, MenuBuilder, MenuItemBuilder};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, Wry};

pub(crate) struct Reading {
    pub id: &'static str,
    pub snapshot: crate::usage::UsageSnapshot,
    pub fraction: Option<f64>,
}

fn readings(app: &AppHandle) -> Vec<Reading> {
    crate::TRAY_PROVIDER_IDS.iter().map(|&id| {
        let snapshot = crate::snapshot_of(app, id);
        let fraction = crate::ring_fraction(app, id, &snapshot);
        Reading { id, snapshot, fraction }
    }).collect()
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    // 旧版说明保留；本次扩展后的行为见下方实现。
    // The application's own icon rather than the monochrome tray glyph: see trayicon::app_mark
    let lang = language(app);
    let readings = readings(app);
    let lines = menu_lines(&lang, &readings);
    let menu = build_menu_from(app, &lang, &lines)?;
    let mut builder = TrayIconBuilder::with_id("main");
    // Windows does not tint tray icons and the monochrome outline vanishes on a dark taskbar, so
    // the app's own mark is the icon. trayicon::app_mark explains why at length.
    if let Some(icon) = crate::trayicon::app_mark() {
        builder = builder.icon(icon);
    }
    builder
        .tooltip(concat!("Codenotch v", env!("CARGO_PKG_VERSION")))
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, ev| handle(app, ev.id().as_ref()))
        .build(app)?;
    *SHOWN.lock().unwrap() = Some((lang, lines));
    refresh_menu(app);
    Ok(())
}

/// 旧版说明保留；本次扩展后的行为见下方实现。
/// Deliberately short. Everything that used to live here — language, autostart, hooks, the tray
/// icon layout, the notch — now has a proper home in the settings window, which can explain each
/// choice instead of hiding it behind a two-word menu label.
/// The readings themselves, as the Mac's menu bar shows them: a line per provider with its headline
/// figure, and under it one greyed line per limit window. The macOS menu is rebuilt as it opens;
/// Tauri has no such hook, so `refresh_menu` is called whenever a reading changes and once a minute
/// besides, which keeps "Resets in 12 min" honest.
/// Every line the menu would show, in order, with the id each carries. Kept apart from building the
/// menu so a refresh can tell whether anything visible changed before it swaps the menu out.
fn menu_lines(lang: &str, readings: &[Reading]) -> Vec<(String, String, bool)> {
    let now = crate::now_ms();
    let mut lines = Vec::new();
    for reading in readings {
        let (id, snap) = (reading.id, &reading.snapshot);
        if snap.status == "absent" {
            continue;
        }
        let head = traymenu::header(
            crate::provider_label(id),
            reading.fraction,
            traymenu::stale_since(snap, now),
            now,
            lang,
        );
        // Clicking a provider re-reads that one, as on the Mac.
        lines.push((format!("refresh:{id}"), head, true));
        for (n, line) in traymenu::provider_lines(snap, now, lang).iter().enumerate() {
            // Windows does not indent submenu-less items, so the indent is in the text.
            lines.push((format!("line:{id}:{n}"), format!("    {line}"), false));
        }
    }
    lines
}

fn build_menu_from(app: &AppHandle, lang: &str, lines: &[(String, String, bool)]) -> tauri::Result<Menu<Wry>> {
    let lang = lang.to_string();
    let mut items: Vec<tauri::menu::MenuItem<Wry>> = Vec::new();
    for (id, text, enabled) in lines {
        items.push(MenuItemBuilder::with_id(id.clone(), text.clone()).enabled(*enabled).build(app)?);
    }
    if items.is_empty() {
        items.push(
            MenuItemBuilder::with_id("waiting", tr(&lang, "waiting"))
                .enabled(false)
                .build(app)?,
        );
    }
    let refresh = MenuItemBuilder::with_id("refresh", tr(&lang, "refresh_all")).build(app)?;
    let settings = MenuItemBuilder::with_id("settings", tr(&lang, "settings")).build(app)?;
    let quit = MenuItemBuilder::with_id("quit", tr(&lang, "quit_app")).build(app)?;
    let mut menu = MenuBuilder::new(app);
    for item in &items {
        menu = menu.item(item);
    }
    menu.separator()
        .item(&refresh)
        .item(&settings)
        .separator()
        .item(&quit)
        .build()
}

/// The language the menu speaks, already resolved: `traymenu` picks its wording by code and has no
/// "auto" of its own.
fn language(app: &AppHandle) -> String {
    let st = app.state::<crate::AppState>();
    let raw = st.cfg.lock().unwrap().lang.clone();
    if raw == "auto" {
        crate::i18n::resolve_auto().to_string()
    } else {
        raw
    }
}

/// The hover text: the same figures the menu opens with, for when the menu is not open.
fn tooltip(lang: &str, readings: &[Reading]) -> String {
    let mut parts: Vec<String> = Vec::new();
    for reading in readings {
        let (id, snap) = (reading.id, &reading.snapshot);
        if snap.status == "absent" {
            continue;
        }
        let value = reading.fraction
            .map(|f| format!("{}%", traymenu::pct(f)))
            .unwrap_or_else(|| "—".into());
        let status = traymenu::status_label(&snap.status, lang)
            .map(|s| format!(" ({s})")).unwrap_or_default();
        parts.push(format!("{} {value}{status}", crate::provider_label(id)));
    }
    if parts.is_empty() {
        concat!("Codenotch v", env!("CARGO_PKG_VERSION")).to_string()
    } else {
        format!("Codenotch — {}", parts.join(" · "))
    }
}

/// Rebuilds the tray menu, ALWAYS on the main thread.
///
/// A menu is a Windows UI object. Building one or swapping it in from another thread leaves the
/// tray holding a menu that never opens again — and since changing the language is what triggers a
/// rebuild, the user is then locked out of the only place they could change it back. The tray's own
/// 旧版说明保留；本次扩展后的行为见下方实现。
/// click handlers already run on the main thread, but commands from the settings window do not, so
/// the hop is done here once rather than being remembered at every call site.
/// click handlers already run on the main thread, but the readings poller and the settings window
/// do not, so the hop is done here once rather than being remembered at every call site.
/// What the menu last showed, so an unchanged refresh leaves it alone.
static TOOLTIP_SHOWN: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

static SHOWN: std::sync::Mutex<Option<(String, Vec<(String, String, bool)>)>> = std::sync::Mutex::new(None);

/// Swaps the menu only when a line of it would read differently. `set_menu` replaces the menu the
/// user may have open this moment — the refresh runs on the main thread, which the open popup's
/// message loop still serves — so the minute tick used to close it under the pointer even when
/// "Resets in 12 min" still said 12 min.
pub fn refresh_menu(app: &AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(tray) = handle.tray_by_id("main") {
            let readings = readings(&handle);
            let lang = language(&handle);
            crate::update_tray_icon(&handle, &readings);
            let tip = tooltip(&lang, &readings);
            if TOOLTIP_SHOWN.lock().unwrap().as_ref() != Some(&tip) {
                if tray.set_tooltip(Some(&tip)).is_ok() {
                    *TOOLTIP_SHOWN.lock().unwrap() = Some(tip);
                }
            }
            let lines = menu_lines(&lang, &readings);
            let key = (lang.clone(), lines.clone());
            if SHOWN.lock().unwrap().as_ref() == Some(&key) {
                // A tooltip can change without a line changing, and setting it closes nothing.
                return;
            }
            match build_menu_from(&handle, &lang, &lines) {
                Ok(menu) => {
                    match tray.set_menu(Some(menu)) {
                        Ok(()) => *SHOWN.lock().unwrap() = Some(key),
                        Err(e) => crate::applog(&format!("tray menu: {e}")),
                    }
                }
                Err(e) => crate::applog(&format!("tray menu: {e}")),
            }
        }
    });
}

/// 旧版说明保留；本次扩展后的行为见下方实现。
/// Only the three items build_menu creates. Everything the menu used to offer besides these
/// (hooks, autostart, language, reset, the data folder, the icon layout) now lives in the settings
/// window and arrives as a command from there, never as a menu event.
/// Provider rows carry `refresh:<id>`; everything else the menu offers is one of the four fixed
/// items. Settings, language, hooks and the rest arrive as commands from the settings window.
fn handle(app: &AppHandle, id: &str) {
    if let Some(provider) = id.strip_prefix("refresh:") {
        refresh_provider(app, provider);
        return;
    }
    match id {
        "refresh" => {
            for provider in crate::TRAY_PROVIDER_IDS {
                refresh_provider(app, provider);
            }
            let a = app.clone();
            std::thread::spawn(move || crate::reload_glyphs(&a));
        }
        "settings" => crate::settings_window::open(app),
        "quit" => app.exit(0),
        _ => {}
    }
}

/// Asks one provider to read again. Claude's backoff is cleared first: asking for a reading is the
/// user saying they want it now, not in fifteen minutes.
fn refresh_provider(app: &AppHandle, provider: &str) {
    match provider {
        "codex" => crate::codex::request_refresh(),
        "cursor" => crate::cursor::request_refresh(),
        "grok" => crate::grok::request_refresh(),
        "gemini" => crate::antigravity::request_refresh(),
        _ => {
            {
                let st = app.state::<crate::AppState>();
                let mut u = st.usage.lock().unwrap();
                u.backoff_until = 0;
            }
            crate::usage::request_refresh();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tooltip_and_menu_share_precise_readings_and_auth_state() {
        let readings = vec![Reading {
            id: "claude",
            fraction: Some(0.005),
            snapshot: crate::usage::UsageSnapshot {
                status: "needsAuth".into(),
                windows: vec![crate::usage::LimitWindow {
                    label: "Current session".into(), used: 0.005,
                    ..Default::default()
                }],
                ..Default::default()
            },
        }];
        let tip = tooltip("zh", &readings);
        let lines = menu_lines("zh", &readings);
        assert!(tip.contains("0.5%"));
        assert!(tip.contains("需要重新登录"));
        assert!(lines[0].1.contains("0.5%"));
        assert!(lines[1].1.contains("需要重新登录 · 历史读数"));
        assert!(tooltip("en", &[]).starts_with("Codenotch v"));
    }
}
