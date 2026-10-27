# Approval board

One page that asks the user for every decision waiting on them, with the evidence beside each ask. The user reads it,
replies with the words it names, and the loop moves on. The page is a lavish review page, run by the `lavish-axi` CLI: a
required dependency that this skill's `scripts/install.sh` installs, pinned, into `~/.local/bin`. Use it on two branches:

- **Asking**: a gate or decision you are about to put to the user carries evidence (screenshots, a prototype,
  before/after, options to compare) or more than one ask.
- **Polling**: the user asks what in their tickets is waiting on them ("what's left for me to approve", "what do I
  need to unblock").

## The waiting record

`tk` notes are the record of who owes a reply; the page and the chat are not. Whenever you put an ask to anyone, add a
note on the ticket it blocks. An ask with no ticket (a plan gate, a question in chat) gets its own small ticket,
`tk create 'Waiting: <ask>'`, closed when the reply arrives:

```bash
tk add-note <id> 'waiting-on: <who> · from: <source> · ask: <ask> · reply: <reply words>'
tk add-note <id> 'answered: <ask> · <reply>'    # when the reply arrives
```

- `<who>` is the person whose reply unblocks it: the user running the session (`git config user.name`) or a named
  other (a PR reviewer, a teammate, ops). Never "the user" when someone else owns the answer.
- `<source>` is where the ask lives and where the reply will come from: `chat <date>` (asked in a chat
  session; never "this session", which means nothing to the next one), a PR (`<repo>#<n>`), a Jira key, a Slack
  thread link, a lanes file. A reply counts only from that source or from the user in this chat.

## Steps

1. **Collect the asks.** On the asking branch: every item waiting on the user (plan and ticket-tree gates, prototypes
   to approve, options to pick, fixes held for an OK before merge, tests only the user can run, open questions).
   On the polling branch: the `waiting-on:` notes with no later `answered:` for that ask, from
   `grep -rn 'waiting-on:' "${TICKETS_DIR:-.tickets}"` in this repo (`docs/backlog/tickets/` in a backlog repository);
   across projects when the user asks for everything, from every `.tickets/` and `docs/backlog/tickets/` under the
   working root. Split them by `<who>`: the user's own are the asks, the rest go in a short
   **Waiting on others** section with their source and no reply asked. When the tickets carry `lane-*` tags, group
   the asks by lane. Done when each ask names **the reply that unblocks it**: the gate word with the item
   (`approved markers`), a choice (`A`, `B`, `C` or a mix), or the result to report back.
2. **Gather the evidence.** For each ask: what changed and why in two or three sentences, your recommendation with
   its reason, and the proof. A UI ask shows screenshots at the sizes that matter, before and after side by side, and
   the approved spec beside the build when one exists. Copy the images into the page's folder (one scratchpad folder
   per session) and reference them by relative path, never a leading `/`. Name what you saw wrong and did not fix,
   and what you could not check.
3. **Write the page.** Run the `input` playbook (`lavish-axi playbook input`) plus
   any other that fits (`comparison`, `code`); design from the project's design system (its tokens, or a
   design skill the project names). Order:
   1. a header naming the project, the date and what the page is for;
   2. **What I need from you**: the numbered asks, each ending on its reply words, then your recommendation;
   3. one section per ask with its evidence (click-to-enlarge images) and its source;
   4. seen but not fixed, and waiting on others.
4. **Open it with lavish** (`lavish-axi <file>`), one HTML file per session in the scratchpad (never in the
   repo: lavish defaults to `.lavish/` in the cwd), rewritten in place as asks are answered and new ones arrive. If
   the user ended the session from the browser, reopen (`--reopen`) only for a new ask. Hand over the
   `http://127.0.0.1:<port>/session/<id>` link it prints (the `install.sh` wrapper keeps lavish on loopback; a
   Tailscale or LAN host name in it means the wrapper was bypassed: run `scripts/install.sh`), and only after the page loaded for you: `curl` returns 200, and a browser tool (when the session has one)
   shows the page with no console errors. If you could not check it in a browser, say so. If `lavish-axi` is not on PATH,
   run `scripts/install.sh`; if it still cannot run, give the file's full path and say why.
5. **Hand over in the chat**: the asks in three to six lines with their reply words, so the user can answer without
   opening the page. Then wait for page feedback with `lavish-axi poll <file>` as a tracked background job
   (Bash `run_in_background`, never `&` or `nohup`); a reply in the chat wins. Answer on the board with
   `lavish-axi reply <file> --agent-reply "<message>"`.

## Rules

- Gates follow PROTOCOL "Core rules": the exact word `approved` / `approve`, naming the item when more than one gate
  is open. The user's words count from the chat or from their lavish feedback; a choice or result needs no gate word.
- The page holds no secrets, tokens or personal data; customer data only as the repo's aggregate rules allow.
- The page stays on this machine: never `lavish-axi share` (it publishes to a third-party host, public by default).
- An item drops off the board once its `answered:` note is written; rewrite the page when the remaining asks change.
