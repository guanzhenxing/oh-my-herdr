import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme, window, shared, layout, settings, exec, focused, nextCommand } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// Same as the agents mod: drops a status glyph, keeps a leading bracket or quote.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").replace(/^\[ [!.] \] /, "").trim();

// A tab Herdr named (unnamed, or after its program) follows its agent's live
// title, as the agents list does; a name the person gave stays.
function label(tab, lead) {
  const prog = lead?.program?.name;
  const base = tab.named ? tab.name : prog ?? "Terminal";
  if (!lead?.program?.agent) return base;
  const live = clean(lead.title);
  // clean() would strip a path's leading ~ or /: test the title with only its status glyph gone.
  const path = /^[~/]|^[A-Za-z]:\\/.test((lead.title ?? "").replace(/^[^\p{L}\p{N}~/]+/u, ""));
  const telling = live && live !== lead.terminal && live !== prog && !path && !live.includes("@") && live.toLowerCase() !== lead.program.key;
  return (tab.name === prog || !tab.named) && telling ? live : base;
}

// Whether a space is a linked git worktree (as the menu mod tells), from its first terminal's folder.
async function isWorktree(s) {
  const tabs = new Set(s.tabs.map((c) => c.id));
  const cwd = panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
  const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on: s.machine });
  const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on: s.machine });
  return top.code === 0 && common.code === 0 && common.stdout.trim() !== `${top.stdout.trim()}/.git`;
}

// Closing the last tab of a worktree space removes the worktree instead (the dialog checks first).
// ask: keys (cmd-w) confirm first; the last tab already asks through tab.close or the worktree dialog.
function closeTab(id, cx, ask = false) {
  const tab = id || focused()?.tab, s = spaces().find((x) => x.tabs.some((c) => c.id === tab));
  if (s && s.tabs.length > 1 && ask) {
    const name = s.tabs.find((c) => c.id === tab)?.name;
    return openOverlay({ mod: "confirm", kind: "dialog", width: 400, height: 170, props: {
      title: `Close tab “${name}”?`,
      detail: "Its terminals end, including any agents running in it.",
      command: { name: "tab.close", args: { id: tab } },
    } });
  }
  if (!s || s.tabs.length > 1) return run("tab.close", { id: tab });
  cx.spawn(async () => {
    const linked = await isWorktree(s).catch(() => false);
    if (linked) openOverlay({ mod: "my-worktree", kind: "dialog", width: 460, height: 350, props: { space: s.id, action: "remove" } });
    else run("tab.close", { id: tab });
  });
}

// The last pane of a tab closes the tab, so it goes through closeTab's worktree check.
function closePane(id, cx, ask = false) {
  const pane = id || focused()?.pane, p = panes().find((x) => x.pane === pane);
  if (!p || panes().filter((x) => x.tab === p.tab).length > 1) return run("pane.close", pane ? { pane } : {});
  closeTab(p.tab, cx, ask);
}

// Collapsing hides the whole sidebar; this button lives in the tab bar so it stays visible.
// Herdr's brand button shrinks it to a rail instead (on macOS it then hides itself), so a
// rail is turned into a hide at the width it had (the brand button saves it in sidebar.width).
function railToHidden(sidebar) {
  if (!sidebar || sidebar.hidden || (sidebar.size?.px ?? Infinity) >= 160) return;
  const width = shared("sidebar.width");
  run("layout.resize", { id: "sidebar", px: width >= 160 ? width : 268 });
  run("layout.hide", { id: "sidebar" });
}

export default class Tabs extends View {
  init(_props, cx) {
    this.pressed = null;
    try { this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}"); } catch { this.panels = {}; }
    if (!this.panels || typeof this.panels !== "object" || Array.isArray(this.panels)) this.panels = {};
    this.swipe = { acc: 0, steps: 0, at: 0, last: 0 };
    // "close-tab[:id]" / "close-pane[:id]" from cmd-w, cmd-shift-w (layout:oh-my-herdr-* keys) and my-menu's tab Close.
    // Only the keys send no id, so only they ask first; menu and button clicks close at once.
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "close-tab" || c.startsWith("close-tab:")) closeTab(c.slice("close-tab:".length), cx, c === "close-tab");
        else if (c === "close-pane" || c.startsWith("close-pane:")) closePane(c.slice("close-pane:".length), cx, c === "close-pane");
      }
    });
  }

  // One tab per wheel notch. A touchpad or smooth-scrolling mouse sends many
  // small events per gesture: a short swipe or one smoothed notch (about
  // 25 px) switches one tab, a longer swipe keeps going a tab per 60 px, at
  // most one every 100 ms so each shows.
  wheel(e) {
    if (e.delta_lines) {
      if (e.delta_lines.y) run(e.delta_lines.y > 0 ? "tab.prev" : "tab.next");
      return;
    }
    const s = this.swipe, now = Date.now();
    // Phases often arrive only as moves (a macOS touchpad included): a pause
    // or a turn starts a new gesture.
    if (e.touch_phase === "started" || now - s.at > 250 || e.delta.y * s.acc < 0) Object.assign(s, { acc: 0, steps: 0 });
    s.at = now;
    s.acc += e.delta.y;
    const need = s.steps ? 60 : 20;
    if (Math.abs(s.acc) < need || now - s.last < 100) return;
    s.acc -= Math.sign(s.acc) * need;
    s.steps++;
    s.last = now;
    run(e.delta.y > 0 ? "tab.prev" : "tab.next");
  }

  // The side panel is remembered per space: switching shows that space's choice
  // (closed if it never had one), and opening or closing it records it.
  syncPanel(space, panel, body, enabled) {
    if (!space || !panel) return;
    const now = panel.hidden ? null : body?.active ?? null;
    if (space.id !== this.space) {
      const first = this.space === undefined;
      this.space = space.id; this.pending = null;
      if (!(first && !(space.id in this.panels))) {
        const stored = this.panels[space.id] ?? null, want = enabled.includes(stored) ? stored : null;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          if (want) { run("layout.select", { stack: "panel-body", child: want }); run("layout.show", { id: "panel" }); }
          else run("layout.hide", { id: "panel" });
          return;
        }
      }
    }
    // Until the restore lands (or something else won), the old state isn't a choice.
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[space.id] === now) return;
    this.panels[space.id] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  }

  render() {
    const t = theme();
    const space = spaces().find(p => p.active);
    const shown = space?.tabs ?? [];
    const stop = (_e, cx) => cx.stop_propagation();
    const button = (id, label, action) => div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6).text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", stop).on_click(action).child(label);
    const item = (c, i) => {
      const lead = panes().find(p => p.tab === c.id && p.program?.agent) ?? panes().find(p => p.tab === c.id);
      const program = lead?.program;
      const name = label(c, lead);
      return h_flex().id(`tab-${c.id}`).h(29).px(10).gap(7).rounded(7).items_center().flex_none().text_size(12.8)
        .border(1).border_color(c.active ? t.border : t.chrome).bg(c.active ? t.raised : t.chrome).text_color(c.active ? t.foreground : t.muted)
        .hover(s => s.bg(t.hover))
        .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); this.pressed = i; if (e.click_count === 2) run("tab.rename", { id: c.id }); })
        .on_mouse_up("left", () => {
          const from = this.pressed; this.pressed = null;
          if (from !== null && from !== i) run("tab.move", { id: shown[from].id, index: space.tabs.findIndex(x => x.id === c.id) + 1 });
          else run("tab.select", { id: c.id });
        })
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "my-menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: c.id, space: space.id } } }); })
        .when(Boolean(program?.icon), el => el.child(program.tint ? svg(program.icon).size(14).text_color(t.muted) : image(program.icon).size(14)))
        .child(div().max_w(170).truncate().child(c.zoomed ? `${name} Z` : name))
        .when(c.status === "working", el => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)))
        .when(c.status === "blocked" || c.status === "done", el => el.child(div().size(6).rounded(3).bg(t[c.status])))
        .when(c.active, el => el.child(div().id(`close-${c.id}`).text_color(t.dim).on_mouse_down("left", stop).on_click((_e, cx) => { cx.stop_propagation(); closeTab(c.id, cx); }).child(svg("mods/pane/close.svg").size(12))));
    };
    const root = layout(), sidebar = find(root, "sidebar"), w = window();
    railToHidden(sidebar);
    // Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
    const lightsPadding = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      ? Math.max(10, (root.traffic_lights[0] + 64) / settings().zoom - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    const panel = find(root, "panel"), body = find(root, "panel-body");
    // Only panels the side panel has: Issues and Automations are popups now (sidebar-nav).
    const enabled = (shared("workspace.panels") ?? ["files", "changes"]).filter(id => body?.children?.some(c => c.id === id));
    this.syncPanel(space, panel, body, enabled);
    // syncPanel still auto-shows the remembered panel per space; the buttons
    // themselves live in mods/panel-head now.
    return h_flex().size_full().min_w(0).px(10).pl(lightsPadding).gap(3).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .on_mouse_up("left", () => { this.pressed = null; })
      .on_scroll_wheel(e => this.wheel(e))
      // One toggle at a time: while the sidebar shows, the brand button covers it;
      // this one appears only once the sidebar is hidden, so a way back is always visible.
      .when(Boolean(sidebar?.hidden), el => el.child(button("sidebar-toggle", svg("mods/workspace-chrome/sidebar.svg").size(15), () => run("layout.show", { id: "sidebar" }))
        .tooltip("Show sidebar")))
      // The + lives inside the scroll area, right after the last tab (browser-style).
      // Panel controls moved off this row: the right panel carries its own
      // header now (mods/panel-head) — Files/Changes segment + Excalidraw + ✕;
      // the row keeps only the 36px panel-toggle from the layout.
      .child(h_flex().id("tab-scroll").flex_1().min_w(0).h_full().items_center().gap(3).overflow_x_scrollbar()
        .children([...shown.map(item), button("tab-new", "+", () => openOverlay({ mod: "my-new-menu", kind: "popup", width: 250, height: 543 }))]))
      .when(w?.buttons, el => el.child(button("minimize", w.platform === "windows" ? svg("mods/my-tabs/win-min.svg").size(16) : "−", () => run("window.minimize")))
        .child(button("maximize", w.platform === "windows" ? svg(`mods/my-tabs/${w.maximized ? "win-restore" : "win-max"}.svg`).size(16) : "□", () => run("window.maximize")))
        .child(button("close-window", w.platform === "windows" ? svg("mods/my-tabs/win-close.svg").size(16) : svg("mods/pane/close.svg").size(13), () => run("window.close"))));
  }
}
