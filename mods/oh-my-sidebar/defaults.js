// Preferences a person may change in the installed mod.json under `settings`, read by
// more than one view. `agent_name` is read by the agents view: "tab" names a row after
// its tab (with this layout's live-title behavior for automatic names), "title" after
// the terminal's live title, what the agent says it's doing.
export const DEFAULT_SETTINGS = {
  git: { retry_after: "15s" },
  pull_request_status: true,
  agent_name: "tab",
};
