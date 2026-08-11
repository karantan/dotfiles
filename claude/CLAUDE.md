# Global instructions

- NEVER add "Co-Authored-By: Claude ..." (or any Claude/AI attribution trailer) to git commit messages.
- NEVER add "🤖 Generated with Claude Code" (or similar attribution) to PR descriptions.

## Be brief

Default to the shortest response that still fully answers. Cut length, not
information.

- **Reporting work done:** 2–4 sentences or a few bullets. What changed, where
  (`file:line`), and anything I must know. No replay of the process, no recap of
  a plan I already approved, no unrequested "next steps".
- **No preamble or postamble.** No "Great question", no "Let me…", no closing
  summary of what you just said. Answer, then stop.
- **Plans:** one line per step — what you'd do, not why each step is sensible.
- **Code comments:** match the surrounding file's density. Never narrate what
  the code plainly says.
- **Don't survey alternatives** I didn't ask about. Real trade-off → your
  recommendation in one sentence, the alternative in one clause.
- **Tables and headers** only for genuinely parallel structure. For two or three
  items, use a sentence.

Never buy brevity with omission: always keep failures, error output, caveats,
uncertainty, work you skipped, and anything hard to reverse. If something truly
needs 500 words it gets 500 words — just don't inflate 50 into 200. Go long when
I ask ("explain", "walk me through", "in detail").

## Browser

I use **Brave** as my browser. Chrome is installed but I don't use it — never
drive Chrome, and don't bother with the "Claude in Chrome" extension (it isn't
connected). Whenever I ask you to open, visit, or look at a website, use my Brave
browser, since it already holds my logged-in sessions (EBN app, GitHub, Grafana,
provider control panels). The in-app preview browser is a separate, logged-out
profile — only use it for anonymous fetches where a session doesn't matter.

Brave is Chromium-based and speaks the same AppleScript dictionary as Chrome, so
drive it with `osascript` via Bash. The `Control_Chrome` MCP tools are hardcoded
to "Google Chrome" and will hit the wrong browser — don't use them for this.

### Don't interrupt me — use `brave-bg`

**Default to `brave-bg` for anything that loads a page.** It works in the
background: it does not bring Brave to the front, does not touch my open tabs,
and does not change which tab I'm looking at. It uses my real profile, so my
logged-in sessions work. It's on PATH, installed to `~/.local/bin/brave-bg` by
the nix-darwin flake (`bin/brave-bg` in `~/.dotfiles`).

```bash
brave-bg open github.com/teamniteo/ebn   # navigate, wait for load
brave-bg text                            # document.body.innerText
brave-bg url                             # {"url":…,"title":…}
brave-bg js 'document.title'             # arbitrary JS
brave-bg close                           # tidy up when done
```

It keeps one minimized scratch window and navigates it from *inside* the page.
Leave that window open between steps — reusing it is completely silent. Only the
first `open` after a `close` creates the window, which flashes Brave forward for
about a second before returning focus to whatever I was using.

### Why not plain AppleScript

Chromium raises itself whenever AppleScript **mutates** it. Measured, all of
these yank Brave to the front mid-task: `make new tab`, `make new window`,
`set URL of …`, and even `open -g -a "Brave Browser" <url>`. `make new tab` also
switches my active tab out from under me. So **don't use those to load a page.**

`execute … javascript` does *not* raise Brave. That's the whole trick, and it's
why read-only inspection of my real windows is safe:

```bash
# safe: read-only, never steals focus
osascript -e 'tell application "Brave Browser" to get URL of tabs of front window'
osascript -e 'tell application "Brave Browser" to get {URL, title} of active tab of front window'
osascript -e 'tell application "Brave Browser" to execute active tab of front window javascript "document.body.innerText"'
```

Use those when I ask about a tab **I already have open**. Use `brave-bg` when you
need to load something new. The minimized scratch window is never Brave's `front
window`, so these keep pointing at my real window.

**View → Developer → Allow JavaScript from Apple Events** must be enabled in
Brave. All of `brave-bg` depends on it, plus any page-content read. Only listing
tabs and reading URLs/titles work without it. If something fails with "Executing
JavaScript through AppleScript is turned off", ask me to flip that toggle rather
than silently falling back to something else — including falling back to the
focus-stealing mutations above. I may turn it back off after a task, so expect to
ask again.

`screencapture` is unavailable — this app lacks macOS Screen Recording
permission, so screenshots of Brave fail with "could not create image from
display". Read page text instead.
