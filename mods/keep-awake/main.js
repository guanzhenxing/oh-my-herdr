// Keep Awake: 防止电脑休眠 (macOS). Three modes in shared("keep-awake"):
// "always" — claim sleep prevention non-stop; "agents" (default) — only while
// an agent reports working; "off". Claims are `caffeinate -t <seconds>`: each
// one exits by itself, a renewal loop in the bar copy re-arms while the mode
// asks for it, so there is no long-lived process to track or kill (Herdr's
// exec caps at 10 minutes, which a -t claim never reaches).
// Two views: the status-bar block (default) and a popup menu
// (props { view: "menu" }) that switches the mode.
// macOS only: caffeinate ships with it, nothing to install. window() is null until
// Herdr's first frame and a copy's init runs before that, so the platform is read
// where it is used, never once in init.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { checking, props, shared, setShared, agents, exec as runProg, openOverlay, closeOverlay, theme, window } from "herdr";

const KEY = "keep-awake";
const MODES = [
  { id: "always", name: "开启", hint: "始终防止此电脑进入睡眠状态", claim: 120 },
  { id: "agents", name: "代理", hint: "代理工作时防止电脑进入睡眠状态", claim: 45 },
  { id: "off", name: "关闭", hint: "允许系统正常进入睡眠状态", claim: 0 },
];
const modeOf = (st) => MODES.find((m) => m.id === (st?.mode ?? "agents")) ?? MODES[1];

// "macos" | "linux" | "windows" | undefined (no window yet: startup, herdr-app check).
const platform = () => window()?.platform;

export default class KeepAwake extends View {
  init(_props, cx) {
    this.dead = false;
    this.active = false; // a caffeinate claim is held right now
    if (checking()) return;
    if (props()?.view !== "menu") cx.spawn(async (cx) => { await this.loop(cx); }); // a task of its own: init's cx is not kept
  }

  async close(cx) {
    this.dead = true;
  }

  working() {
    return agents().some((a) => a.status === "working");
  }

  sleep(ms, cx) {
    return new Promise((r) => cx.timer.after(ms, r));
  }

  // Renewal loop: hold a claim while the mode asks for one, else poll.
  // Mode changes are read off shared every iteration; switching away from a
  // claim lets it lapse naturally (at most one claim length of linger).
  async loop(cx) {
    let lastActive = null;
    for (;;) {
      if (this.dead) return;
      const st = shared(KEY) ?? {};
      const mode = modeOf(st).id;
      const os = platform();
      if (os && os !== "macos") return; // settled on another system: nothing to claim, ever
      let claim = modeOf(st).claim;
      if (os !== "macos" || (mode === "agents" && !this.working())) claim = 0;
      this.active = claim > 0;
      if (this.active !== lastActive) {
        lastActive = this.active;
        setShared(KEY, { ...st, mode, active: this.active }); // re-renders the menu copy too
      }
      cx.notify();
      if (claim > 0) {
        const r = await runProg("caffeinate", ["-t", String(claim)], { timeout: (claim + 10) * 1000 }).catch(() => null);
        if (r === null || (r.code !== 0 && r.code !== undefined)) {
          // No caffeinate (or it refuses): stop claiming, say so, stop looping.
          this.active = false;
          this.broken = true;
          setShared(KEY, { ...st, mode, active: false });
          cx.notify();
          return;
        }
      } else {
        await this.sleep(3000, cx);
      }
    }
  }

  render(cx) {
    const t = theme();
    if (props()?.view === "menu") return this.menu(t, cx);
    return this.bar(t, cx);
  }

  // ---- status-bar block ----
  bar(t, cx) {
    if (platform() !== "macos") return div().size(0);
    const st = shared(KEY) ?? {};
    const mode = modeOf(st);
    const active = st.active === true || (this.active && st.active !== false);
    return h_flex().id("keep-awake-bar").size_full().px(10).gap(6).items_center().cursor_pointer()
      .bg(t.chrome).border_t(1).border_color(t.border)
      .hover((h) => h.bg(t.hover))
      .on_click((_e, c) => openOverlay({ mod: "keep-awake", kind: "popup", width: 300, height: 330, props: { view: "menu" } }))
      .text_size(11.5).text_color(t.muted)
      .when(this.broken, (r) => r.child(div().text_color(t.blocked).child("☕×")))
      .when(!this.broken, (r) => r
        .child(div().child("☕"))
        .child(div().whitespace_nowrap().child(mode.name)))
      .when(this.broken, (r) => r.child(div().text_color(t.blocked).text_size(10.5).child("不可用")));
  }

  // ---- the popup menu ----
  menu(t, cx) {
    const st = shared(KEY) ?? {};
    const mode = modeOf(st).id;
    const active = st.active === true;
    return v_flex().id("keep-awake-menu").w_full().h_full().text_size(12.5).text_color(t.foreground)
      .child(h_flex().px(14).py(10).gap(8).items_center().justify_between()
        .child(div().font_semibold().child("防止电脑休眠"))
        .child(h_flex().gap(6).items_center().text_size(11).text_color(t.dim)
          .child(div().child(`${modeOf(st).name} · ${active ? "生效中" : "未生效"}`))
          .child(div().id("ka-close").size(20).rounded(5).flex().items_center().justify_center().cursor_pointer()
            .hover((h) => h.bg(t.hover)).on_click((_e, c) => closeOverlay(props()?.overlay)).child("✕"))))
      .child(div().h(1).bg(t.border))
      .child(v_flex().p(8).gap(2).children(MODES.map((m) =>
        v_flex().id(`ka-${m.id}`).gap(1).px(10).py(7).rounded(7)
          .when(mode === m.id, (e) => e.bg(t.selected))
          .hover((h) => h.bg(t.hover))
          .cursor_pointer()
          .on_click((_e, c) => { setShared(KEY, { ...st, mode: m.id }); closeOverlay(props()?.overlay); })
          .child(h_flex().gap(8).items_center()
            .child(div().size(12).rounded(6).border(1).border_color(mode === m.id ? t.accent : t.input).flex().items_center().justify_center()
              .when(mode === m.id, (e) => e.child(div().size(6).rounded(3).bg(t.accent))))
            .child(div().font_semibold().child(m.name)))
          .child(div().text_size(11).text_color(t.dim).pl(20).child(m.hint)))));
  }
}
