# Shell scripts

Drop a shell script in this folder and it becomes a button.

Every executable script here is scanned on load and on every `help()` call, and each one gets its own method and `hammerspoon://` address:

```
deploy-staging.sh   ->  launchShellDeployStaging()
                        hammerspoon://launchshelldeploystaging
```

Nothing to configure: the file name is the button name, CamelCased with accents transliterated, exactly like the other integrations. Rename a script and its address follows; delete it and the button disappears.

## What a press does

All scripts share **one** Terminal window, on **Desktop 1**:

1. Switch to Desktop 1 and bring the shared window up (creating it there if it does not exist).
2. If the window is idle, run the script in it.
3. If it is **busy running something else**, say so and cancel — nothing is typed into a running program.

That last rule is why one window is enough: scripts queue behind you, not behind each other, and you always see what is running.

Add a description by making the first comment line of the script one:

```bash
#!/bin/zsh
# Sync the aliases across to the laptop
```

That line shows up in the generated catalog next to the button address.

## Privacy

**The scripts in this folder are not committed** — only this README is. They routinely contain hostnames, paths and account details, so `.gitignore` publishes the folder and hides its contents. Keep credentials out of them anyway: anything here is readable by any application that can read your files.
