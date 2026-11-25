// Context menus (Herdr's items). Opened as a popup with
// props { tab: "pane" | "tab" | "space" | "global", target }.
// ↑/↓ move, Enter runs, Esc closes. An item is [label, command, args];
// a command "worktree" opens the worktree dialog instead.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { home, focused as focusedNow, run, props, closeOverlay, openOverlay, theme, keys, terminals, spaces, panes, exec as runProg, shared, setShared } from "herdr";

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

// This Mac: its home; another machine: space.new starts in that machine's home by itself.
const newSpaceArgs = () => {
  const m = spaces().find((x) => x.id === focusedNow()?.space)?.machine ?? null;
  return m ? { machine: m } : { machine: "", folder: home() };
};

// A space's checkout: "main" (a repo's own), "linked" (a worktree), or null.
async function checkout(folder, on) {
  const top = await runProg("git", ["rev-parse", "--show-toplevel"], { cwd: folder, on });
  const common = await runProg("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: folder, on });
  if (top.code !== 0 || common.code !== 0) return null;
  return common.stdout.trim() === `${top.stdout.trim()}/.git` ? "main" : "linked";
}

// Items come back grouped: sections() yields { label?, items } — the renderer
// draws a divider between sections and a small header where a label is set.
// Sort order is by use: layout first, agent actions, then terminal behavior,
// destructive closes last.
function sections(p, git) {
  p = p ?? {};
  const tg = p.target ?? {};
  switch (p.tab) {
    case "pane": {
      // A kept sub-agent can go back under its parent, still running.
      const all = terminals();
      const term = all.find((t) => t.address === tg.terminal);
      const parent = term?.parent && all.find((t) => t.address === term.parent);
      // Once they go to the program, Shift+right-click still opens this menu.
      const toProgram = term?.labels?.["herdr.right-click"] === "program";
      return [
        { label: "布局", items: [
          ["Rename", "pane.rename", { pane: tg.pane }],
          ["Split right", "pane.split", { direction: "right", pane: tg.pane }],
          ["Split down", "pane.split", { direction: "down", pane: tg.pane }],
          ["Zoom", "pane.zoom", { pane: tg.pane }],
        ]},
        { label: "代理", items: [
          ...(term ? [["移交给另一个代理", "agent-handoff", { terminal: term.address }]] : []),
          ...(parent ? [[`Send back to ${parent.name || parent.address}`, "terminal.park", { terminal: term.address }]] : []),
        ]},
        { label: "终端", items: term ? [
          toProgram
            ? ["Use Herdr right-click menu", "terminal.right_click", { terminal: term.address, to: "menu" }]
            : ["Send right-clicks to pane", "terminal.right_click", { terminal: term.address, to: "program" }],
        ] : []},
        { items: [["Close pane", `my-tabs.close-pane:${tg.pane}`, {}]] },
      ];
    }
    case "tab":
      return [
        { items: [
          ["Rename", "tab.rename", { id: tg.id }],
          ["New tab", "tab.new", { space: tg.space }],
        ]},
        // my-tabs checks it: the last tab of a worktree space removes the worktree instead.
        { items: [["Close", `my-tabs.close-tab:${tg.id}`, {}]] },
      ];
    case "space":
      return [
        { items: [
          ["Rename", "space.rename", { id: tg.id }],
          ...(git ? [["Project settings…", "project-settings", { space: tg.id }]] : []),
          // oh-my-sidebar's folders: a repo files with its worktrees, any other space by itself.
          // oh-my-sidebar's worktree notes: one note per checkout, edited in its dialog.
          ["Note…", "note", { space: tg.id }],
          ["Move to folder…", "move-folder", { space: tg.id }],
        ]},
        { label: "工作树", items: git ? [
          ["New worktree", "worktree", { space: tg.id, action: "new" }],
          ["Open worktree", "worktree", { space: tg.id, action: "open" }],
        ] : []},
        // hibernate mod: stop a space's programs (on this computer or another machine), or start them again.
        { label: "电源", items: tg.id ? [shared("hibernate.sleeping")?.[tg.id] ? ["Wake space", "hibernate", { action: "wake", space: tg.id }] : ["Sleep space", "hibernate", { action: "sleep", space: tg.id }]] : [] },
        // A worktree space closes by removing its worktree (the dialog checks for unsaved work first).
        { items: [git === "linked" ? ["Close & remove worktree", "worktree", { space: tg.id, action: "remove" }] : ["Close", "space.close", { id: tg.id }]] },
      ];
    default:
      return [
        // At home, not in the focused (maybe worktree) folder: a second space there shares its removal.
        { items: [["New space", "space.new", newSpaceArgs()]] },
        { label: "主题", items: [
          ["Theme: graphite", "app.theme", { name: "graphite" }],
          ["Theme: ink", "app.theme", { name: "ink" }],
          ["Theme: moss", "app.theme", { name: "moss" }],
          ["Theme: atom one dark", "app.theme", { name: "atom-one-dark" }],
        ]},
        { items: [["Keybinds", "app.help", {}]] },
      ];
  }
}

// The menu's items, flattened in render order (headers are not selectable).
function flatItems(p, git) {
  return sections(p, git).flatMap((s) => s.items);
}

const closes = (it) => it[0].startsWith("Close");

function menuIcon(it) {
  const command = it[1];
  if (command === "hibernate") return `mods/hibernate/${it[2].action === "wake" ? "sun" : "moon"}.svg`;
  const name = closes(it) ? "x" : command === "agent-handoff" ? "terminal" : command.endsWith(".rename") ? "square-pen" : command.endsWith(".new") ? "plus" : command === "worktree" ? "git-branch" : command === "move-folder" ? "folder" : command === "note" ? "file-text" : command === "app.help" ? "terminal" : command === "app.theme" || command === "project-settings" ? "settings" : command === "pane.split" ? (it[2]?.direction === "down" ? "panel-bottom" : "panel-right") : command === "pane.zoom" ? "square" : "terminal";
  return `mods/workspace-chrome/${name}.svg`;
}

// The key bound to a command, for the hint on the right.
function shortcut(name, args) {
  // `pane.split:right` binds pane.split with { direction: "right" }.
  const value = args && Object.values(args)[0];
  const k = keys().find((b) => b.section === "global" && (b.action === name || b.action === `${name}:${value}`));
  return k ? k.keys : "";
}

export default class Menu extends View {
  init(_props, cx) {
    this.at = 0;
    this.git = null;
    this.handle = cx.focus_handle();
    this.handle.focus();
    const p = props();
    const space = p?.tab === "space" && spaces().find((s) => s.id === p.target?.id);
    const folder = space && place(space);
    if (folder)
      cx.spawn(async (cx) => {
        this.git = await checkout(folder, space.machine).catch(() => null);
        cx.notify();
      });
  }

  choose(i, cx) {
    const it = flatItems(props(), this.git)[i];
    if (!it) return;
    closeOverlay(props()?.overlay);
    // Remove uses my-worktree's restyled confirm.
    if (it[1] === "project-settings") openOverlay({ mod: "project-settings", kind: "dialog", width: 660, height: 700, props: it[2] });
    // Hand the running session to another agent: the handoff dialog takes the terminal.
    else if (it[1] === "agent-handoff") openOverlay({ mod: "agent-handoff", kind: "dialog", width: 560, height: 660, props: it[2] });
    else if (it[1] === "worktree" && it[2].action === "remove") openOverlay({ mod: "my-worktree", kind: "dialog", width: 460, height: 350, props: it[2] });
    // New and open use the Create worktree dialog (new-worktree); open starts on its Branch tab.
    else if (it[1] === "worktree") openOverlay({ mod: "new-worktree", kind: "dialog", width: 560, height: 780, props: { space: it[2].space, ...(it[2].action === "open" ? { mode: "branch" } : {}) } });
    else if (it[1] === "move-folder") {
      const s = spaces().find((x) => x.id === it[2].space);
      const key = shared("oh-my-sidebar.space-parents")?.[it[2].space]?.key ?? `space:${it[2].space}`;
      const count = (shared("oh-my-sidebar.groups")?.groups ?? []).length;
      openOverlay({ mod: "oh-my-sidebar", kind: "popup", width: 260, height: Math.min(460, 112 + (count + 1) * 31),
        props: { view: "groups", mode: "move", key, name: s?.name, machine: s?.machine ?? null } });
    }
    else if (it[1] === "note") openOverlay({ mod: "oh-my-sidebar", kind: "dialog", width: 460, height: 290, props: { view: "note", space: it[2].space } });
    else if (it[1] === "hibernate") setShared("hibernate.request", { nonce: Date.now(), ...it[2] });
    else run(it[1], it[2]);
  }

  render(cx) {
    const t = theme();
    const flat = flatItems(props(), this.git);
    const secs = sections(props(), this.git).filter((s) => s.items.length);
    let row = -1; // flat item index, for the keyboard and choose()
    return v_flex()
      .id("menu")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % flat.length;
        else if (e.key === "up") this.at = (this.at + flat.length - 1) % flat.length;
        else if (e.key === "enter") this.choose(this.at, cx);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(secs.flatMap((s, si) => [
        ...(si > 0 ? [div().mx(7).mt(4).mb(3).h(1).bg(t.border)] : []),
        ...(s.label ? [div().px(8).pt(si > 0 ? 1 : 4).pb(2).text_size(10.5).text_color(t.dim).child(s.label)] : []),
        ...s.items.map((it) => {
          row += 1;
          const i = row;
          return h_flex()
            .id(`mi-${i}`)
            .h(31)
            .px(8)
            .gap(9)
            .rounded(7)
            .items_center()
            .justify_between()
            .text_color(t.foreground)
            .when(i === this.at, (el) => el.bg(t.selected))
            .hover((s2) => s2.bg(t.hover))
            .on_click((_e, cx2) => this.choose(i, cx2))
            .child(svg(menuIcon(it)).size(14).flex_none().text_color(t.muted))
            .child(div().flex_1().child(it[0]))
            .child(div().text_size(11).text_color(t.dim).child(shortcut(it[1], it[2])));
        }),
      ]));
  }
}
