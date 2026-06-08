# Multi-user access

The DGX Spark runs **one shared** AI stack — a single ComfyUI, a single NemoClaw
assistant, and the system Ollama service. Several people can use it at once, each
from their own laptop over their **own SSH account** on the Spark. The big models
(20–65 GB) load once into the shared 119 GiB memory, so sharing one instance is
the only thing that fits — there are no per-user copies.

```
  Alice's Mac ─ ssh -L 8188 alice@dgx ─┐
  Bob's Mac   ─ ssh -L 8188 bob@dgx   ─┼─►  ONE ComfyUI   127.0.0.1:8188   (runs as arts)
  Carol's Mac ─ ssh -L 18789 carol@dgx ┼─►  ONE NemoClaw  127.0.0.1:18789  (runs as arts)
                                       └─►  Ollama        127.0.0.1:11434  (systemd, shared)
```

> **Shared, not private.** Because it's a single instance, everyone tunnelling to
> ComfyUI sees the same queue and can browse the same gallery. Outputs are at
> least **namespaced per user** (see below), but this is organization, not access
> control — don't generate anything you wouldn't want the other Spark users to see.
> (True isolation would need per-user ComfyUI instances; not set up here.)

### Per-user output folders (ComfyUI)

Each user gets their own workflow whose images save to `~/ComfyUI/output/<user>/`
instead of one shared pile. The owner creates them once on the Spark:

```bash
bash server/comfyui-add-user-workflow.sh lzr yue yuki    # add names as needed
```

Then in ComfyUI each user opens **`Qwen2512-<their-name>`** from the Workflows
menu (refresh the page if it's not listed yet — no restart needed). Everything
else about the workflow is identical to the shared default.

---

## For the admin (the owner account, `arts`) — one time

1. Make sure each person has their **own Linux account** on the Spark and can SSH
   in with their key (`ssh alice@dgx.zrh.arts.moe` works for them).
2. Run the enabler once, listing those users:
   ```bash
   sudo bash setup/enable-multiuser.sh alice bob carol
   ```
   It creates the `dgx-ai` group, adds those users, installs two small wrappers
   (`/usr/local/bin/nemoclaw-dashboard-url`, `/usr/local/bin/comfyui-ensure`), and
   a **scoped** `NOPASSWD` sudo rule so group members can fetch a NemoClaw token
   and restart the shared ComfyUI **as `arts`** — and nothing else.
3. Add more people later:
   ```bash
   sudo bash setup/enable-multiuser.sh --add dave
   ```
   (New group membership takes effect after they log out and back in.)

Nothing about the single-user setup changes; this is purely additive. To revoke
someone: `sudo gpasswd -d alice dgx-ai`. To turn the whole thing off: delete
`/etc/sudoers.d/dgx-ai` and the two wrappers.

---

## For each user — one time, on your own Mac

1. Get this repo (clone it, or copy the `client/` folder), or just the two
   `*-connect.sh` scripts.
2. Confirm you can reach the box as yourself:
   ```bash
   ssh YOUR_SPARK_USER@dgx.zrh.arts.moe 'echo ok'
   ```

That's it — no config file required. The first time you run a script it asks
which Spark account is yours:

```
Which DGX Spark account is yours?
   1) arts
   2) lzr
   3) yue
   4) yuki
   5) other (type a username)
Choice [1]:
```

If you'd rather not be asked every time, set your name once (then it never
prompts):
```bash
cp client/dgx.conf.example client/dgx.conf   # or → ~/.config/dgx-spark.conf
# edit it: set  DGX_USER=lzr
```
…or just answer the menu each run.

## For each user — every time

Same commands as the single-user [USERGUIDE](USERGUIDE.md):

| Action | Command (on your Mac) |
|---|---|
| Open ComfyUI | `bash client/comfyui-connect.sh` (or double-click `client/ComfyUI.command`) |
| Open NemoClaw chat | `bash client/nemoclaw-connect.sh` |
| Health-check image gen | `bash client/comfyui-connect.sh --check` |

> The menu (and `client/dgx.conf`) also apply when you double-click
> `ComfyUI.command`. One-off override without touching config:
> `DGX_USER=lzr bash client/comfyui-connect.sh`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `nemoclaw-connect.sh` says "must be in the dgx-ai group" | Ask `arts` to run `enable-multiuser.sh --add <you>`; then **log out and back in** on the Spark so the group applies |
| `sudo: a password is required` in the fetch | The sudoers rule isn't installed or your group membership hasn't taken effect yet — see above |
| ComfyUI "did not respond" | The shared instance is down. If you're in `dgx-ai`: `ssh <you>@dgx.zrh.arts.moe 'sudo -u arts /usr/local/bin/comfyui-ensure'`; otherwise ask `arts` |
| Connects as the wrong user | You didn't set `CU_HOST`/`NC_HOST` — check `client/dgx.conf`, or pass `CU_HOST=you@host` inline |
| `ssh` asks for a password | Your SSH key isn't set up on the Spark for your account — sort that first (`ssh-copy-id you@dgx.zrh.arts.moe`) |
