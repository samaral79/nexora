//! Nexora Build — monitor gráfico do build da Nexora Linux (Rust + Slint, render por software).
//!
//! Lê, sem root:
//!   /mnt/lfs/sources/.done e .logs        -> estado de cada pacote
//!   scripts/build/*.sh, scripts/blfs/*.sh -> ordem dos pacotes por fase
//!   journal do serviço nexora-build       -> horas de início e durações
//!   cgroup do serviço                     -> memória e CPU do build
//! Quando a imagem está desmontada mostra o último estado guardado em ~/.cache.
//! Uso: nexora-monitor [--hidden]   (NEXORA_PROJ=<pasta do projeto> para outra árvore)

slint::include_modules!();

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::ffi::CString;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use ksni::blocking::TrayMethods;
use regex::Regex;
use resvg::tiny_skia;
use slint::{Color, ComponentHandle, Model as _, ModelRc, SharedPixelBuffer, VecModel};

const UNIT: &str = "nexora-build";
const LFS: &str = "/mnt/lfs";
const DONE: &str = "/mnt/lfs/sources/.done";
const LOGS: &str = "/mnt/lfs/sources/.logs";
const CGROUP: &str = "/sys/fs/cgroup/system.slice/nexora-build.service";
const ICON_SVG: &[u8] = include_bytes!("../nexora.svg");
const SPIN: [&str; 4] = ["◐", "◓", "◑", "◒"];

const PHASES: &[(&str, &str, &str)] = &[
    ("ch5", "Cap. 5 · Toolchain cruzada", "build/ch5.sh"),
    ("ch6", "Cap. 6 · Ferramentas temporárias", "build/ch6.sh"),
    ("ch7", "Cap. 7 · Chroot", "build/ch7.sh"),
    ("ch8", "Cap. 8 · Sistema base", "build/ch8.sh"),
    ("ch9", "Cap. 9 · Configuração", "build/ch9.sh"),
    ("ch10", "Cap. 10 · Kernel e GRUB", "build/ch10.sh"),
    ("blfs-a", "BLFS A · Rede e ferramentas", "blfs/blfs-a.sh"),
    ("blfs-b", "BLFS B · Xorg, Mesa e GTK", "blfs/blfs-b.sh"),
    ("blfs-c", "BLFS C · Xfce e LightDM", "blfs/blfs-c.sh"),
    ("blfs-d", "Nexora · Toques finais", "blfs/blfs-d.sh"),
    ("blfs-e", "Nexora · Xfce de origem", "blfs/blfs-e.sh"),
    ("blfs-f", "Nexora · Live e instalador", "blfs/blfs-f.sh"),
    ("blfs-g", "Nexora · Hardware e visual", "blfs/blfs-g.sh"),
    ("blfs-h", "Nexora Flow · Wayland", "blfs/blfs-h.sh"),
    ("blfs-i", "Nexora · Browser", "blfs/blfs-i.sh"),
    ("blfs-j", "Nexora · Base moderna", "blfs/blfs-j.sh"),
    ("blfs-k", "Nexora · Apps GTK4", "blfs/blfs-k.sh"),
    ("blfs-l", "Nexora · Mais apps", "blfs/blfs-l.sh"),
    ("blfs-m", "Nexora · Vídeo e música", "blfs/blfs-m.sh"),
    ("blfs-n", "Nexora · Cara nova", "blfs/blfs-n.sh"),
    ("blfs-o", "Nexora Flow · Acertos", "blfs/blfs-o.sh"),
    ("blfs-p", "Nexora · AUR isolado", "blfs/blfs-p.sh"),
];
// fases que correm dentro do chroot (as que o Retomar sabe relançar): tudo menos os caps. 5 e 6
fn chroot_phase(k: &str) -> bool {
    k != "ch5" && k != "ch6"
}

// ------------------------------------------------------------------ utilitários
fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

fn hms(sec: f64) -> String {
    let s = sec.max(0.0) as u64;
    let (h, m, s) = (s / 3600, s % 3600 / 60, s % 60);
    if h > 0 {
        format!("{h}h{m:02}m")
    } else if m > 0 {
        format!("{m}m{s:02}s")
    } else {
        format!("{s}s")
    }
}

fn gib(b: u64) -> String {
    format!("{:.1} GiB", b as f64 / 1073741824.0)
}

fn read_u64(p: &str) -> Option<u64> {
    let v = std::fs::read_to_string(p).ok()?;
    let v = v.trim();
    if v == "max" {
        None
    } else {
        v.parse().ok()
    }
}

fn is_mounted(p: &str) -> bool {
    std::fs::read_to_string("/proc/self/mounts")
        .map(|m| m.lines().any(|l| l.split(' ').nth(1) == Some(p)))
        .unwrap_or(false)
}

fn disk_usage(p: &str) -> Option<(u64, u64)> {
    let c = CString::new(p).ok()?;
    // SAFETY: statvfs só escreve na struct que lhe passamos
    unsafe {
        let mut s: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c.as_ptr(), &mut s) != 0 {
            return None;
        }
        let f = s.f_frsize as u64;
        let total = s.f_blocks as u64 * f;
        Some((total - s.f_bfree as u64 * f, total))
    }
}

fn local_hm(t: f64) -> String {
    // SAFETY: localtime_r só escreve no tm que lhe passamos
    unsafe {
        let tt = t as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&tt, &mut tm);
        format!("{:02}:{:02}", tm.tm_hour, tm.tm_min)
    }
}

fn mtime(p: &Path) -> SystemTime {
    std::fs::metadata(p).and_then(|m| m.modified()).unwrap_or(UNIX_EPOCH)
}

/// Lança um processo sem esperar por ele (e sem deixar zombies).
fn spawn(cmd: &str, args: &[&str]) {
    if let Ok(mut c) = Command::new(cmd).args(args).stdin(Stdio::null()).spawn() {
        std::thread::spawn(move || {
            let _ = c.wait();
        });
    }
}

fn output(cmd: &str, args: &[&str]) -> String {
    Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default()
}

fn notify(title: &str, body: &str, urgent: bool) {
    // caminho absoluto: o tema hicolor do utilizador não tem index.theme e o nome não resolve
    let icon = std::env::var("HOME").map(|h| format!("{h}/.local/share/icons/hicolor/scalable/apps/nexora-monitor.svg"))
        .unwrap_or_default();
    spawn("notify-send", &["-a", "Nexora Build", "-i", &icon, "-u",
                           if urgent { "critical" } else { "normal" }, title, body]);
}

fn rgb(hex: u32) -> Color {
    Color::from_rgb_u8((hex >> 16) as u8, (hex >> 8) as u8, hex as u8)
}

const ACCENT: u32 = 0x22b8cf;
const GREEN: u32 = 0x3fb950;
const RED: u32 = 0xe5534b;
const GREY: u32 = 0x8b949e;
const AMBER: u32 = 0xd29922;
const DIM: u32 = 0x5d6b78;

fn status_hex(s: &str) -> u32 {
    match s {
        "A compilar" => ACCENT,
        "Falhou" => RED,
        "Completo" => GREEN,
        _ => GREY,
    }
}

struct Re {
    nice: Regex,
    ansi: Regex,
    jline: Regex,
    jend: Regex,
    chain: Regex,
}

impl Re {
    fn new() -> Self {
        Re {
            nice: Regex::new(r"^[A-Z]?\d*\.?\d+[a-z]?-").unwrap(),
            ansi: Regex::new(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\r").unwrap(),
            jline: Regex::new(r"^(\d+\.\d+) \S+ \S+: (🔨|✔|✘|⏭)\s+(\S+)(?: \.\.\.)?(?: \((\d+)m(\d+)s\))?").unwrap(),
            jend: Regex::new(r"^(\d+\.\d+) \S+ \S+: (🎉|🏁)\s*(.*)$").unwrap(),
            chain: Regex::new(r"chroot\.sh (\S+)").unwrap(),
        }
    }
    /// B.49-rust -> rust
    fn nice(&self, pid: &str) -> String {
        let s = self.nice.replace(pid, "");
        if s.is_empty() { pid.to_string() } else { s.into_owned() }
    }
}

// ------------------------------------------------------------------ dados
#[derive(Default)]
struct Data {
    phases: Vec<(String, String, Vec<String>)>, // (chave, nome, ids)
    order: Vec<String>,
    phase_of: HashMap<String, String>,
    starts: HashMap<String, f64>,
    durations: HashMap<String, u64>,
    events: Vec<String>,
    first_seen: HashMap<String, f64>,
    cpu_prev: Option<(u64, Instant)>,
    last_start: Option<String>,
    last_closed: Option<String>,
}

struct Svc {
    active: bool,
    result: String,
    started: Option<f64>,
    chain: Vec<String>,
}

struct Snap {
    mounted: bool,
    done: HashSet<String>,
    logs: HashSet<String>,
    cached_at: f64,
}

impl Data {
    fn load_scripts(&mut self, scripts: &Path) {
        self.phases.clear();
        self.order.clear();
        self.phase_of.clear();
        for (key, label, rel) in PHASES {
            let mut ids = Vec::new();
            if let Ok(t) = std::fs::read_to_string(scripts.join(rel)) {
                for line in t.lines() {
                    let mut w = line.split_whitespace();
                    if matches!(w.next(), Some("pkg") | Some("step")) {
                        if let Some(id) = w.next() {
                            ids.push(id.to_string());
                        }
                    }
                }
            }
            for i in &ids {
                self.order.push(i.clone());
                self.phase_of.insert(i.clone(), key.to_string());
            }
            self.phases.push((key.to_string(), label.to_string(), ids));
        }
    }

    fn read_journal(&mut self, re: &Re) {
        let out = output("journalctl", &["-u", UNIT, "-o", "short-unix", "-q", "--no-pager", "-n", "4000"]);
        if out.is_empty() {
            return;
        }
        self.events.clear();
        self.last_start = None;
        self.last_closed = None;
        for line in out.lines() {
            if let Some(c) = re.jline.captures(line) {
                let t: f64 = c[1].parse().unwrap_or(0.0);
                let pid = c[3].to_string();
                match &c[2] {
                    "🔨" => {
                        self.starts.insert(pid.clone(), t);
                        self.last_start = Some(pid);
                    }
                    sym @ ("✔" | "✘") => {
                        if sym == "✔" {
                            if let (Some(m), Some(s)) = (c.get(4), c.get(5)) {
                                let d = m.as_str().parse::<u64>().unwrap_or(0) * 60
                                    + s.as_str().parse::<u64>().unwrap_or(0);
                                self.durations.insert(pid.clone(), d);
                            }
                        }
                        if self.last_start.as_deref() == Some(pid.as_str()) {
                            self.last_closed = Some(pid);
                        }
                    }
                    _ => {}
                }
            } else if let Some(c) = re.jend.captures(line) {
                self.events.push(c[3].to_string());
            }
        }
    }

    fn service(re: &Re) -> Svc {
        let out = output("systemctl", &["show", UNIT, "--timestamp=unix", "-p", "ActiveState", "-p", "Result",
                                        "-p", "ExecMainStartTimestamp", "-p", "ExecStart"]);
        let mut s = Svc { active: false, result: String::new(), started: None, chain: Vec::new() };
        for l in out.lines() {
            if let Some((k, v)) = l.split_once('=') {
                match k {
                    "ActiveState" => s.active = v == "active",
                    "Result" => s.result = v.to_string(),
                    "ExecMainStartTimestamp" => s.started = v.trim_start_matches('@').parse().ok(),
                    "ExecStart" => s.chain = re.chain.captures_iter(v).map(|c| c[1].to_string()).collect(),
                    _ => {}
                }
            }
        }
        s
    }
}

// ------------------------------------------------------------------ símbolo
fn status_icon(tree: &resvg::usvg::Tree, status: &str, frac: f32, size: u32) -> tiny_skia::Pixmap {
    use tiny_skia::{FillRule, Paint, PathBuilder, Rect, Transform};
    let mut pm = tiny_skia::Pixmap::new(size, size).unwrap();
    let sz = size as f32;
    let k = sz * 0.86 / tree.size().width();
    resvg::render(tree, Transform::from_scale(k, k), &mut pm.as_mut());
    let c = status_hex(status);
    let (r, g, b) = ((c >> 16) as u8, (c >> 8) as u8, c as u8);
    let mut paint = Paint::default();
    paint.anti_alias = true;
    let fill = |pm: &mut tiny_skia::Pixmap, pb: PathBuilder, paint: &Paint| {
        if let Some(p) = pb.finish() {
            pm.fill_path(&p, paint, FillRule::Winding, Transform::identity(), None);
        }
    };
    let capsule = |x: f32, y: f32, w: f32, h: f32| {
        let mut pb = PathBuilder::new();
        let rr = h / 2.0;
        if let Some(rc) = Rect::from_xywh(x + rr, y, (w - h).max(0.01), h) {
            pb.push_rect(rc);
        }
        pb.push_circle(x + rr, y + rr, rr);
        pb.push_circle(x + w - rr, y + rr, rr);
        pb
    };
    // barra de progresso em baixo
    let h = (size / 9).max(2) as f32;
    paint.set_color_rgba8(128, 128, 128, 140);
    fill(&mut pm, capsule(0.0, sz - h, sz, h), &paint);
    paint.set_color_rgba8(r, g, b, 255);
    fill(&mut pm, capsule(0.0, sz - h, (sz * frac).max(h), h), &paint);
    // ponto de estado
    let d = (sz * 0.36).floor().max(5.0);
    let mut pb = PathBuilder::new();
    pb.push_circle(sz - d / 2.0 - 1.0, sz - h - d / 2.0 - 1.0, d / 2.0 + 1.0);
    paint.set_color_rgba8(20, 20, 20, 200);
    fill(&mut pm, pb, &paint);
    let mut pb = PathBuilder::new();
    pb.push_circle(sz - d / 2.0, sz - h - d / 2.0, d / 2.0);
    paint.set_color_rgba8(r, g, b, 255);
    fill(&mut pm, pb, &paint);
    pm
}

fn pixmap_rgba(pm: &tiny_skia::Pixmap) -> Vec<u8> {
    pm.pixels().iter().flat_map(|p| {
        let c = p.demultiply();
        [c.red(), c.green(), c.blue(), c.alpha()]
    }).collect()
}

// ------------------------------------------------------------------ painel (StatusNotifierItem)
struct NxTray {
    ui: slint::Weak<AppWindow>,
    icon: Vec<ksni::Icon>,
    tip: (String, String),
    active: bool,
    shown: bool,
}

impl ksni::Tray for NxTray {
    fn id(&self) -> String {
        "nexora-monitor".into()
    }
    fn title(&self) -> String {
        "Nexora Build".into()
    }
    fn category(&self) -> ksni::Category {
        ksni::Category::SystemServices
    }
    fn icon_pixmap(&self) -> Vec<ksni::Icon> {
        self.icon.clone()
    }
    fn tool_tip(&self) -> ksni::ToolTip {
        ksni::ToolTip { title: self.tip.0.clone(), description: self.tip.1.clone(), ..Default::default() }
    }
    fn activate(&mut self, _x: i32, _y: i32) {
        let _ = self.ui.upgrade_in_event_loop(|ui| ui.invoke_tray_toggle());
    }
    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::{MenuItem, StandardItem};
        let item = |label: &str, icon: &str, enabled: bool, f: fn(&AppWindow)| -> MenuItem<Self> {
            StandardItem {
                label: label.into(),
                icon_name: icon.into(),
                enabled,
                activate: Box::new(move |t: &mut Self| {
                    let _ = t.ui.upgrade_in_event_loop(move |ui| f(&ui));
                }),
                ..Default::default()
            }
            .into()
        };
        vec![
            item(if self.shown { "Esconder janela" } else { "Mostrar janela" }, "", true, |ui| ui.invoke_tray_toggle()),
            MenuItem::Separator,
            item("Parar build", "media-playback-stop", self.active, |ui| ui.invoke_stop()),
            item("Retomar build", "media-playback-start", !self.active, |ui| ui.invoke_resume()),
            MenuItem::Separator,
            item("Sair do monitor", "application-exit", true, |ui| ui.invoke_tray_quit()),
        ]
    }
}

// ------------------------------------------------------------------ app
enum Pending {
    Stop,
    Resume(Vec<String>),
    Nothing,
}

struct App {
    scripts: PathBuf,
    cache: PathBuf,
    d: Data,
    re: Re,
    svg: resvg::usvg::Tree,
    tick: u64,
    prev_status: Option<&'static str>,
    prev_events: Option<usize>,
    selected_log: Option<String>,
    current: Option<String>,
    expanded: HashSet<String>,
    last_log: String,
    last_cache: String,
    icon_key: Option<(&'static str, u32)>,
    told_tray: bool,
    shown: bool,
    pending: Pending,
    // último estado (para redesenhar a lista sem reler tudo)
    snap_done: HashSet<String>,
    status: &'static str,
    active: bool,
    ph_cur: Option<String>,
    phases_m: Rc<VecModel<PhaseRow>>,
    pkgs_m: Rc<VecModel<PkgRow>>,
    tray: Option<ksni::blocking::Handle<NxTray>>,
}

impl App {
    fn snapshot(&mut self) -> Snap {
        let mounted = is_mounted(LFS) && Path::new(DONE).is_dir();
        if mounted {
            let ls = |p: &str| -> Vec<String> {
                std::fs::read_dir(p)
                    .map(|r| r.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect())
                    .unwrap_or_default()
            };
            let mut done = ls(DONE);
            let mut logs: Vec<String> = ls(LOGS).into_iter()
                .filter_map(|f| f.strip_suffix(".log").map(str::to_string)).collect();
            done.sort();
            logs.sort();
            let key = format!("{}|{}", done.len(), logs.len());
            if key != self.last_cache {
                self.last_cache = key;
                let j = serde_json::json!({"done": done, "logs": logs, "t": now()});
                let _ = std::fs::create_dir_all(self.cache.parent().unwrap());
                let _ = std::fs::write(&self.cache, j.to_string());
            }
            Snap { mounted, done: done.into_iter().collect(), logs: logs.into_iter().collect(), cached_at: 0.0 }
        } else {
            let mut s = Snap { mounted, done: HashSet::new(), logs: HashSet::new(), cached_at: 0.0 };
            if let Ok(t) = std::fs::read_to_string(&self.cache) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
                    let set = |k: &str| -> HashSet<String> {
                        v[k].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
                            .unwrap_or_default()
                    };
                    s.done = set("done");
                    s.logs = set("logs");
                    s.cached_at = v["t"].as_f64().unwrap_or(0.0);
                }
            }
            s
        }
    }

    fn pending_phases(&self, done: &HashSet<String>) -> Vec<String> {
        self.d.phases.iter()
            .filter(|(k, _, ids)| chroot_phase(k) && ids.iter().any(|i| !done.contains(i)))
            .map(|(k, _, _)| k.clone())
            .collect()
    }

    fn label_of(&self, key: Option<&str>) -> String {
        key.and_then(|k| PHASES.iter().find(|p| p.0 == k)).map(|p| p.1.to_string()).unwrap_or_default()
    }

    fn refresh(&mut self, ui: &AppWindow, full: bool) {
        self.tick += 1;
        if full || self.tick % 20 == 0 {
            self.d.load_scripts(&self.scripts);
        }
        if full || self.tick % 2 == 0 {
            self.d.read_journal(&self.re);
        }
        let svc = Data::service(&self.re);
        let active = svc.active;
        let sn = self.snapshot();
        let (done, logs) = (&sn.done, &sn.logs);

        // pacote atual: o último 🔨 do journal ainda sem ✔/✘; senão o log mais recente sem .done
        let mut cur = None;
        if active {
            if let Some(ls) = &self.d.last_start {
                if self.d.last_closed.as_ref() != Some(ls) && !done.contains(ls) {
                    cur = Some(ls.clone());
                }
            }
        }
        if cur.is_none() {
            let cands: Vec<&String> = self.d.order.iter().filter(|i| logs.contains(*i) && !done.contains(*i)).collect();
            if !cands.is_empty() {
                cur = if sn.mounted {
                    cands.iter().max_by_key(|i| mtime(&Path::new(LOGS).join(format!("{i}.log")))).map(|s| (*s).clone())
                } else {
                    Some(cands[0].clone())
                };
            }
        }
        self.current = cur.clone();
        let n_done = self.d.order.iter().filter(|i| done.contains(*i)).count();
        let total = self.d.order.len();
        ui.set_n_done(n_done as i32);
        ui.set_n_total(total as i32);

        // estado geral
        let status: &'static str = if active {
            "A compilar"
        } else if cur.is_some() && !svc.result.is_empty() && svc.result != "success" {
            "Falhou"
        } else if cur.is_some() {
            "Parado"
        } else if n_done == total {
            "Completo"
        } else {
            "Parado"
        };
        ui.set_status(status.into());
        ui.set_status_color(rgb(status_hex(status)));
        ui.set_active(active);

        // subtítulo e relógio
        let ph_cur = cur.as_ref().and_then(|c| self.d.phase_of.get(c).cloned());
        let label = self.label_of(ph_cur.as_deref());
        if !sn.mounted {
            let age = if sn.cached_at > 0.0 { local_hm(sn.cached_at) } else { "?".into() };
            ui.set_subtitle(format!("Imagem desmontada · último estado às {age}").into());
        } else if !label.is_empty() {
            ui.set_subtitle(label.clone().into());
        } else {
            ui.set_subtitle(if n_done == total { "Tudo compilado" } else { "À espera" }.into());
        }
        ui.set_clock(match (active, svc.started) {
            (true, Some(t0)) => format!("build a correr há {}", hms(now() - t0)).into(),
            _ => "".into(),
        });

        // fases
        let rows: Vec<PhaseRow> = self.d.phases.iter().map(|(k, l, ids)| PhaseRow {
            label: l.into(),
            done: ids.iter().filter(|i| done.contains(*i)).count() as i32,
            total: ids.len() as i32,
            active: ph_cur.as_deref() == Some(k.as_str()),
        }).collect();
        sync_model(&self.phases_m, rows);

        // pacote atual
        let spin = SPIN[(self.tick % 4) as usize];
        let mut cur_time = String::new();
        if let Some(c) = &cur {
            let t0 = self.d.starts.get(c).copied()
                .unwrap_or_else(|| *self.d.first_seen.entry(c.clone()).or_insert_with(now));
            ui.set_cur_name(self.re.nice(c).into());
            let mut info;
            if active {
                ui.set_cur_spin(spin.into());
                ui.set_cur_spin_color(rgb(ACCENT));
                cur_time = hms(now() - t0);
                info = format!("{c} · {label}");
            } else {
                let failed = status == "Falhou";
                ui.set_cur_spin(if failed { "✘" } else { "⏸" }.into());
                ui.set_cur_spin_color(rgb(if failed { RED } else { AMBER }));
                info = format!("{c} · {}", if failed { "falhou — vê o log abaixo" } else { "parado a meio, retoma quando quiseres" });
            }
            // a seguir: o resto desta fase e das fases seguintes da cadeia
            let ids_of: HashMap<&str, &Vec<String>> = self.d.phases.iter().map(|(k, _, ids)| (k.as_str(), ids)).collect();
            let chain: Vec<String> = if svc.chain.is_empty() {
                self.d.phases.iter().map(|p| p.0.clone()).collect()
            } else {
                svc.chain.clone()
            };
            let mut seq: Vec<&String> = ph_cur.as_deref().and_then(|p| ids_of.get(p)).map(|v| v.iter().collect()).unwrap_or_default();
            if let Some(pos) = ph_cur.as_ref().and_then(|p| chain.iter().position(|k| k == p)) {
                for k in &chain[pos + 1..] {
                    if let Some(v) = ids_of.get(k.as_str()) {
                        seq.extend(v.iter());
                    }
                }
            }
            if let Some(pos) = seq.iter().position(|i| *i == c) {
                let nxt: Vec<String> = seq[pos + 1..].iter().filter(|i| !done.contains(**i)).take(3).map(|i| self.re.nice(i)).collect();
                if !nxt.is_empty() {
                    info.push_str(&format!("   ·   a seguir: {}", nxt.join(", ")));
                }
            }
            ui.set_cur_info(info.into());
        } else {
            ui.set_cur_spin(if n_done == total { "✔" } else { "" }.into());
            ui.set_cur_spin_color(rgb(GREEN));
            ui.set_cur_name(if n_done == total { "Tudo pronto" } else { "Nada a compilar" }.into());
            ui.set_cur_info("".into());
        }
        ui.set_cur_time(cur_time.clone().into());

        if full {
            self.expanded = ph_cur.iter().cloned().collect();
        }
        self.snap_done = sn.done.clone();
        self.status = status;
        self.active = active;
        self.ph_cur = ph_cur;
        if self.shown {
            self.rebuild_pkgs();
            self.refresh_resources(ui);
            self.refresh_log(ui, false);
        }

        // notificações: fim de fase e fim do serviço
        if let Some(p) = self.prev_events {
            for txt in self.d.events.iter().skip(p) {
                notify("Nexora Linux", txt, false);
            }
        }
        self.prev_events = Some(self.d.events.len());
        if let Some(p) = self.prev_status {
            if p != status {
                match status {
                    "Falhou" => notify("Build da Nexora falhou",
                                       &format!("Parou em {}", cur.as_deref().unwrap_or("?")), true),
                    "Completo" => notify("Build da Nexora completo", "Está tudo compilado. 🎉", false),
                    _ => {}
                }
            }
        }
        self.prev_status = Some(status);

        // símbolo do painel e da janela
        let frac = if total > 0 { n_done as f32 / total as f32 } else { 0.0 };
        let pct = (frac * 100.0) as u32;
        let new_icon = self.icon_key != Some((status, pct));
        if new_icon {
            self.icon_key = Some((status, pct));
            let pm = status_icon(&self.svg, status, frac, 64);
            let buf = SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(&pixmap_rgba(&pm), 64, 64);
            ui.set_win_icon(slint::Image::from_rgba8(buf));
        }
        let pending = self.pending_phases(done);
        ui.set_hint(if active || pending.is_empty() { "".into() } else {
            format!("Retomar relança: {}", pending.join(" → ")).into()
        });
        if let Some(tray) = &self.tray {
            let icons: Option<Vec<ksni::Icon>> = new_icon.then(|| {
                [16u32, 22, 24, 32, 48, 64].iter().map(|&s| {
                    let pm = status_icon(&self.svg, status, frac, s);
                    let data = pm.pixels().iter().flat_map(|p| {
                        let c = p.demultiply();
                        [c.alpha(), c.red(), c.green(), c.blue()]
                    }).collect();
                    ksni::Icon { width: s as i32, height: s as i32, data }
                }).collect()
            });
            let line = match &cur {
                Some(c) if active => format!("{} há {}", self.re.nice(c), cur_time),
                Some(c) => self.re.nice(c),
                None => String::new(),
            };
            let counts = format!("{n_done}/{total} pacotes · {pct}%");
            let tip = (format!("Nexora Build — {status}"),
                       if line.is_empty() { counts } else { format!("{line}\n{counts}") });
            let shown = self.shown;
            tray.update(move |t| {
                if let Some(i) = icons {
                    t.icon = i;
                }
                t.tip = tip;
                t.active = active;
                t.shown = shown;
            });
        }
    }

    fn rebuild_pkgs(&mut self) {
        let done = &self.snap_done;
        let spin = SPIN[(self.tick % 4) as usize];
        let mut rows = Vec::with_capacity(64);
        for (key, label, ids) in &self.d.phases {
            let n = ids.iter().filter(|i| done.contains(*i)).count();
            let expanded = self.expanded.contains(key);
            let is_cur = self.ph_cur.as_deref() == Some(key.as_str());
            rows.push(PkgRow {
                header: true,
                sym: if n == ids.len() && !ids.is_empty() { "✔" } else if is_cur { "●" } else { "" }.into(),
                col: rgb(if is_cur && n != ids.len() { ACCENT } else { GREEN }),
                name: label.into(),
                phase: format!("{n}/{}", ids.len()).into(),
                dur: "".into(),
                id: key.into(),
                expanded,
            });
            if !expanded {
                continue;
            }
            for pid in ids {
                let is_now = self.current.as_deref() == Some(pid.as_str());
                let (sym, col) = if done.contains(pid) {
                    ("✔", GREEN)
                } else if is_now {
                    if self.active { (spin, ACCENT) } else if self.status == "Falhou" { ("✘", RED) } else { ("⏸", AMBER) }
                } else {
                    ("·", DIM)
                };
                let dur = if is_now && self.active {
                    hms(now() - self.d.starts.get(pid).copied().unwrap_or_else(now))
                } else {
                    self.d.durations.get(pid).map(|d| hms(*d as f64)).unwrap_or_default()
                };
                rows.push(PkgRow {
                    header: false,
                    sym: sym.into(),
                    col: rgb(col),
                    name: self.re.nice(pid).into(),
                    phase: key.into(),
                    dur: dur.into(),
                    id: pid.into(),
                    expanded: false,
                });
            }
        }
        sync_model(&self.pkgs_m, rows);
    }

    fn refresh_resources(&mut self, ui: &AppWindow) {
        let mut mem: HashMap<String, u64> = HashMap::new();
        if let Ok(t) = std::fs::read_to_string("/proc/meminfo") {
            for l in t.lines() {
                if let Some((k, v)) = l.split_once(':') {
                    mem.insert(k.to_string(), v.split_whitespace().next().and_then(|x| x.parse().ok()).unwrap_or(0) * 1024);
                }
            }
        }
        let g = |k: &str| mem.get(k).copied().unwrap_or(0);
        let ram_total = g("MemTotal").max(1);
        let ram_used = ram_total.saturating_sub(g("MemAvailable"));
        let (sw_total, sw_used) = (g("SwapTotal"), g("SwapTotal").saturating_sub(g("SwapFree")));
        let md = |frac: f64, text: String, warn: bool| MeterData { frac: frac as f32, text: text.into(), warn };

        let mut cores = None;
        if Path::new(CGROUP).is_dir() {
            let cur = read_u64(&format!("{CGROUP}/memory.current")).unwrap_or(0);
            let lim = read_u64(&format!("{CGROUP}/memory.max")).unwrap_or(ram_total);
            let high = read_u64(&format!("{CGROUP}/memory.high"));
            let warn = high.map(|h| cur as f64 >= h as f64 * 0.95).unwrap_or(false);
            ui.set_m_build(md(cur as f64 / lim as f64, format!("{:.1} / {}", cur as f64 / 1073741824.0, gib(lim)), warn));
            if let Ok(st) = std::fs::read_to_string(format!("{CGROUP}/cpu.stat")) {
                if let Some(u) = st.lines().find_map(|l| l.strip_prefix("usage_usec ")).and_then(|v| v.trim().parse::<u64>().ok()) {
                    let t = Instant::now();
                    if let Some((pu, pt)) = self.d.cpu_prev {
                        let dt = t.duration_since(pt).as_secs_f64();
                        if dt > 0.0 {
                            cores = Some(u.saturating_sub(pu) as f64 / 1e6 / dt);
                        }
                    }
                    self.d.cpu_prev = Some((u, t));
                }
            }
        } else {
            self.d.cpu_prev = None;
            ui.set_m_build(md(0.0, "serviço parado".into(), false));
        }
        ui.set_m_ram(md(ram_used as f64 / ram_total as f64, format!("{} de {}", gib(ram_used), gib(ram_total)),
                        ram_used as f64 / ram_total as f64 > 0.9));
        if sw_total > 0 {
            ui.set_m_swap(md(sw_used as f64 / sw_total as f64, format!("{} de {}", gib(sw_used), gib(sw_total)),
                             sw_used as f64 / sw_total as f64 > 0.8));
        }
        match is_mounted(LFS).then(|| disk_usage(LFS)).flatten() {
            Some((u, t)) => ui.set_m_disk(md(u as f64 / t.max(1) as f64, format!("{} de {}", gib(u), gib(t)), false)),
            None => ui.set_m_disk(md(0.0, "desmontado".into(), false)),
        }
        let load = std::fs::read_to_string("/proc/loadavg").ok()
            .and_then(|t| t.split_whitespace().next().map(str::to_string)).unwrap_or_else(|| "?".into());
        let ncpu = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
        ui.set_cpu_text(match cores {
            Some(c) => format!("CPU do build: {c:.1} de {ncpu} núcleos   ·   load {load}"),
            None => format!("load {load}"),
        }.into());
    }

    fn refresh_log(&mut self, ui: &AppWindow, force: bool) {
        let Some(pid) = self.selected_log.clone().or_else(|| self.current.clone()) else {
            ui.set_log_title("".into());
            return;
        };
        ui.set_log_title(format!("{pid}.log{}", if self.selected_log.is_some() { "  (escolhido)" } else { "" }).into());
        let path = Path::new(LOGS).join(format!("{pid}.log"));
        let Ok(mut f) = std::fs::File::open(&path) else { return };
        use std::io::{Read, Seek, SeekFrom};
        let size = f.metadata().map(|m| m.len()).unwrap_or(0);
        let _ = f.seek(SeekFrom::Start(size.saturating_sub(96 * 1024)));
        let mut buf = Vec::new();
        if f.read_to_end(&mut buf).is_err() {
            return;
        }
        let raw = String::from_utf8_lossy(&buf);
        let clean = self.re.ansi.replace_all(&raw, "");
        let lines: Vec<&str> = clean.lines().collect();
        let text = lines[lines.len().saturating_sub(400)..].join("\n");
        if !force && text == self.last_log {
            return;
        }
        ui.set_log_text(text.as_str().into());
        self.last_log = text;
        if ui.get_follow() || force {
            ui.invoke_scroll_log_end();
        }
    }

    fn show(&mut self, ui: &AppWindow) {
        if !self.shown {
            self.shown = true;
            let _ = ui.show();
            self.rebuild_pkgs();
            self.refresh_resources(ui);
            self.refresh_log(ui, true);
            if let Some(t) = &self.tray {
                t.update(|t| t.shown = true);
            }
        }
    }

    fn hide(&mut self, ui: &AppWindow) {
        self.shown = false;
        let _ = ui.hide();
        if let Some(t) = &self.tray {
            t.update(|t| t.shown = false);
        }
    }

    fn dialog(&mut self, ui: &AppWindow, title: &str, text: &str, ok_only: bool, p: Pending) {
        self.show(ui);
        self.pending = p;
        ui.set_dlg_title(title.into());
        ui.set_dlg_text(text.into());
        ui.set_dlg_ok_only(ok_only);
        ui.set_dlg_visible(true);
    }
}

/// Atualiza um modelo só onde mudou (a lista não salta nem pisca).
fn sync_model<T: Clone + PartialEq + 'static>(m: &VecModel<T>, rows: Vec<T>) {
    if m.row_count() != rows.len() {
        m.set_vec(rows);
        return;
    }
    for (i, r) in rows.into_iter().enumerate() {
        if m.row_data(i).as_ref() != Some(&r) {
            m.set_row_data(i, r);
        }
    }
}

fn project_dir() -> PathBuf {
    std::env::var_os("NEXORA_PROJ").map(PathBuf::from).unwrap_or_else(|| {
        let p = PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../.."));
        p.canonicalize().unwrap_or(p)
    })
}

fn main() {
    let hidden = std::env::args().any(|a| a == "--hidden");
    let proj = project_dir();
    let ui = AppWindow::new().expect("não consegui abrir a janela");
    // só depois de haver plataforma (antes disto falha); tem de ser antes de mostrar a janela
    let _ = slint::set_xdg_app_id("nexora-monitor");
    // a letra mono do sistema (o Slint não resolve o alias "monospace" do fontconfig)
    let mono = output("fc-match", &["-f", "%{family[0]}", "monospace"]);
    if !mono.trim().is_empty() {
        ui.set_mono_font(mono.trim().into());
    }
    let svg = resvg::usvg::Tree::from_data(ICON_SVG, &resvg::usvg::Options::default()).unwrap();
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| "/tmp".into());

    let app = Rc::new(RefCell::new(App {
        scripts: proj.join("scripts"),
        cache: home.join(".cache/nexora-monitor/state.json"),
        d: Data::default(),
        re: Re::new(),
        svg,
        tick: 0,
        prev_status: None,
        prev_events: None,
        selected_log: None,
        current: None,
        expanded: HashSet::new(),
        last_log: String::new(),
        last_cache: String::new(),
        icon_key: None,
        told_tray: false,
        shown: false,
        pending: Pending::Nothing,
        snap_done: HashSet::new(),
        status: "Parado",
        active: false,
        ph_cur: None,
        phases_m: Rc::new(VecModel::default()),
        pkgs_m: Rc::new(VecModel::default()),
        tray: None,
    }));
    {
        let a = app.borrow();
        ui.set_phases(ModelRc::from(a.phases_m.clone()));
        ui.set_pkgs(ModelRc::from(a.pkgs_m.clone()));
    }

    // símbolo no painel (se não houver painel com StatusNotifier, fica só a janela)
    let tray = NxTray { ui: ui.as_weak(), icon: Vec::new(), tip: Default::default(), active: false, shown: false };
    app.borrow_mut().tray = tray.spawn().ok();
    let has_tray = app.borrow().tray.is_some();

    // ---------- ações
    let w = ui.as_weak();
    let a = app.clone();
    let with = move |f: fn(&mut App, &AppWindow)| {
        let (w, a) = (w.clone(), a.clone());
        move || {
            if let Some(ui) = w.upgrade() {
                f(&mut a.borrow_mut(), &ui);
            }
        }
    };
    ui.on_open_log(with(|a, _| {
        if let Some(pid) = a.selected_log.clone().or_else(|| a.current.clone()) {
            spawn("xdg-open", &[&format!("{LOGS}/{pid}.log")]);
        }
    }));
    ui.on_open_folder(with(|_, _| spawn("xdg-open", &[LOGS])));
    ui.on_back(with(|a, ui| {
        a.selected_log = None;
        ui.set_picked(false);
        a.refresh_log(ui, true);
    }));
    ui.on_stop(with(|a, ui| {
        a.dialog(ui, "Parar o build",
                 "Parar o build da Nexora?\n\nO pacote a meio perde-se, mas tudo o que já está feito fica. \
                  Depois é só carregar em Retomar.", false, Pending::Stop);
    }));
    ui.on_resume(with(|a, ui| {
        let sn = a.snapshot();
        let ph = a.pending_phases(&sn.done);
        if ph.is_empty() {
            a.dialog(ui, "Nada a fazer", "Todas as fases estão completas. 🎉", true, Pending::Nothing);
        } else {
            let txt = format!("Relançar estas fases (o que já está feito é saltado):\n\n{}", ph.join("  →  "));
            a.dialog(ui, "Retomar o build", &txt, false, Pending::Resume(ph));
        }
    }));
    ui.on_tray_toggle(with(|a, ui| if a.shown { a.hide(ui) } else { a.show(ui) }));
    ui.on_tray_quit(|| {
        let _ = slint::quit_event_loop();
    });
    {
        let (w, a) = (ui.as_weak(), app.clone());
        ui.on_dlg_answer(move |yes| {
            let Some(ui) = w.upgrade() else { return };
            ui.set_dlg_visible(false);
            let mut a = a.borrow_mut();
            match std::mem::replace(&mut a.pending, Pending::Nothing) {
                Pending::Stop if yes => spawn("systemctl", &["stop", UNIT]), // o polkit pede a senha
                Pending::Resume(ph) if yes => {
                    let script = a.scripts.join("build-bg.sh");
                    let mut args: Vec<&str> = vec![script.to_str().unwrap_or("")];
                    args.extend(ph.iter().map(String::as_str));
                    spawn("pkexec", &args);
                }
                _ => {}
            }
        });
    }
    {
        let (w, a) = (ui.as_weak(), app.clone());
        ui.on_pick(move |id| {
            let Some(ui) = w.upgrade() else { return };
            if Path::new(LOGS).join(format!("{id}.log")).exists() {
                let mut a = a.borrow_mut();
                a.selected_log = Some(id.to_string());
                ui.set_picked(true);
                ui.set_tab(0);
                a.refresh_log(&ui, true);
            }
        });
    }
    {
        let a = app.clone();
        ui.on_toggle_phase(move |key| {
            let mut a = a.borrow_mut();
            let k = key.to_string();
            if !a.expanded.remove(&k) {
                a.expanded.insert(k);
            }
            a.rebuild_pkgs();
        });
    }
    {
        // fechar a janela deixa o monitor no painel; "Sair do monitor" no menu do símbolo fecha mesmo
        let (w, a) = (ui.as_weak(), app.clone());
        ui.window().on_close_requested(move || {
            let mut a = a.borrow_mut();
            if a.tray.is_some() {
                a.shown = false;
                if let Some(t) = &a.tray {
                    t.update(|t| t.shown = false);
                }
                if !a.told_tray {
                    a.told_tray = true;
                    notify("Nexora Build", "Continuo no painel, junto ao relógio. Clica no símbolo para voltar.", false);
                }
            } else {
                let _ = slint::quit_event_loop();
            }
            let _ = &w;
            slint::CloseRequestResponse::HideWindow
        });
    }

    // ---------- arranque
    {
        let mut a = app.borrow_mut();
        a.shown = !(hidden && has_tray);
        a.refresh(&ui, true);
    }
    if !(hidden && has_tray) {
        ui.show().expect("não consegui mostrar a janela");
    }
    let timer = slint::Timer::default();
    {
        let (w, a) = (ui.as_weak(), app.clone());
        timer.start(slint::TimerMode::Repeated, Duration::from_millis(1500), move || {
            if let Some(ui) = w.upgrade() {
                a.borrow_mut().refresh(&ui, false);
            }
        });
    }
    slint::run_event_loop_until_quit().expect("erro no ciclo de eventos");
    let tray = app.borrow_mut().tray.take();
    if let Some(t) = tray {
        t.shutdown().wait();
    }
}
