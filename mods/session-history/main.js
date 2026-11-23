// Session history panel. Minimal paint first, then full UI once the slot shows.

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, Scrollbar } from "gpui-base";
import {
  spaces, panes, run, theme, shared, setShared, exec, home, appHome, openOverlay, props, window, knownAgents, checking, watchFolder, notify, closeOverlay,
} from "herdr";

const SCOPES = [
  { id: "spaces", label: "工作区" },
  { id: "projects", label: "项目" },
  { id: "all", label: "全部" },
];
// Catalog mirrors Orca's Agent Session History: every CLI whose transcript
// store we can read gets scanned; empty stores simply contribute no rows.
const AGENTS = [
  { id: "pi", label: "Pi" },
  { id: "claude", label: "Claude" },
  { id: "codex", label: "Codex" },
  { id: "opencode", label: "OpenCode" },
  { id: "gemini", label: "Gemini" },
  { id: "cursor", label: "Cursor" },
  { id: "droid", label: "Droid" },
  { id: "muse", label: "Muse" },
  { id: "omp", label: "OMP" },
  { id: "prime", label: "Prime Agent" },
  { id: "copilot", label: "GitHub Copilot" },
  { id: "cline", label: "Cline" },
  { id: "grok", label: "Grok" },
  { id: "devin", label: "Devin" },
  { id: "openclaw", label: "OpenClaw" },
  { id: "rovo", label: "Rovo Dev" },
  { id: "kimi", label: "Kimi" },
  { id: "kiro", label: "Kiro" },
  { id: "codebuddy", label: "CodeBuddy" },
  { id: "jcode", label: "Jcode" },
  { id: "qoder", label: "Qoder" },
  { id: "zcode", label: "ZCode" },
  { id: "hermes", label: "Hermes" },
];

// Orca opens on 全部; "This folder" starts nearly empty for most spaces.
// Brand icons for stores the app's program table doesn't carry (OMP/ZCode),
// bundled in this mod's icons/ folder.
const LOCAL_ICONS = {
  omp: { file: "omp.svg", tint: true }, // white glyph, drawn in theme color
  zcode: { file: "zcode.svg" }, // multicolor brand mark
};

// Store ids that differ from the program table's key: the table names the
// omp CLI "oh-my-pi" (official name, and its icon); sources/rows should show
// exactly what the launcher menu shows.
const NAME_ALIASES = { omp: ["oh-my-pi"] };

const scopeOf = () => SCOPES.find((s) => s.id === shared("session-history.scope")) ?? SCOPES[2];
const agentsOf = () => {
  const raw = shared("session-history.agents");
  const list = Array.isArray(raw) && raw.length ? raw : AGENTS.map((a) => a.id);
  return AGENTS.filter((a) => list.includes(a.id));
};

function age(ms) {
  if (!ms) return "";
  const d = Date.now() - ms;
  const m = Math.floor(d / 60000);
  if (m < 1) return "now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const days = Math.floor(h / 24);
  return days < 30 ? `${days}d` : `${Math.floor(days / 30)}mo`;
}

function activeFolder() {
  const s = spaces().find((x) => x.active);
  return s?.folder || null;
}

// oh-my-herdr is macOS-first; Linux falls back to xdg-open / xclip / wl-copy
// where they exist.
const PLATFORM = () => window()?.platform || "macos";
const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

function copyText(text) {
  const t = String(text);
  return exec("bash", ["-c", `printf %s ${shq(t)} | pbcopy 2>/dev/null || printf %s ${shq(t)} | xclip -selection clipboard 2>/dev/null || printf %s ${shq(t)} | wl-copy 2>/dev/null`]).catch(() => {});
}

function revealPath(p) {
  if (PLATFORM() === "macos") {
    return exec("open", ["-R", String(p)]).catch(() => {});
  }
  const dir = String(p).replace(/\/[^/]*$/, "") || "/";
  return exec("xdg-open", [dir]).catch(() => {});
}

function removePath(p) {
  return exec("rm", ["-rf", String(p)]).catch(() => {});
}

function openDir(p) {
  if (!p) return;
  if (PLATFORM() === "macos") {
    exec("open", [String(p)]).catch(() => {});
    return;
  }
  exec("xdg-open", [String(p)]).catch(() => {});
}

export default class SessionHistory extends View {
  init(_props, cx) {
    const p = props() ?? {};
    // One class, four kinds of copies: the panel, a transcript viewer tab, the
    // handoff dialog, and the light popup menus (actions / worktree / agents).
    this.mode = p.viewer ? "viewer" : p.handoff ? "handoff" : (p.actionsMenu || p.wtPicker) ? "menu" : "panel";
    this.icons = {};
    if (this.mode === "viewer") {
      this.viewer = p.viewer;
      this.viewerText = null;
      this.viewerError = null;
      if (checking()) return;
      cx.spawn(async (cx) => {
        try {
          const r = await exec("python3", [`${appHome()}/mods/session-history/log.py`, "text", this.viewer.path, this.viewer.agent], { timeout: 30000 });
          if (r.code !== 0) throw new Error((r.stderr || `exited ${r.code}`).trim().slice(0, 200));
          this.viewerText = r.stdout;
        } catch (e) {
          this.viewerError = String(e?.message || e).slice(0, 200);
        }
        cx.notify();
      });
      return;
    }
    if (this.mode === "handoff") {
      this.h = { session: p.handoff.session, agents: null, pick: null, mode: "focused", sum: null, error: null };
      if (checking()) return;
      cx.spawn(async (cx) => {
        try {
          const all = await knownAgents();
          this.h.agents = all.filter((a) => a.installed).sort((a, b) => a.name.localeCompare(b.name));
          this.h.pick = this.h.agents[0]?.key ?? null;
        } catch (e) {
          this.h.error = String(e?.message ?? e);
        }
        try {
          const s = this.h.session;
          const r = await exec("python3", [`${appHome()}/mods/session-history/log.py`, "summary", s.path, s.agent], { timeout: 20000 });
          this.h.sum = JSON.parse(((r.stdout || "{}").trim().split("\n").pop()));
        } catch (e) {
          this.h.sum = { ok: false, reason: String(e?.message ?? e) };
        }
        cx.notify();
      });
      return;
    }
    if (this.mode === "menu") {
      // light copies: the agents filter menu still wants the program icons
      if (p.agentsMenu && !checking()) {
        cx.spawn(async (cx) => {
          await this.loadIcons(cx);
        });
      }
      return;
    }
    this.input = InputState.new({ placeholder: "Type to filter…" });
    this.filter = "";
    this.sessions = [];
    this.sources = {};
    this.partial = false;
    this.lastAt = 0;
    this.error = null;
    this.loading = false;
    this.token = 0;
    this.expanded = null;
    this.booted = false;
    this.icons = {};
    this.scanning = false;
    this.pendingScan = false;
    this.lastDone = 0;
    this.sourcesOpen = true;
    this.folds = {};
    this._dirty = true;
    this._cache = null;
    this._rebuilding = false;
    this._normCache = new Map();
    this.lastDone = 0;
    this.input.on("change", (_e, cx) => { this.filter = this.input.value(); this._dirty = true; this.scheduleRebuild(cx); cx.notify(); });
    cx.spawn(async (cx) => {
      if (checking()) return;
      await this.loadIcons(cx);
      await this.refresh(cx);
      this.booted = true;
      cx.notify();
      // Transcript stores are watched, so a new session shows up on its own;
      // the slow timer only covers watches the app reclaimed or refused.
      // Registered after the first scan lands so a hot reload's first paint
      // carries only the render, not seven watch registrations.
      for (const root of this.watchRoots()) {
        cx.spawn(async (cx) => {
          for (;;) {
            try {
              await watchFolder(root);
            } catch {
              return;
            }
            // the active session writes its transcript constantly; keep the
            // rescan cadence sane instead of scanning back-to-back
            const gap = Date.now() - (this.lastDone || 0);
            if (gap < 8000) await cx.timer.wait(8000 - gap);
            await this.refresh(cx);
          }
        });
      }
      for (;;) {
        await cx.timer.wait(300000);
        await this.refresh(cx);
      }
    });
  }

  // The app's program table carries the official per-agent icons — the very
  // same entries, flags and files the launcher menu draws with. Use its
  // `tint` as given: re-deriving it from the svg text misclassifies gradient
  // icons (codex) as one-color glyphs and svg()-tints them into a black
  // square.
  async loadIcons(cx) {
    try {
      const known = await knownAgents();
      this.icons = Object.fromEntries((known || []).map((p) => [p.key, p]));
    } catch {}
    cx.notify();
  }

  // One program glyph, drawn exactly like the shipped launcher menu
  // (new-menu): `tint` marks a one-color glyph and is drawn in the theme
  // foreground via svg(); everything else is the icon's own picture via
  // image(). Program-table `tile` colors are badge-style and don't match the
  // menu look, so they are not used here.
  programIcon(a, t, size = 14) {
    if (!a?.icon) {
      const label = a?.label || a?.key || "?";
      return div().size(size).rounded(Math.max(3, Math.round(size / 4))).flex_none().flex().items_center().justify_center()
        .text_size(Math.max(8, Math.round(size * 0.6))).font_bold().text_color(t.muted)
        .child(label[0].toUpperCase());
    }
    if (a.tint) return svg(a.icon).size(size).flex_none().text_color(t.foreground);
    return image(a.icon).size(size).flex_none();
  }

  agentGlyph(id, t, size = 16) {
    const known = this.knownOf(id);
    if (known) return this.programIcon(known, t, size);
    // not in the program table: fall back to this mod's bundled brand marks
    const local = LOCAL_ICONS[id];
    if (local) {
      // bundled brand marks follow the same two-case rule as the menu
      if (local.tint) return svg(`mods/session-history/icons/${local.file}`).size(size).flex_none().text_color(t.foreground);
      return image(`mods/session-history/icons/${local.file}`).size(size).flex_none();
    }
    return this.programIcon({ key: id, label: this.agentName(id) }, t, size);
  }

  // The program-table entry for a store id, following NAME_ALIASES.
  knownOf(id) {
    const direct = this.icons[id];
    if (direct) return direct;
    for (const alt of NAME_ALIASES[id] ?? []) {
      if (this.icons[alt]) return this.icons[alt];
    }
    return null;
  }

  // Official display name, exactly as the launcher menu shows it.
  agentName(id) {
    const known = this.knownOf(id);
    if (known?.name) return known.name;
    return (AGENTS.find((a) => a.id === id) ?? {}).label ?? id;
  }

  watchRoots() {
    const h = home();
    return [
      `${h}/.claude/projects`,
      `${h}/.codex/sessions`,
      `${h}/.pi/agent/sessions`,
      `${h}/.omp/agent/sessions`,
      `${h}/.gemini/tmp`,
      `${h}/.local/share/opencode`,
      `${h}/.zcode/cli/agents`,
    ];
  }

  async refresh(cx) {
    // one scan at a time: watch storms coalesce into a single follow-up
    if (this.scanning) {
      this.pendingScan = true;
      return;
    }
    const token = ++this.token;
    this.scanning = true;
    this.loading = true;
    this.error = null;
    cx.notify();
    try {
      const r = await exec("bash", [
        `${appHome()}/mods/session-history/scan.sh`,
        "--limit", "4000",
        "--cache", `${appHome()}/data/session-history/index.json`,
        "--budget-ms", "8000",
      ], { timeout: 60000 });
      if (token !== this.token) return;
      if (r.code !== 0) {
        const raw = (r.stderr || r.stdout || `scan exited ${r.code}`).trim().slice(0, 240);
        this.error = /python3|scan\.sh/.test(raw)
          ? "Scanner needs python3 (macOS: xcode-select --install)"
          : raw;
        this.sessions = [];
      } else {
        // the scanner writes the (megabyte-scale) result to a file and prints
        // only a pointer: a big write into the exec pipe can block forever if
        // a hot reload abandons the reading side
        const data = JSON.parse((r.stdout || "").trim() || "{}" );
        this.sessions = Array.isArray(data.sessions) ? data.sessions : [];
        this.sources = (data.sources && typeof data.sources === "object") ? data.sources : {};
        this.partial = Boolean(data.partial);
        this.lastAt = Date.now();
        this._dirty = true;
        this.scheduleRebuild(cx);
        this.error = null;
      }
    } catch (e) {
      if (token !== this.token) return;
      this.error = String(e?.message || e).slice(0, 240);
      this.sessions = [];
    }
    this.scanning = false;
    this.loading = false;
    this.lastDone = Date.now();
    cx.notify();
    if (this.pendingScan) {
      this.pendingScan = false;
      await this.refresh(cx);
    }
  }

  // Filtering/grouping over a 2k+ catalog blows the render budget (an
  // interrupted render never recovers — _dirty stays set), so it runs in a
  // spawned task instead of inside render; render only reads this._cache.
  scheduleRebuild(cx) {
    if (this._rebuilding || this.mode !== "panel" || checking()) return;
    this._rebuilding = true;
    cx.spawn(async (cx) => {
      try {
        const ctx = this.buildContext();
        const list = this.filtered(ctx);
        // bucket by owning space in one pass — the old per-space filter ran
        // spaces × entries × two regexes and was what got renders interrupted
        const bySpace = new Map();
        const groups = new Map();
        for (const s of list) {
          const owner = ctx.cwdSpace.get(this.normPath(s.cwd));
          if (owner) {
            let b = bySpace.get(owner.id);
            if (!b) bySpace.set(owner.id, (b = []));
            b.push(s);
          }
          const key = this.normPath(s.cwd) || "(no folder)";
          let g = groups.get(key);
          if (!g) groups.set(key, (g = []));
          g.push(s);
        }
        const pjGroups = [...groups.entries()].sort((a, b) => (b[1][0]?.mtime || 0) - (a[1][0]?.mtime || 0));
        const spMembers = ctx.spacesNow.map((sp) => ({ sp, members: bySpace.get(sp.id) || [] }));
        this._cache = { list, pjGroups, spMembers };
        this._dirty = false;
      } finally {
        this._rebuilding = false;
      }
      cx.notify();
    });
  }

  normPath(p) {
    // Normalize separators and case so Windows paths compare consistently.
    // Memoized: session cwds repeat heavily and this sits inside per-pair
    // loops — an interrupted render once died inside the regex here.
    const key = String(p ?? "");
    let v = this._normCache.get(key);
    if (v === undefined) {
      v = key.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
      this._normCache.set(key, v);
    }
    return v;
  }

  // ONE snapshot per render: panes()/spaces() each cross the mod boundary and
  // copying them per row was slow enough to hit the render time budget
  // ("interrupted") on space switches. Every helper below consumes ctx.
  buildContext() {
    const spacesNow = spaces();
    const panesNow = panes();
    const cwdSpace = new Map();  // normalized cwd -> space (pane cwd wins)
    for (const sp of spacesNow) {
      const n = this.normPath(sp.folder);
      if (n && !cwdSpace.has(n)) cwdSpace.set(n, sp);
    }
    for (const p of panesNow) {
      if (!p.terminal) continue;
      const n = this.normPath(p.cwd);
      if (!n) continue;
      if (!cwdSpace.has(n)) {
        const sp = spacesNow.find((s) => (s.tabs || []).some((t) => t.id === p.tab));
        if (sp) cwdSpace.set(n, sp);
      }
    }
    return { spacesNow, cwdSpace };
  }

  spaceLabelFor(cwd, ctx) {
    if (!ctx) ctx = this.buildContext();
    return (ctx.cwdSpace.get(this.normPath(cwd)) || {}).name || null;
  }

  filtered(ctx) {
    const q = (this.filter || "").trim().toLowerCase();
    const scope = scopeOf();
    const allow = new Set(agentsOf().map((a) => a.id));
    return this.sessions.filter((s) => {
      if (allow.size && !allow.has(s.agent)) return false;
      if (scope.id === "spaces" && !this.assignSpace(s, ctx)) return false;
      if (!q) return true;
      const hay = `${s.agent} ${this.agentName(s.agent)} ${s.folder || ""} ${s.cwd || ""} ${s.preview || ""} ${s.first_prompt || ""} ${s.model || ""} ${s.id || ""}`.toLowerCase();
      return hay.includes(q);
    });
  }

  // Which space a session belongs to: the space with a live terminal in this
  // cwd, else the space whose root folder matches. Null = no space claims it.
  assignSpace(s, ctx) {
    if (!ctx) ctx = this.buildContext();
    return ctx.cwdSpace.get(this.normPath(s.cwd)) || null;
  }

  resume(s) {
    if (!s?.argv?.length) return;
    const folder = s.cwd || activeFolder() || home();
    const name = s.folder || s.agent || "session";
    const argv = s.argv;
    // Exact-match space else a new one, so Spaces shows where it really lives.
    const existing = this.spaceForFolder(folder);
    if (existing) {
      run("tab.new", { name, space: existing.id, folder, argv });
      if (!existing.active) run("space.select", { id: existing.id });
      return;
    }
    run("space.new", { name, folder, argv });
  }

  toggleAgent(id, cx) {
    const cur = agentsOf().map((a) => a.id);
    const next = cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id];
    setShared("session-history.agents", next.length ? next : AGENTS.map((a) => a.id));
    this._dirty = true;
    this.scheduleRebuild(cx);
  }

  // Orca-style: select the transcript in Finder / Explorer.
  reveal(s) {
    revealPath(s.path);
  }

  // Two-step: first click arms, second click deletes the transcript for real.
  // ZCode rows point at a sess_<id> directory; rm -rf / Remove-Item -Recurse
  // handle both shapes.
  delete(s, cx) {
    if (this.confirmDelete !== s.path) {
      this.confirmDelete = s.path;
      cx.notify();
      return;
    }
    this.confirmDelete = null;
    this.expanded = null;
    cx.notify();
    removePath(s.path)
      .then(() => this.refresh(cx))
      .catch(() => this.refresh(cx));
  }

  chip(t, id, label, on, onClick) {
    return div()
      .id(id)
      .px(8)
      .h(22)
      .rounded(6)
      .text_size(10.5)
      .font_medium()
      .flex()
      .items_center()
      .cursor_pointer()
      .when(on, (el) => el.bg(t.selected).text_color(t.foreground))
      .when(!on, (el) => el.bg(t.raised).text_color(t.dim).hover((el) => el.bg(t.hover).text_color(t.foreground)))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        onClick(cx);
      })
      .child(label);
  }

  agentsMenu(t) {
    const agents = agentsOf();
    return v_flex()
      .w_full()
      .p(5)
      .text_size(12.8)
      .child(div().px(8).pt(4).pb(6).text_size(11).text_color(t.dim).child("Agents to scan"))
      .children(AGENTS.map((a) => {
        const on = agents.some((x) => x.id === a.id);
        const prog = (this.icons || {})[a.id];
        const logo = this.programIcon(prog ?? { key: a.id, label: a.label }, t, 14);
        return h_flex()
          .id(`menu-agent-${a.id}`)
          .h(31)
          .px(8)
          .gap(9)
          .rounded(7)
          .items_center()
          .text_color(t.foreground)
          .hover((el) => el.bg(t.hover))
          .on_click((_e, cx) => {
            cx.stop_propagation();
            this.toggleAgent(a.id, cx);
            cx.notify();
          })
          .child(logo)
          .child(div().flex_1().child(this.agentName(a.id)))
          .when(on, (el) => el.child(svg("mods/workspace-chrome/check.svg").size(14).flex_none().text_color(t.foreground)));
      }));
  }

  // ── M3 actions ──────────────────────────────────────────────────────────

  openLog(s) {
    run("tab.new", { name: `日志 · ${s.folder || s.agent}`, mod: "session-history", props: { viewer: { path: s.path, agent: s.agent } } });
  }

  // Orca's 在工作树中恢复: pick a space of the same repo (same git common
  // dir); the session resumes in a new tab there. No match → a toast.
  resumeInWorktree(s, cx) {
    cx.spawn(async (cx) => {
      const norm = (p) => String(p || "").replace(/\/+$/, "");
      let common = "";
      try {
        const r = await exec("git", ["-C", s.cwd, "rev-parse", "--git-common-dir"], { timeout: 8000 });
        common = r.stdout.trim();
      } catch {}
      if (!common) {
        notify({ title: "会话历史", body: "该会话目录不是 git 仓库，无法选择 worktree" });
        return;
      }
      if (!common.startsWith("/")) common = `${s.cwd}/${common}`;
      const same = [];
      for (const sp of spaces()) {
        if (!sp.folder) continue;
        try {
          const r = await exec("git", ["-C", sp.folder, "rev-parse", "--git-common-dir"], { timeout: 8000 });
          let dir = r.stdout.trim();
          if (dir && !dir.startsWith("/")) dir = `${sp.folder}/${dir}`;
          if (dir && norm(dir) === norm(common)) same.push(sp);
        } catch {}
      }
      if (!same.length) {
        notify({ title: "会话历史", body: "没有找到同一仓库的 worktree space——先创建 worktree 再试" });
        return;
      }
      openOverlay({ mod: "session-history", kind: "popup", width: 380, height: same.length * 36 + 60, props: { wtPicker: true, session: s, list: same } });
    });
  }

  handoff(s) {
    openOverlay({ mod: "session-history", kind: "popup", width: 380, height: 430, props: { handoff: { session: s } } });
  }

  // ── popup / viewer renders ──────────────────────────────────────────────

  actionsMenuView(cx) {
    const t = theme(), p = props() ?? {};
    const s = p.session ?? {};
    const item = (id, label, fn, disabled) =>
      h_flex().id(`am-${id}`).h(28).px(8).gap(8).rounded(6).items_center().text_size(12)
        .text_color(disabled ? t.dim : t.foreground)
        .cursor_pointer()
        .hover((w) => w.bg(t.hover))
        .when(!disabled, (r) => r.on_click((_e, c) => {
          c.stop_propagation();
          closeOverlay(p.overlay);
          fn(c);
        }))
        .child(label);
    return v_flex().id("sh-actions").w_full().p(5).gap(1).text_size(12).children([
      item("cmd", "复制恢复命令", () => copyText(s.argv.join(" ")), !s.argv?.length),
      item("cid", "复制会话 ID", () => copyText(s.id)),
      item("cpath", "复制日志路径", () => copyText(s.path)),
      item("log", "打开日志", () => this.openLog(s)),
      item("cwd", "打开工作目录", () => openDir(s.cwd), !s.cwd),
      item("reveal", "在 Finder 中显示", () => revealPath(s.path)),
      item("wt", "在工作树中恢复…", (c) => this.resumeInWorktree(s, c), !s.argv?.length || !s.cwd),
      item("handoff", "移交给另一个代理…", (c) => this.handoff(s), !s.cwd),
    ]);
  }

  worktreePickView(cx) {
    const t = theme(), p = props() ?? {};
    const s = p.session ?? {};
    const same = p.list || [];
    return v_flex().id("sh-wt").size_full().p(10).gap(4).bg(t.canvas).text_size(12.5).text_color(t.foreground)
      .child(h_flex().gap(8).items_center()
        .child(div().flex_1().text_size(13).font_semibold().child("在工作树中恢复"))
        .when(p.overlay, (r) => r.child(div().id("sh-w-close").size(22).rounded(6).flex().items_center().justify_center().text_color(t.dim).cursor_pointer().hover((w) => w.bg(t.hover)).on_click((_e, c) => closeOverlay(p.overlay)).child("✕"))))
      .child(div().text_size(11).text_color(t.dim).child("选择同一仓库的 worktree space，会话将在那里的新 tab 继续"))
      .children(same.map((sp) =>
        h_flex().id(`wt-${sp.id}`).gap(8).items_center().px(8).py(6).rounded(6).cursor_pointer()
          .hover((w) => w.bg(t.hover))
          .on_click((_e, c) => {
            c.stop_propagation();
            closeOverlay(p.overlay);
            run("space.select", { id: sp.id });
            run("tab.new", { name: s.folder || s.agent || "session", space: sp.id, folder: sp.folder, argv: s.argv });
          })
          .child(div().flex_1().min_w(0).truncate().child(sp.name))
          .child(div().flex_none().max_w(150).truncate().text_size(10.5).text_color(t.dim).child(sp.folder || ""))));
  }

  handoffView(cx) {
    const t = theme(), p = props() ?? {};
    const h = this.h, s = h.session;
    const ready = h.pick && (h.agents || []).find((x) => x.key === h.pick);
    return v_flex().id("sh-handoff").size_full().p(14).gap(9).bg(t.canvas).text_size(12.5).text_color(t.foreground)
      .child(h_flex().gap(8).items_center()
        .child(div().flex_1().text_size(14).font_semibold().child("移交给另一个代理"))
        .when(p.overlay, (r) => r.child(div().id("sh-h-close").size(22).rounded(6).flex().items_center().justify_center().text_color(t.dim).cursor_pointer().hover((w) => w.bg(t.hover)).on_click((_e, c) => closeOverlay(p.overlay)).child("✕"))))
      .child(div().text_size(11).text_color(t.dim).child(`从这条历史会话的进度启动一个新的代理会话（${s.folder || s.cwd || "无目录"}），原会话保持不变`))
      .when(h.error, (r) => r.child(div().p(8).rounded(8).bg(t.raised).text_color(t.blocked).child(h.error)))
      .when(h.agents === null, (r) => r.child(div().text_color(t.dim).child("读取代理列表…")))
      .when(Array.isArray(h.agents), (r) => r.child(v_flex().gap(2).overflow_y_scrollbar().max_h(160).children(h.agents.map((a) =>
        h_flex().id(`hh-${a.key}`).gap(8).items_center().px(8).h(28).rounded(6)
          .when(h.pick === a.key, (e) => e.bg(t.selected))
          .hover((w) => w.bg(t.hover)).cursor_pointer()
          .on_click((_e, c) => { h.pick = a.key; c.notify(); })
          .child(div().flex_1().truncate().child(a.name))
          .child(div().flex_none().text_size(10.5).text_color(t.dim).child(a.key)))))
      .child(v_flex().gap(2).children([{ id: "focused", name: "聚焦续接（推荐）" }, { id: "full", name: "完整历史" }].map((m) =>
        h_flex().id(`hm-${m.id}`).gap(8).items_center().px(8).py(5).rounded(6)
          .when(h.mode === m.id, (e) => e.bg(t.selected))
          .hover((w) => w.bg(t.hover)).cursor_pointer()
          .on_click((_e, c) => { h.mode = m.id; c.notify(); })
          .child(div().size(12).rounded(6).border(1).border_color(h.mode === m.id ? t.accent : t.input).flex().items_center().justify_center()
            .when(h.mode === m.id, (e) => e.child(div().size(6).rounded(3).bg(t.accent))))
          .child(div().child(m.name)))))
      .when(h.sum && !h.sum.ok, (r) => r.child(div().text_size(11).text_color(t.blocked).child(`原会话不可读：${h.sum.reason ?? ""}`)))
      .when(h.sum?.ok, (r) => r.child(div().text_size(11).text_color(t.dim).truncate().child(`原会话 ${String(h.sum.id || "").slice(0, 8)} · ${h.sum.count ?? "?"} 条消息`))))
      .child(div().flex_1())
      .child(h_flex().gap(8).justify_end()
        .child(div().id("sh-h-cancel").px(12).py(6).rounded(7).cursor_pointer().hover((w) => w.bg(t.hover)).on_click((_e, c) => closeOverlay(p.overlay)).child("取消"))
        .when(ready, (r) => r.child(div().id("sh-h-go").px(14).py(6).rounded(7).bg(t.accent).text_color(t.accent_foreground || t.background).font_semibold().cursor_pointer().hover((w) => w.bg(t.done)).on_click((_e, c) => this.hLaunch(c)).child("启动新会话"))));
  }

  // The brief mirrors agent-handoff's: ends of the conversation plus the
  // workspace, with the transcript path for anything earlier.
  hBrief() {
    const h = this.h, s = h.session, sum = h.sum ?? {};
    const lines = [`[移交] 接手 ${s.agent} 的一条历史会话，继续在同一目录完成任务。`];
    lines.push(`原会话: ${s.path}（完整记录，需要更早细节时直接读它）`);
    if (sum.firstUser) lines.push(`最初任务: ${sum.firstUser}`);
    if (h.mode === "full") {
      lines.push("先用工具通读原会话记录，完整了解此前进展，不要凭空猜测。");
    } else if (sum.lastUsers?.length) {
      lines.push(`最近进展（原会话的指令）:\n${sum.lastUsers.map((u, i) => `${i + 1}. ${u}`).join("\n")}`);
    }
    if (sum.lastAssistant) lines.push(`最后交底: ${sum.lastAssistant}`);
    lines.push(`工作区: ${s.cwd || "(未知目录)"}`);
    lines.push("先核对当前状态（git status / git diff），再继续完成任务。");
    return lines.filter(Boolean).join("\n");
  }

  hLaunch(cx) {
    const h = this.h, s = h.session;
    const a = (h.agents || []).find((x) => x.key === h.pick);
    if (!a || !s.cwd) return;
    closeOverlay(props()?.overlay);
    run("space.new", { name: `${s.folder || s.agent} · 移交`, folder: s.cwd, argv: a.run, task: this.hBrief() });
  }

  viewerView(cx) {
    const t = theme();
    return v_flex().id("sh-viewer").size_full().bg(t.background).text_color(t.foreground)
      .child(
        h_flex().h(38).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
          .child(div().flex_none().text_size(13).font_semibold().child(`日志 · ${this.viewer.agent}`))
          .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(this.viewer.path)),
      )
      .when(this.viewerError, (r) => r.child(div().p(12).text_size(12).text_color(t.blocked).child(this.viewerError)))
      .child(
        div()
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .p(12)
          .text_size(11)
          .text_color(t.foreground)
          .when(!this.viewerError, (r) => r.child(this.viewerText ?? "读取中…")),
      );
  }

  // Orca's per-source progress header: one row per transcript store with a
  // fill bar and an indexed/total count; click the header to fold it.
  sourcesBlock(t) {
    const ORDER = ["claude", "codex", "pi", "omp", "gemini", "opencode", "zcode"];
    const rows = Object.entries(this.sources || {})
      .filter(([id, v]) => v && v.total > 0)
      .sort((a, b) => {
        const ia = ORDER.indexOf(a[0]);
        const ib = ORDER.indexOf(b[0]);
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
      });
    const { indexed, total } = this.indexedRatio();
    const done = indexed >= total && total > 0;
    const head = h_flex()
      .id("sh-sources-head")
      .px(12)
      .py(5)
      .gap(8)
      .flex_none()
      .items_center()
      .cursor_pointer()
      .hover((el) => el.bg(t.hover))
      .on_click((_e, c) => {
        c.stop_propagation();
        this.sourcesOpen = !this.sourcesOpen;
        c.notify();
      })
      .child(div().text_size(11).font_semibold().text_color(t.muted).child("来源"))
      .child(div().flex_1())
      .child(
        div()
          .text_size(10.5)
          .text_color(done ? t.done : t.dim)
          .child(rows.length ? (done ? `✓ ${total}` : `${indexed} / ${total}`) : ""),
      )
      .child(div().text_size(10).text_color(t.dim).child(this.sourcesOpen ? "▾" : "▸"));
    if (!rows.length || !this.sourcesOpen) return head;
    return v_flex()
      .flex_none()
      .px(12)
      .pt(4)
      .gap(3)
      .child(head)
      .children(rows.map(([id, v]) => {
        const pct = v.total > 0 ? Math.min(1, v.indexed / v.total) : 0;
        const full = v.indexed >= v.total;
        const label = this.agentName(id);
        return h_flex()
          .id(`sh-src-${id}`)
          .h(18)
          .gap(6)
          .flex_none()
          .items_center()
          .child(this.agentGlyph(id, t, 14))
          .child(
            div()
              .w(74)
              .flex_none()
              .truncate()
              .text_size(10.5)
              .text_color(t.muted)
              .child(label),
          )
          .child(
            div()
              .w(110)
              .h(3)
              .flex_none()
              .rounded(2)
              .bg(t.raised)
              .child(
                div()
                  .w(Math.max(full ? 110 : 2, Math.round(110 * pct)))
                  .h(3)
                  .flex_none()
                  .rounded(2)
                  .bg(full ? t.done : t.accent),
              ),
          )
          .child(
            div()
              .text_size(10)
              .text_color(full ? t.done : t.dim)
              .child(full ? `${v.indexed} ✓` : `${v.indexed}/${v.total}`),
          );
      }));
  }

  // Indexed/total across stores: the head pass's visible progress.
  indexedRatio() {
    const rows = Object.entries(this.sources || {});
    const sum = (sel) => rows.reduce((n, [, v]) => n + (sel(v) || 0), 0);
    return { indexed: sum((v) => v.indexed), total: sum((v) => v.total) };
  }

  render(cx) {
    if (this.mode === "viewer") return this.viewerView(cx);
    const t = theme();
    if (this.mode === "handoff") return this.handoffView(cx);
    if (this.mode === "menu") {
      const mp = props() ?? {};
      if (mp.actionsMenu) return this.actionsMenuView(cx);
      if (mp.wtPicker) return this.worktreePickView(cx);
      return this.agentsMenu(t);
    }
    if (props()?.agentsMenu) return this.agentsMenu(t);
    const ctx = this.buildContext();
    const scope = scopeOf();
    const agents = agentsOf();
    // The cache is rebuilt by scheduleRebuild's spawned task (render must not
    // run the 2k+ rebuild — an interrupted render never recovers). Until it
    // lands, show the chrome with a placeholder line.
    if (!this._cache) {
      return v_flex()
        .id("session-history")
        .size_full()
        .min_h(0)
        .overflow_hidden()
        .bg(t.background)
        .text_color(t.foreground)
        .child(this.sourcesBlock(t))
        .child(div().px(12).py(10).text_size(12).text_color(t.dim).child(this.loading ? "Scanning sessions…" : "整理会话索引…"));
    }
    const { list, pjGroups, spMembers } = this._cache;

    const row = (s, i) => {
      const open = this.expanded === s.path;
      return v_flex()
        .id(`sess-${s.agent}-${i}`)
        .flex_none()
        .px(9)
        .py(7)
        .gap(4)
        .rounded(8)
        .cursor_pointer()
        .when(open, (el) => el.bg(t.raised))
        .when(!open, (el) => el.hover((el) => el.bg(t.hover)))
        .on_click((_e, c) => {
          this.expanded = open ? null : s.path;
          c.notify();
        })
        .child(
          h_flex()
            .items_center()
            .gap(8)
            .child(this.agentGlyph(s.agent, t, 16))
            .child(div().flex_1().min_w(0).truncate().text_size(12).text_color(t.foreground).child(this.spaceLabelFor(s.cwd, ctx) || s.folder || s.cwd || s.id))
            .child(div().text_size(10.5).text_color(t.dim).child(age(s.mtime))),
        )
        .when(Boolean(s.preview), (el) =>
          el.child(div().pl(24).text_size(11).text_color(t.muted).truncate().child(s.preview)),
        )
        .when(open, (el) =>
          el
            .child(div().pl(24).pt(2).text_size(10.5).text_color(t.dim).truncate().child(s.cwd || "(no folder recorded)"))
            .when(s.msgs != null || Boolean(s.model), (el) =>
              el.child(
                h_flex()
                  .pl(24)
                  .gap(10)
                  .pt(1)
                  .when(s.msgs != null, (el2) =>
                    el2.child(div().text_size(10.5).text_color(t.dim).child(`${s.msgs} 条消息`)),
                  )
                  .when(Boolean(s.model), (el2) =>
                    el2.child(div().text_size(10.5).text_color(t.dim).truncate().child(String(s.model))),
                  ),
              ),
            )
            .when(Boolean(s.first_prompt), (el) =>
              el.child(
                v_flex()
                  .pl(24)
                  .pt(2)
                  .gap(2)
                  .child(div().text_size(10).text_color(t.dim).child("首次提示"))
                  .child(
                    div()
                      .px(8)
                      .py(6)
                      .rounded(6)
                      .bg(t.raised)
                      .text_size(11)
                      .text_color(t.muted)
                      .child(String(s.first_prompt)),
                  ),
              ),
            )
            .child(
              h_flex()
                .pl(24)
                .gap(6)
                .pt(3)
                // ZCode rows carry no argv: ⋯ menu holds the view-only actions.
                .when(Boolean(s.argv?.length), (el) =>
                  el.child(
                    div()
                      .id(`resume-${s.agent}-${i}`)
                      .px(10)
                      .h(24)
                      .rounded(6)
                      .bg(t.accent)
                      .text_color(t.accent_foreground || t.background)
                      .text_size(11)
                      .font_semibold()
                      .flex()
                      .items_center()
                      .cursor_pointer()
                      .on_click((_e, c) => {
                        c.stop_propagation();
                        this.resume(s);
                      })
                      .child("Resume"),
                  ),
                )
                .child(
                  div()
                    .id(`more-${s.agent}-${i}`)
                    .px(8)
                    .h(24)
                    .rounded(6)
                    .border_1()
                    .border_color(t.border)
                    .text_size(12)
                    .text_color(t.dim)
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(26)
                    .hover((el) => el.bg(t.hover).text_color(t.foreground))
                    .tooltip("更多操作")
                    .on_click((_e, c) => {
                      c.stop_propagation();
                      openOverlay({ mod: "session-history", kind: "popup", width: 210, height: 8 * 29 + 16, props: { actionsMenu: true, session: s } });
                    })
                    .child("⋯"),
                )
                .when(this.confirmDelete === s.path, (el) =>
                  el
                    .child(
                      div()
                        .id(`delete-yes-${s.agent}-${i}`)
                        .px(8)
                        .h(24)
                        .rounded(6)
                        .bg(t.blocked)
                        .text_color(t.background)
                        .text_size(10.5)
                        .font_semibold()
                        .flex()
                        .items_center()
                        .cursor_pointer()
                        .on_click((_e, c) => {
                          c.stop_propagation();
                          this.delete(s, c);
                        })
                        .child("Delete?"),
                    )
                    .child(
                      div()
                        .id(`delete-no-${s.agent}-${i}`)
                        .px(6)
                        .h(24)
                        .text_size(10.5)
                        .text_color(t.dim)
                        .hover((el) => el.text_color(t.foreground))
                        .on_click((_e, c) => {
                          c.stop_propagation();
                          this.confirmDelete = null;
                          c.notify();
                        })
                        .child("Keep it"),
                    ),
                )
                .when(this.confirmDelete !== s.path, (el) =>
                  el.child(
                    div()
                      .id(`delete-${s.agent}-${i}`)
                      .px(8)
                      .h(24)
                      .rounded(6)
                      .border_1()
                      .border_color(t.border)
                      .text_size(10.5)
                      .text_color(t.blocked)
                      .flex()
                      .items_center()
                      .hover((el) => el.bg(t.hover))
                      .tooltip("Permanently delete this transcript")
                      .on_click((_e, c) => {
                        c.stop_propagation();
                        this.delete(s, c);
                      })
                      .child("Delete"),
                  ),
                ),
            ),
        );
    };

    // A foldable section header, Orca-style: name, divider, count.
    const groupHeader = (gid, label, count, folded) =>
      h_flex()
        .id(`sh-group-${gid}`)
        .flex_none()
        .px(6)
        .pt(8)
        .pb(3)
        .gap(6)
        .items_center()
        .cursor_pointer()
        .hover((el) => el.bg(t.hover))
        .on_click((_e, c) => {
          c.stop_propagation();
          this.folds[gid] = !folded;
          c.notify();
        })
        .child(div().text_size(10).text_color(t.dim).w(12).child(folded ? "▸" : "▾"))
        .child(div().text_size(10.5).font_semibold().text_color(t.dim).truncate().child(label))
        .child(div().flex_1().h(1).bg(t.border))
        .child(div().text_size(10).text_color(t.dim).child(String(count)));

    // Flat descriptors (headers + member rows) for the paged list; only the
    // visible slice becomes elements.
    const items = [];
    if (scope.id === "spaces") {
      for (const { sp, members } of spMembers) {
        if (!members.length) continue;
        const folded = Boolean(this.folds[`sp-${sp.id}`]);
        items.push({ t: "group", gid: `sp-${sp.id}`, label: sp.name, count: members.length, folded });
        if (folded) continue;
        for (const s of members) items.push({ t: "row", s });
      }
    } else if (scope.id === "projects") {
      for (const [key, members] of pjGroups) {
        const folded = Boolean(this.folds[`pj-${key}`]);
        items.push({ t: "group", gid: `pj-${key}`, label: members[0].folder || key.split("/").pop() || key, count: members.length, folded });
        if (folded) continue;
        for (const s of members) items.push({ t: "row", s });
      }
    } else {
      for (const s of list) items.push({ t: "row", s });
    }

    return v_flex()
      .id("session-history")
      .size_full()
      .min_h(0)
      .rounded(10)
      .overflow_hidden()
      .bg(t.background)
      .border_1()
      .border_color(t.border)
      .text_size(13)
      .text_color(t.foreground)
      .child(
        h_flex()
          .h(42)
          .flex_none()
          .px(14)
          .gap(8)
          .items_center()
          .border_b(1)
          .border_color(t.border)
          .child(div().font_semibold().child("会话历史"))
          .child(div().flex_1())
          .child(
            div()
              .id("sh-refresh")
              .size(26)
              .rounded(6)
              .flex()
              .items_center()
              .justify_center()
              .cursor_pointer()
              .text_color(t.dim)
              .hover((el) => el.bg(t.hover).text_color(t.foreground))
              .tooltip("重新扫描")
              .on_click((_e, c) => this.refresh(c))
              .child(
                svg("mods/usage-limits/icons/refresh.svg")
                  .size(14)
                  .flex_none()
                  .when(this.loading, (el) => el.spin(900).text_color(t.accent)),
              ),
          ),
      )
      .child(this.sourcesBlock(t))
      .child(
        h_flex()
          .px(12)
          .py(8)
          .gap(4)
          .flex_none()
          .children(SCOPES.map((s) => this.chip(t, `scope-${s.id}`, s.label, scope.id === s.id, (c) => {
            setShared("session-history.scope", s.id);
            this._dirty = true;
            this.scheduleRebuild(cx);
            cx.notify();
          })))
          .child(div().flex_1())
          .child(
            // Agent filter as a dropdown: keeps the header to one row.
            h_flex()
              .id("sh-agents-menu")
              .px(8)
              .h(22)
              .gap(5)
              .rounded(6)
              .text_size(10.5)
              .font_medium()
              .flex()
              .items_center()
              .cursor_pointer()
              .bg(t.raised)
              .text_color(t.foreground)
              .hover((el) => el.bg(t.hover))
              .on_click((_e, c) => {
                c.stop_propagation();
                openOverlay({ mod: "session-history", kind: "popup", width: 200, height: AGENTS.length * 32 + 26, props: { agentsMenu: true } });
              })
              .child(svg("mods/workspace-chrome/layers.svg").size(12).text_color(t.dim))
              .child(`Agents (${agents.length})`),
          ),
      )
      .child(
        div()
          .px(12)
          .pb(8)
          .flex_none()
          .child(
            Input.new(this.input)
              .h(28)
              .px(10)
              .rounded(7)
              .border_1()
              .border_color(t.input)
              .bg(t.background)
              .text_size(12)
              .text_color(t.foreground),
          ),
      )
      .when(list.length > 0 || this.partial, (el) =>
        el.child(
          h_flex()
            .px(12)
            .pb(6)
            .flex_none()
            .items_center()
            .child(div().text_size(11).font_semibold().text_color(t.muted).child(`${list.length} 个会话`))
            .child(div().flex_1())
            .child(
              div()
                .text_size(10.5)
                .text_color(t.dim)
                .child(
                  this.partial
                    ? `索引中 ${(() => { const r = this.indexedRatio(); return `${r.indexed}/${r.total}`; })()} — 统计在后台继续补全`
                    : this.lastAt
                      ? `已索引 · ${age(this.lastAt)}刷新`
                      : "",
                ),
            ),
        ),
      )
      .when(Boolean(this.error), (el) =>
        el.child(div().px(12).pb(8).text_size(11).text_color(t.blocked).child(this.error)),
      )
      .when(this.loading && list.length === 0, (el) =>
        el.child(div().px(12).text_size(12).text_color(t.dim).child("Scanning sessions…")),
      )
      .when(!this.loading && list.length === 0 && !this.error, (el) =>
        el.child(
          div()
            .px(12)
            .text_size(12)
            .text_color(t.dim)
            .child(
              scope.id === "spaces"
                ? "此工作区还没有会话。切换到「项目」或「全部」查看磁盘上的历史。"
                : scope.id === "projects"
                  ? "没有匹配的会话。换一个搜索词，或切换到「全部」。"
                  : "扫描的会话存储里还没有记录。",
            ),
        ),
      )
      .child(
        div()
          .flex_1()
          .min_h(0)
          .relative()
          .child(
            v_flex()
              .id("sh-list")
              .size_full()
              .px(6)
              .pb(6)
              .gap(1)
              .overflow_y_scrollbar()
              .children((() => {
                // gpui-kit's `list` never painted rows here (cause unknown),
                // so this stays a plain scroll list with a render cap
                const CAP = 50;
                const shown = items.slice(0, CAP).map((it, i) =>
                  it.t === "group"
                    ? groupHeader(it.gid, it.label, it.count, it.folded)
                    : row(it.s, i));
                if (items.length > CAP) {
                  shown.push(div().px(8).py(6).text_size(11).text_color(t.dim).child(`已显示 ${CAP} / ${items.length} 行 — 用筛选缩小范围`));
                }
                return shown;
              })()),
          )
          .child(Scrollbar.vertical("sh-list").viewport_from_layout().absolute().inset_0()),
      );
  }
}
