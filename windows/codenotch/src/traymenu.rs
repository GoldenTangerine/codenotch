/*
@name: 上游功能同步
@Descripttion: 提供上游新增功能或对应回归验证。
@version: 1.0.0
@Author: sm
@Date: 2026-09-17 16:29:47
@LastEditTime: 2026-09-17 16:29:47
@FilePath: windows/codenotch/src/traymenu.rs
*/
//! The words the tray menu prints, and nothing else: no menu, no Tauri, so every line can be
//! tested on its own.
//!
//! The page has these strings too (`TEXT` in notch.html), and they are kept here under the exact
//! same English keys, the way `i18n.rs` already mirrors the page's dictionary. `the_card_and_the_menu_agree`
//! below fails if the two ever drift apart.
//!
//! Dates and times come from Windows rather than a table of month names: the menu should read the
//! way the taskbar clock does, including whether the user's region writes 4:59 AM or 16:59.

use crate::usage::{LimitWindow, UsageSnapshot};

/// A reading as the card prints it: whole percents, except where rounding would claim nothing is
/// used or nothing is left.
pub fn pct(fraction: f64) -> String {
    let v = (fraction * 100.0).clamp(0.0, 100.0);
    if v <= 0.0 {
        return "0".into();
    }
    // Tenths only where rounding would lie: a sliver used reading as 0, or a sliver left as 100.
    // Exactly 100 is not a sliver, so it stays a whole number.
    if v < 1.0 || (v > 99.0 && v < 100.0) {
        let tenth = (v * 10.0).round() / 10.0;
        if tenth < 0.1 {
            "<0.1".into()
        } else if tenth > 99.9 {
            ">99.9".into()
        } else {
            format!("{tenth:.1}")
        }
    } else {
        format!("{}", v.round() as u32)
    }
}

/// "61% Used · 39% left". Both ends, because vendors disagree about which one they publish, and the
/// left half is taken from the rounded used half so the two always add up on screen.
pub fn used_left(w: &LimitWindow, lang: &str) -> String {
    let v = (w.used * 100.0).clamp(0.0, 100.0);
    let (used, left) = if (v > 0.0 && v < 1.0) || (v > 99.0 && v < 100.0) {
        (pct(w.used), pct((100.0 - v) / 100.0))
    } else {
        let u = v.round() as u32;
        (u.to_string(), (100 - u.min(100)).to_string())
    };
    let used = if w.derived { format!("~{used}") } else { used };
    match lang {
        "ru" => format!("Использовано {used}% · осталось {left}%"),
        "zh" => format!("已用 {used}% · 剩余 {left}%"),
        "ja" => format!("{used}% 使用 · 残り {left}%"),
        "uk" => format!("Використано {used}% · Лишилось {left}%"),
        _ => format!("{used}% Used · {left}% left"),
    }
}

/// Unknown window lengths must not imply an even pace.
pub fn pace_points(w: &LimitWindow, now: u64) -> Option<f64> {
    if !w.metered() || !w.used.is_finite() || w.used < 0.0 { return None }
    let duration = w.duration_ms.filter(|d| *d > 0)? as f64;
    let remaining = w.resets_at.filter(|r| *r > now)?.saturating_sub(now) as f64;
    let elapsed = 1.0 - (remaining / duration).min(1.0);
    Some((w.used.min(1.0) - elapsed) * 100.0)
}

/// Only ahead-of-pace usage adds text; the reserved side stays unsaid.
pub fn deficit_text(w: &LimitWindow, now: u64, lang: &str) -> Option<String> {
    let points = pace_points(w, now).filter(|p| *p > 0.0)?;
    let rounded = (points * 10.0).round() / 10.0;
    let value = if rounded == 0.0 { "<0.1".to_string() } else { format!("{rounded:.1}").trim_end_matches(".0").to_string() };
    Some(match lang {
        "pt-BR" => format!("{value}% de déficit"),
        "ru" => format!("дефицит {value}%"),
        "zh" | "zh-Hant" => format!("{value}% 透支"),
        "ja" => format!("{value}% 超過"),
        "uk" => format!("{value}% дефіциту"),
        "ko" => format!("{value}% 초과"),
        _ => format!("{value}% deficit"),
    })
}

/// "Resets in 59 min", "Resets in 2h 15m", "Resets in 3 Days 4h", or the date and time once it is
/// far enough out that a duration stops meaning anything.
pub fn reset_text(resets_at: u64, now: u64, lang: &str) -> String {
    if resets_at <= now {
        return match lang {
            "ru" => "Сброс…",
            "zh" => "正在重置…",
            "ja" => "リセット中…",
            "uk" => "Скидання…",
            _ => "Resetting…",
        }
        .into();
    }
    let minutes = ((resets_at - now) as f64 / 60_000.0).round() as u64;
    let (hours, days) = (minutes / 60, minutes / 1440);
    if minutes < 60 {
        let m = minutes.max(1);
        return match lang {
            "ru" => format!("Сброс через {m} мин"),
            "zh" => format!("{m} 分钟后重置"),
            "ja" => format!("{m} 分後にリセット"),
            "uk" => format!("Скидання через {m} хв"),
            _ => format!("Resets in {m} min"),
        };
    }
    if hours < 24 {
        let (h, m) = (hours, minutes % 60);
        return match lang {
            "ru" => format!("Сброс через {h} ч {m} мин"),
            "zh" => format!("{h} 小时 {m} 分钟后重置"),
            "ja" => format!("{h} 時間 {m} 分後にリセット"),
            "uk" => format!("Скидання через {h} год {m} хв"),
            _ => format!("Resets in {h}h {m}m"),
        };
    }
    if days < 7 {
        let (d, h) = (days, hours % 24);
        return match lang {
            "ru" => format!("Сброс через {d} дн. {h} ч"),
            "zh" => format!("{d} 天 {h} 小时后重置"),
            "ja" => format!("{d} 日 {h} 時間後にリセット"),
            "uk" => format!("Скидання через {d} дн {h} год"),
            _ if d == 1 => format!("Resets in {d} Day {h}h"),
            _ => format!("Resets in {d} Days {h}h"),
        };
    }
    let when = system_datetime(resets_at);
    match lang {
        "ru" => format!("Сброс: {when}"),
        "zh" => format!("{when} 重置"),
        "ja" => format!("{when} にリセット"),
        "uk" => format!("Скидання {when}"),
        _ => format!("Resets {when}"),
    }
}

/// "20 min ago", for a reading that has gone stale.
pub fn ago(since: u64, now: u64, lang: &str) -> String {
    let minutes = now.saturating_sub(since) / 60_000;
    let span = if minutes < 60 {
        match lang {
            "ru" => format!("{minutes} мин"),
            "zh" => format!("{minutes} 分钟"),
            "ja" => format!("{minutes} 分"),
            "uk" => format!("{minutes} хв"),
            _ => format!("{minutes}m"),
        }
    } else {
        let h = (minutes as f64 / 60.0).round() as u64;
        match lang {
            "ru" => format!("{h} ч"),
            "zh" => format!("{h} 小时"),
            "ja" => format!("{h} 時間"),
            "uk" => format!("{h} год"),
            _ => format!("{h}h"),
        }
    };
    match lang {
        "ru" => format!("{span} назад"),
        "zh" => format!("{span}前"),
        "ja" => format!("{span}前"),
        "uk" => format!("{span} тому"),
        _ => format!("{span} ago"),
    }
}

/// The window names the providers publish. English is the key on both sides, so a provider that
/// starts sending a name nobody has translated prints that name rather than nothing.
pub fn label(name: &str, lang: &str) -> String {
    let translated = match (lang, name) {
        ("pt-BR", "Current session") => "Sessão atual",
        ("pt-BR", "Weekly (all models)") => "Semanal (todos os modelos)",
        ("pt-BR", "Weekly (Opus)") => "Semanal (Opus)",
        ("pt-BR", "Weekly (model-scoped)") => "Semanal (por modelo)",
        ("pt-BR", "Weekly limit" | "Weekly Limit") => "Limite semanal",
        ("pt-BR", "Monthly limit" | "Monthly Limit") => "Limite mensal",
        ("pt-BR", "5-hour Limit" | "5-Hour Limit") => "Limite de 5 horas",
        ("pt-BR", "Included usage") => "Uso incluído",
        ("pt-BR", "API usage") => "Uso da API",
        ("pt-BR", "Plan usage") => "Uso do plano",
        ("pt-BR", "Total usage") => "Uso total",
        ("pt-BR", "Add-on credits") => "Créditos adicionais",
        ("pt-BR", "Organization package") => "Pacote da organização",
        ("pt-BR", "Premium requests") => "Solicitações premium",
        ("pt-BR", "Chat requests") => "Solicitações de chat",
        ("pt-BR", "Completions") => "Conclusões de código",
        ("es", "Current session") => "Sesión actual",
        ("es", "Weekly (all models)") => "Semanal (todos los modelos)",
        ("es", "Weekly (Opus)") => "Semanal (Opus)",
        ("es", "Weekly (model-scoped)") => "Semanal (por modelo)",
        ("es", "Weekly limit" | "Weekly Limit") => "Límite semanal",
        ("es", "Monthly limit" | "Monthly Limit") => "Límite mensual",
        ("es", "5-hour Limit" | "5-Hour Limit") => "Límite de 5 horas",
        ("es", "Included usage") => "Uso incluido",
        ("es", "API usage") => "Uso de API",
        ("es", "Premium requests") => "Solicitudes premium",
        ("es", "Chat requests") => "Solicitudes de chat",
        ("es", "Completions") => "Autocompletados",
        ("ru", "Current session") => "Текущий сеанс",
        ("ru", "Weekly (all models)") => "Недельный (все модели)",
        ("ru", "Weekly (Opus)") => "Недельный (Opus)",
        ("ru", "Weekly (model-scoped)") => "Недельный (для выбранной модели)",
        ("ru", "Weekly limit" | "Weekly Limit") => "Недельный лимит",
        ("ru", "Monthly limit" | "Monthly Limit") => "Месячный лимит",
        ("ru", "5-hour Limit" | "5-Hour Limit") => "Лимит на 5 часов",
        ("ru", "Included usage") => "Включённое использование",
        ("ru", "API usage") => "Использование API",
        ("ru", "Premium requests") => "Премиум-запросы",
        ("ru", "Chat requests") => "Запросы чата",
        ("ru", "Completions") => "Автодополнения",
        ("zh", "Current session") => "当前会话",
        ("zh", "Weekly (all models)") => "每周（全部模型）",
        ("zh", "Weekly (Opus)") => "每周（Opus）",
        ("zh", "Weekly (model-scoped)") => "每周（指定模型）",
        ("zh", "Weekly limit" | "Weekly Limit") => "每周限额",
        ("zh", "Monthly limit" | "Monthly Limit") => "每月限额",
        ("zh", "5-hour Limit" | "5-Hour Limit") => "5 小时限额",
        ("zh", "Included usage") => "包含用量",
        ("zh", "API usage") => "API 用量",
        ("zh", "Premium requests") => "高级请求",
        ("zh", "Chat requests") => "聊天请求",
        ("zh", "Completions") => "代码补全",
        ("zh-Hant", "Current session") => "目前工作階段",
        ("zh-Hant", "Weekly (all models)") => "每週（全部模型）",
        ("zh-Hant", "Weekly (Opus)") => "每週（Opus）",
        ("zh-Hant", "Weekly (model-scoped)") => "每週（指定模型）",
        ("zh-Hant", "Weekly limit" | "Weekly Limit") => "每週限額",
        ("zh-Hant", "Monthly limit" | "Monthly Limit") => "每月限額",
        ("zh-Hant", "5-hour Limit" | "5-Hour Limit") => "5 小時限額",
        ("zh-Hant", "Included usage") => "包含用量",
        ("zh-Hant", "API usage") => "API 用量",
        ("zh-Hant", "Premium requests") => "進階請求",
        ("zh-Hant", "Chat requests") => "聊天請求",
        ("zh-Hant", "Completions") => "程式碼補全",
        ("ja", "Current session") => "現在のセッション",
        ("ja", "Weekly (all models)") => "週間 (すべてのモデル)",
        ("ja", "Weekly (Opus)") => "週間 (Opus)",
        ("ja", "Weekly (model-scoped)") => "週間 (モデル別)",
        ("ja", "Weekly limit" | "Weekly Limit") => "週間の上限",
        ("ja", "Monthly limit" | "Monthly Limit") => "月間の上限",
        ("ja", "5-hour Limit" | "5-Hour Limit") => "5 時間の上限",
        ("ja", "Included usage") => "プラン内の使用量",
        ("ja", "API usage") => "API 使用量",
        ("ja", "Premium requests") => "プレミアムリクエスト",
        ("ja", "Chat requests") => "チャットリクエスト",
        ("ja", "Completions") => "コード補完",
        ("uk", "Current session") => "Поточна сесія",
        ("uk", "Weekly (all models)") => "Тижневий (усі моделі)",
        ("uk", "Weekly (Opus)") => "Тижневий (Opus)",
        ("uk", "Weekly (model-scoped)") => "Тижневий (за моделями)",
        ("uk", "Weekly limit" | "Weekly Limit") => "Тижневий ліміт",
        ("uk", "Monthly limit" | "Monthly Limit") => "Місячний ліміт",
        ("uk", "5-hour Limit" | "5-Hour Limit") => "Ліміт 5 годин",
        ("uk", "Included usage") => "Використання в тарифі",
        ("uk", "API usage") => "Використання API",
        // Only these three in Korean: the Mac catalog has no Korean, so the names it shares
        // with the card have nothing to take.
        ("uk", "Premium requests") => "Преміум-запити",
        ("uk", "Chat requests") => "Запити чату",
        ("uk", "Completions") => "Автодоповнення",
        ("ko", "Current session") => "현재 세션",
        ("ko", "Included usage") => "포함 사용량",
        ("ko", "API usage") => "API 사용량",
        ("ko", "Weekly limit" | "Weekly Limit") => "주간 한도",
        ("ko", "Monthly limit" | "Monthly Limit") => "월간 한도",
        ("ko", "5-hour Limit" | "5-Hour Limit") => "5시간 한도",
        ("ko", "Weekly (all models)") => "주간 (모든 모델)",
        ("ko", "Weekly (Opus)") => "주간 (Opus)",
        ("ko", "Weekly (model-scoped)") => "주간 (모델별)",
        ("ko", "Premium requests") => "프리미엄 요청",
        ("ko", "Chat requests") => "채팅 요청",
        ("ko", "Completions") => "코드 완성",
        ("ko", "Plan usage") => "요금제 사용량",
        ("ko", "Total usage") => "총 사용량",
        ("ko", "Add-on credits") => "추가 크레딧",
        ("ko", "Organization package") => "조직 패키지",
        _ => name,
    };
    translated.into()
}

/// "Claude — 61%", plus how old the reading is once it has gone stale.
///
/// The fraction rather than a rounded percentage: Antigravity publishes lanes like 0.5 %, and a
/// header reading 1 % above a line reading 0.5 % is the app contradicting itself.
pub fn header(provider: &str, reading: Option<f64>, stale_since: Option<u64>, now: u64, lang: &str) -> String {
    let value = reading.map(|f| format!("{}%", pct(f))).unwrap_or_else(|| "—".into());
    // Under a minute is not worth saying. A provider that re-reads while still flagged stale would
    // otherwise head every line with "0m ago", which reads as a fault rather than as an age.
    match stale_since.filter(|since| now.saturating_sub(*since) >= 60_000) {
        Some(since) => format!("{provider} — {value} · {}", ago(since, now, lang)),
        None => format!("{provider} — {value}"),
    }
}

/// "Current session: 61% Used · 39% left · Resets in 59 min". A window with no denominator says how
/// many requests there were instead, because a percentage of an unpublished limit is a guess.
pub fn window_line(w: &LimitWindow, now: u64, lang: &str) -> String {
    let name = label(&w.label, lang);
    if let Some(count) = w.count {
        return format!("{name}: ~{count}");
    }
    if let Some(amount) = &w.amount {
        return format!("{name}: {amount}");
    }
    let mut line = format!("{name}: {}", used_left(w, lang));
    if let Some(deficit) = deficit_text(w, now, lang) {
        line.push_str(" · ");
        line.push_str(&deficit);
    }
    if let Some(at) = w.resets_at {
        line.push_str(" · ");
        line.push_str(&reset_text(at, now, lang));
    }
    line
}

/// Every line one provider contributes: its header, then a line per window it publishes.
pub fn provider_lines(snap: &UsageSnapshot, now: u64, lang: &str) -> Vec<String> {
    let mut lines = Vec::new();
    if let Some(status) = status_label(&snap.status, lang) {
        let history = if snap.windows.is_empty() { "" } else {
            match lang {
                "zh" => " · 历史读数", "ru" => " · Предыдущие данные",
                "uk" => " · Попередні дані", "ja" => " · 前回の値",
                "ko" => " · 이전 데이터", _ => " · Last reading",
            }
        };
        lines.push(format!("{status}{history}"));
    }
    if !snap.note.is_empty() && (snap.status != "ok" || snap.windows.is_empty()) {
        lines.push(snap.note.clone());
    }
    lines.extend(snap.windows.iter().map(|w| window_line(w, now, lang)));
    lines
}

pub fn status_label(status: &str, lang: &str) -> Option<&'static str> {
    Some(match (status, lang) {
        ("needsAuth", "zh") => "需要重新登录",
        ("needsAuth", "ru") => "Требуется вход",
        ("needsAuth", "uk") => "Потрібен вхід",
        ("needsAuth", "ja") => "再ログインが必要",
        ("needsAuth", "ko") => "다시 로그인 필요",
        ("needsAuth", _) => "Sign-in required",
        ("error" | "stale", "zh") => "暂时无法刷新",
        ("error" | "stale", "ru") => "Не удалось обновить",
        ("error" | "stale", "uk") => "Не вдалося оновити",
        ("error" | "stale", "ja") => "更新できません",
        ("error" | "stale", "ko") => "새로 고침 실패",
        ("error" | "stale", _) => "Unable to refresh",
        _ => return None,
    })
}

/// When the reading is old enough to say so: the page draws the same cell dimmed on the same rule.
pub fn stale_since(snap: &UsageSnapshot, now: u64) -> Option<u64> {
    let old = snap.fetched_at > 0 && now.saturating_sub(snap.fetched_at) > 5 * 60 * 1000;
    (status_label(&snap.status, "en").is_some() || old).then_some(snap.fetched_at).filter(|t| *t > 0)
}

/// The date and time as this machine writes them, so "Resets Thu, 4:59 AM" follows the same region
/// settings as the clock in the corner.
#[cfg(windows)]
fn system_datetime(ms: u64) -> String {
    use windows::core::PCWSTR;
    use windows::Win32::Globalization::{
        GetDateFormatEx, GetTimeFormatEx, DATE_SHORTDATE, TIME_NOSECONDS,
    };
    let Some(st) = local_systemtime(ms) else { return String::new() };
    let mut date = [0u16; 80];
    let mut time = [0u16; 80];
    let (d, t) = unsafe {
        (
            GetDateFormatEx(PCWSTR::null(), DATE_SHORTDATE, Some(&st), PCWSTR::null(), Some(&mut date), PCWSTR::null()),
            GetTimeFormatEx(PCWSTR::null(), TIME_NOSECONDS, Some(&st), PCWSTR::null(), Some(&mut time)),
        )
    };
    if d <= 0 || t <= 0 {
        return String::new();
    }
    let text = |buf: &[u16], n: i32| String::from_utf16_lossy(&buf[..(n as usize - 1)]);
    format!("{} {}", text(&date, d), text(&time, t))
}

/// Epoch milliseconds as local wall-clock time. chrono owns the calendar arithmetic; Windows only
/// formats what it is given.
#[cfg(windows)]
fn local_systemtime(ms: u64) -> Option<windows::Win32::Foundation::SYSTEMTIME> {
    use chrono::{Datelike, Local, TimeZone, Timelike};
    let local = Local.timestamp_millis_opt(ms as i64).single()?;
    Some(windows::Win32::Foundation::SYSTEMTIME {
        wYear: local.year() as u16,
        wMonth: local.month() as u16,
        wDayOfWeek: local.weekday().num_days_from_sunday() as u16,
        wDay: local.day() as u16,
        wHour: local.hour() as u16,
        wMinute: local.minute() as u16,
        wSecond: 0,
        wMilliseconds: 0,
    })
}

#[cfg(not(windows))]
fn system_datetime(_ms: u64) -> String {
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(label: &str, used: f64, resets_at: Option<u64>) -> LimitWindow {
        LimitWindow { id: "w".into(), label: label.into(), used, resets_at, ..Default::default() }
    }

    const MIN: u64 = 60 * 1000;

    fn paced(used: f64, remaining: u64, duration: u64) -> LimitWindow {
        let mut w = window("Current session", used, Some(MIN + remaining));
        w.duration_ms = Some(duration);
        w
    }

    #[test]
    fn deficit_matches_the_mac_and_worked_examples() {
        let duration = crate::usage::FIVE_HOURS_MS;
        for (used, remaining, expected) in [
            (0.10, 150 * MIN, None),
            (0.50, 150 * MIN, None),
            (0.60, 150 * MIN, Some("10% deficit")),
            (0.70, 210 * MIN, Some("40% deficit")),
            (0.625, 150 * MIN, Some("12.5% deficit")),
            (0.5004, 150 * MIN, Some("<0.1% deficit")),
            (1.0, 240 * MIN, Some("80% deficit")),
            (1.2, 240 * MIN, Some("80% deficit")),
            (0.30, 360 * MIN, Some("30% deficit")),
            (0.02, duration, Some("2% deficit")),
        ] {
            assert_eq!(deficit_text(&paced(used, remaining, duration), MIN, "en").as_deref(), expected);
        }
        let weekly = crate::usage::SEVEN_DAYS_MS;
        let w = paced(0.98, 1440 * MIN, weekly);
        assert!((pace_points(&w, MIN).unwrap() - 12.285714).abs() < 0.00001);
        assert_eq!(deficit_text(&w, MIN, "en").as_deref(), Some("12.3% deficit"));
        let reserve = paced(0.27, weekly / 2, weekly);
        assert!((pace_points(&reserve, MIN).unwrap() + 23.0).abs() < 0.00001);
        assert_eq!(deficit_text(&reserve, MIN, "en"), None);
        assert_eq!(deficit_text(&paced(0.4996, weekly / 2, weekly), MIN, "en"), None);
        assert!((pace_points(&paced(0.8, 36 * 60 * MIN, 3 * 1440 * MIN), MIN).unwrap() - 30.0).abs() < 0.00001);
        assert!((pace_points(&paced(0.2, weekly + 1000, weekly), MIN).unwrap() - 20.0).abs() < 0.00001);
    }

    #[test]
    fn pace_requires_a_valid_current_percentage_window() {
        let valid = paced(0.6, 150 * MIN, crate::usage::FIVE_HOURS_MS);
        let invalid = [
            LimitWindow { duration_ms: None, ..valid.clone() },
            LimitWindow { duration_ms: Some(0), ..valid.clone() },
            LimitWindow { resets_at: None, ..valid.clone() },
            LimitWindow { resets_at: Some(MIN), ..valid.clone() },
            LimitWindow { resets_at: Some(0), ..valid.clone() },
            LimitWindow { count: Some(42), ..valid.clone() },
            LimitWindow { used: f64::NAN, ..valid.clone() },
            LimitWindow { used: f64::INFINITY, ..valid.clone() },
            LimitWindow { used: f64::NEG_INFINITY, ..valid.clone() },
            LimitWindow { used: -0.1, ..valid.clone() },
        ];
        for w in invalid {
            assert_eq!(pace_points(&w, MIN), None);
            assert_eq!(deficit_text(&w, MIN, "en"), None);
        }
    }

    #[test]
    fn a_deficit_sits_between_usage_and_reset_in_each_language() {
        let w = paced(0.6, 150 * MIN, crate::usage::FIVE_HOURS_MS);
        assert_eq!(window_line(&w, MIN, "en"), "Current session: 60% Used · 40% left · 10% deficit · Resets in 2h 30m");
        assert_eq!(window_line(&w, MIN, "ru"), "Текущий сеанс: Использовано 60% · осталось 40% · дефицит 10% · Сброс через 2 ч 30 мин");
        for used in [0.1, 0.5] {
            let mut w = LimitWindow { used, ..w.clone() };
            let under_pace = window_line(&w, MIN, "en");
            w.duration_ms = None;
            assert_eq!(under_pace, window_line(&w, MIN, "en"));
        }
    }

    #[test]
    fn the_card_and_the_menu_agree_on_deficit_wording() {
        let page = include_str!("../ui/notch.html");
        let dictionary = page.split("const UI={").nth(1).unwrap().split("function ui()").next().unwrap();
        let w = paced(0.6, 150 * MIN, crate::usage::FIVE_HOURS_MS);
        // 本地刘海卡片的语言表只含 en/ru/zh/ja/uk/ko；pt-BR 与 zh-Hant 沿用 en/zh 的卡片文案，不在此对照。
        for lang in ["en", "ru", "zh", "ja", "uk", "ko"] {
            let key = if lang == "ja" { "UI.ja={".to_string() } else if lang.contains('-') { format!("'{lang}':{{") } else { format!("{lang}:{{") };
            let block = dictionary.split(&key).nth(1).unwrap_or_else(|| panic!("missing {lang} UI")).split("},").next().unwrap();
            let wording = deficit_text(&w, MIN, lang).unwrap().replace("10", "${v}");
            assert!(block.contains(&format!("deficit:v=>`{wording}`")), "{lang} card and tray disagree on deficit wording");
        }
        assert_eq!(deficit_text(&w, MIN, "unknown"), deficit_text(&w, MIN, "en"));
    }


    #[test]
    fn failed_refresh_keeps_history_but_explains_why_it_is_not_current() {
        for status in ["needsAuth", "stale", "error"] {
            let snap = UsageSnapshot {
                status: status.into(), note: "Synthetic refresh failure".into(), fetched_at: MIN,
                windows: vec![window("Current session", 0.3, None)], ..Default::default()
            };
            let lines = provider_lines(&snap, MIN + 1000, "en");
            assert!(lines[0].contains(status_label(status, "en").unwrap()));
            assert!(lines[0].contains("Last reading"));
            assert_eq!(lines[1], "Synthetic refresh failure");
            assert!(lines[2].contains("30%"));
            assert_eq!(stale_since(&snap, MIN + 1000), Some(MIN));
        }
    }

    #[test]
    fn menu_content_changes_for_status_secondary_limits_and_reset_times() {
        let base = UsageSnapshot {
            status: "ok".into(), windows: vec![window("Current session", 0.3, None),
                window("Weekly limit", 0.4, Some(60 * MIN))], ..Default::default()
        };
        let original = provider_lines(&base, 0, "en");
        let mut changed = base.clone();
        changed.windows[1].used = 0.5;
        assert_ne!(original, provider_lines(&changed, 0, "en"));
        changed = base.clone();
        changed.windows[1].resets_at = Some(90 * MIN);
        assert_ne!(original, provider_lines(&changed, 0, "en"));
        changed = base.clone();
        changed.status = "needsAuth".into();
        assert_ne!(original, provider_lines(&changed, 0, "en"));
        assert_eq!(original, provider_lines(&base, 0, "en"));
    }

    #[test]
    fn a_reading_reads_as_the_card_prints_it() {
        assert_eq!(pct(0.0), "0");
        assert_eq!(pct(0.0004), "<0.1");
        assert_eq!(pct(0.006), "0.6");
        assert_eq!(pct(0.615), "62");
        assert_eq!(pct(0.9995), ">99.9");
        assert_eq!(pct(1.0), "100");
    }

    #[test]
    fn a_window_says_both_ends_and_when_it_resets() {
        let w = window("Current session", 0.61, Some(60 * MIN));
        assert_eq!(
            window_line(&w, MIN, "en"),
            "Current session: 61% Used · 39% left · Resets in 59 min"
        );
        assert_eq!(
            window_line(&w, MIN, "ru"),
            "Текущий сеанс: Использовано 61% · осталось 39% · Сброс через 59 мин"
        );
    }

    #[test]
    fn a_reset_is_minutes_then_hours_then_days() {
        assert_eq!(reset_text(59 * MIN, 0, "en"), "Resets in 59 min");
        assert_eq!(reset_text(135 * MIN, 0, "en"), "Resets in 2h 15m");
        assert_eq!(reset_text(3 * 1440 * MIN + 4 * 60 * MIN, 0, "en"), "Resets in 3 Days 4h");
        assert_eq!(reset_text(1440 * MIN + 60 * MIN, 0, "en"), "Resets in 1 Day 1h");
        assert_eq!(reset_text(0, MIN, "en"), "Resetting…");
    }

    #[test]
    fn a_count_window_says_how_many_rather_than_a_percentage() {
        let mut w = window("Requests today", 0.0, None);
        w.count = Some(42);
        assert_eq!(window_line(&w, 0, "en"), "Requests today: ~42");
    }

    #[test]
    fn a_header_carries_the_age_only_once_the_reading_is_old() {
        assert_eq!(header("Claude", Some(0.61), None, 0, "en"), "Claude — 61%");
        assert_eq!(header("Claude", Some(0.61), Some(0), 20 * MIN, "en"), "Claude — 61% · 20m ago");
        assert_eq!(header("Cursor", None, None, 0, "en"), "Cursor — —");
    }

    /// A reading taken seconds ago says nothing about its age, however it is flagged.
    #[test]
    fn an_age_under_a_minute_is_left_unsaid() {
        assert_eq!(header("Claude", Some(0.07), Some(0), 30_000, "en"), "Claude — 7%");
        assert_eq!(header("Claude", Some(0.07), Some(0), 90_000, "en"), "Claude — 7% · 1m ago");
    }

    /// Antigravity reports lanes below one percent; rounding the header to 1 % while the line under
    /// it says 0.5 % has the menu disagreeing with itself.
    #[test]
    fn a_header_under_one_percent_keeps_its_tenth() {
        assert_eq!(header("Antigravity", Some(0.005), None, 0, "en"), "Antigravity — 0.5%");
        let w = window("Weekly Limit", 0.005, None);
        assert_eq!(window_line(&w, 0, "en"), "Weekly Limit: 0.5% Used · 99.5% left");
    }

    #[test]
    fn a_fresh_reading_is_not_called_stale() {
        let fresh = UsageSnapshot { status: "ok".into(), fetched_at: 1, ..Default::default() };
        assert_eq!(stale_since(&fresh, 2 * MIN), None);
        assert_eq!(stale_since(&fresh, 10 * MIN), Some(1));
        let flagged = UsageSnapshot { status: "stale".into(), fetched_at: 1, ..Default::default() };
        assert_eq!(stale_since(&flagged, 2), Some(1));
    }

    /// The page translates these same names; if either side is reworded the menu and the card would
    /// disagree about the same window.
    #[test]
    fn the_card_and_the_menu_agree_on_window_names() {
        let page = include_str!("../ui/notch.html");
        for name in ["Current session", "Weekly (all models)", "Weekly (Opus)", "Weekly (model-scoped)",
                     "Weekly limit", "Monthly limit", "Included usage", "API usage",
                     "Premium requests", "Chat requests", "Completions"] {
            assert!(page.contains(&format!("'{name}'")), "notch.html no longer names {name:?}");
            assert_ne!(label(name, "ru"), name, "{name:?} lost its Russian here");
        }
    }
}
