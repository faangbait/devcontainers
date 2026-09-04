# Project TODOs

## Deferred and intentionally skipped

These were considered and deliberately not done. They are recorded so the
reasoning survives and the next pass does not re-litigate them.

- **Missing launch configs.** Awaiting a good method for "inject this file into userland". Might move outside the container space entirely, so deferred. `.vscode/launch.json` 
```
vscode_launch_configurations:
    - name: "Python Debugger: Current File"
    type: debugpy
    request: launch
    program: "${file}"
    console: integratedTerminal
    - name: "Python Debugger: Attach"
    type: debugpy
    request: attach
    connect:
        host: localhost
        port: 5678  
  
  rust:
    vscode_launch_configurations:
      - name: "Attach"
        type: lldb
        request: attach
        pid: "${command:pickProcess}"
  ```

## opencode plugins (potential for inclusion)

- https://github.com/spoons-and-mirrors/subtask2
- https://github.com/vtemian/octto
- https://github.com/kdcokenny/opencode-background-agents
- https://github.com/kdcokenny/opencode-worktree
- https://www.opencode.cafe/plugin/opencode-obsidian
- https://github.com/danyuchn/asd-ste100-skill/tree/master
