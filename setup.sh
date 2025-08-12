You’re getting the error because `docker stack deploy` is being run on a node that is not a Swarm manager. Even though `docker swarm init` might have been run previously, the script is not detecting the manager status correctly or the node has lost that state.

Here’s how I’ll fix it in the script:
1. **Improve `ensure_swarm()`** to verify if the node is part of a Swarm **and** is a **manager**.
2. If not, it will either **init** (if standalone) or ask for a **join command** to rejoin as manager.

### Updated `ensure_swarm()`
```bash
ensure_swarm() {
  local state role
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  role=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo "false")

  if [[ "$state" == "active" && "$role" == "true" ]]; then
    log "Docker Swarm already initialized and this node is a manager."
  elif [[ "$state" == "active" && "$role" != "true" ]]; then
    warn "This node is part of a swarm but is not a manager. Please run the manager join command from an existing swarm manager node."
    read -rp "Enter manager join command (or leave blank to abort): " join_cmd
    if [[ -n "$join_cmd" ]]; then
      eval "$join_cmd"
    else
      err "Aborting. This node must be a Swarm manager to deploy the stack."
      exit 1
    fi
  else
    # Standalone node: init swarm
    local addr_guess
    addr_guess=$(hostname -I 2>/dev/null | awk '{print $1}')
    ip=$(prompt_default "Advertise IP for Swarm" "${addr_guess:-127.0.0.1}")
    log "Initializing Swarm..."
    docker swarm init --advertise-addr "$ip" || true
  fi
}
```

This way, if your node isn’t a manager, it will clearly tell you and allow you to paste the `docker swarm join --token ...` command from a manager node.

Do you want me to patch the script in the canvas with this updated `ensure_swarm()` so you can just re-run it without manual checks?
