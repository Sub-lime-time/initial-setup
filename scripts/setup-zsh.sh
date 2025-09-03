#! /bin/bash
set -e

# Cross-platform zsh/yadm/oh-my-zsh setup script
# - Installs zsh, yadm, Oh My Zsh, and zsh-autosuggestions if missing
# - Works on macOS (brew) and Ubuntu/Debian (apt)
# - Never deletes or overwrites .zshrc/.zprofile (let yadm manage them)
# - Safe to run multiple times

# Detect OS and set package manager/paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    PM="brew"
    INSTALL_CMD="brew install"
    ZSH_PATH="$(which zsh)"
    SUDO=""
else
    PM="apt-get"
    INSTALL_CMD="apt_retry sudo apt-get install -y"
    ZSH_PATH="/usr/bin/zsh"
    SUDO="sudo"
fi

# Source shared helpers (apt_retry) if present when running this script directly
if [ -f "$(dirname "$0")/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$(dirname "$0")/common.sh"
fi

OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
OH_MY_ZSH_SH="$OH_MY_ZSH_DIR/oh-my-zsh.sh"
ZSH_CUSTOM="${ZSH_CUSTOM:-$OH_MY_ZSH_DIR/custom}"
AUTO_SUGGESTIONS="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
DOTFILES_REPO="https://github.com/Sub-Lime-Time/dotfiles.git"
DOTFILES_REPO_SSH="git@github.com:Sub-lime-time/dotfiles.git"

install_zsh() {
    if ! command -v zsh &>/dev/null; then
        echo "[INFO] Installing zsh..."
        $INSTALL_CMD zsh
    else
        echo "[OK] zsh is already installed."
    fi
}

check_debug_log() {
    local dbg="$HOME/initial-setup-debug.log"
    if [ -f "$dbg" ]; then
        echo "[INFO] Found debug log: $dbg — showing last 200 lines for quick inspection"
        echo "--- BEGIN initial-setup-debug.log (last 200 lines) ---"
        tail -n 200 "$dbg" || echo "[WARN] Unable to read $dbg"
        echo "--- END initial-setup-debug.log ---"
    else
        :
    fi
}

install_yadm() {
    if ! command -v yadm &>/dev/null; then
        echo "[INFO] Installing yadm..."
        $INSTALL_CMD yadm
    else
        echo "[OK] yadm is already installed."
    fi
}

install_oh_my_zsh() {
    if [ -e "$OH_MY_ZSH_SH" ]; then
        echo "[OK] Oh My Zsh is already installed at $OH_MY_ZSH_SH"
    else
        echo "[INFO] Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
}

install_autosuggestions() {
    if [ -d "$AUTO_SUGGESTIONS" ]; then
        echo "[OK] Zsh Autosuggestions plugin already exists at $AUTO_SUGGESTIONS"
    else
        echo "[INFO] Installing Zsh Autosuggestions plugin..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTO_SUGGESTIONS" || {
            echo "[ERROR] Failed to clone Zsh Autosuggestions plugin."
            return 1
        }
    fi
}

setup_ssh_key() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Check if 1Password CLI is signed in before fetching keys
    if command -v op &>/dev/null; then
        if ! op account get &>/dev/null; then
            echo "[INFO] 1Password CLI not signed in. Running 'op signin'..."
            eval "$(op signin)"
        fi
    fi

    # Fetch GitHub private key from 1Password if not present. Some vaults
    # may store the key under id_ed25519_github; fall back to a homelab key
    # only if the github key isn't available.
    # Ensure we have both private and public GitHub keys in ~/.ssh/github and
    # ~/.ssh/github.pub. These are required for authenticating to GitHub; fail
    # hard if we can't fetch both fields from 1Password.
    if [ ! -f "$HOME/.ssh/github" ] || [ ! -f "$HOME/.ssh/github.pub" ]; then
        if ! command -v op &>/dev/null; then
            echo "[ERROR] 1Password CLI (op) not found. Please install it or place your GitHub keys at ~/.ssh/github and ~/.ssh/github.pub." >&2
            exit 1
        fi

        echo "[INFO] Fetching GitHub private+public keys from 1Password (id_ed25519_github)..."

        # Read each field once into temp files, then move them into place
        priv_tmp=$(mktemp "$HOME/.ssh/github.XXXX") || { echo "[ERROR] mktemp failed" >&2; exit 1; }
        pub_tmp=$(mktemp "$HOME/.ssh/github.pub.XXXX") || { rm -f "$priv_tmp"; echo "[ERROR] mktemp failed" >&2; exit 1; }

        if op read "op://Private/id_ed25519_github/private key" > "$priv_tmp" 2>/dev/null; then
            if op read "op://Private/id_ed25519_github/public key" > "$pub_tmp" 2>/dev/null; then
                mv "$priv_tmp" "$HOME/.ssh/github"
                mv "$pub_tmp" "$HOME/.ssh/github.pub"
                chmod 600 "$HOME/.ssh/github"
                chmod 644 "$HOME/.ssh/github.pub"
                echo "[INFO] Installed GitHub private and public keys to ~/.ssh/github{,.pub}."
            else
                rm -f "$priv_tmp" "$pub_tmp"
                echo "[ERROR] Could not read public key field 'public key' for id_ed25519_github from 1Password." >&2
                exit 1
            fi
        else
            rm -f "$priv_tmp" "$pub_tmp"
            echo "[ERROR] Could not read private key field 'private key' for id_ed25519_github from 1Password." >&2
            exit 1
        fi
    fi

    # Add GitHub to known_hosts if not already present.
    # Use ssh-keygen -F which correctly recognizes hashed hostnames.
    if ! ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
        echo "[INFO] github.com not found in known_hosts; fetching host key(s)"
        # Collect common key types explicitly to be thorough
        ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || {
            echo "[WARN] ssh-keyscan failed to fetch github.com host key; known_hosts may be incomplete" >&2
        }
    else
        echo "[INFO] github.com already present in known_hosts"
    fi

    # Optionally add SSH config for GitHub (use the github identity)
    if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
        cat <<'EOF' >> "$HOME/.ssh/config"
Host github.com
    User git
    IdentityFile ~/.ssh/github
    IdentitiesOnly yes
    ForwardAgent yes
EOF
        chmod 600 "$HOME/.ssh/config"
    fi

    # Try to add the key to the ssh-agent if available
    if [ -S "${SSH_AUTH_SOCK:-}" ]; then
        # If agent already has identities, skip adding unless none are present
        if ssh-add -l &>/dev/null; then
            # agent has identities; ensure our key is present (best-effort)
            if ! ssh-add -l | grep -q "github"; then
                echo "[INFO] Adding github key to ssh-agent (agent already running)."
                if grep -q "ENCRYPTED" "$HOME/.ssh/github" 2>/dev/null; then
                    echo "[INFO] github key is encrypted; you may be prompted for a passphrase."
                    ssh-add "$HOME/.ssh/github" || echo "[WARN] ssh-add failed or was cancelled."
                else
                    ssh-add "$HOME/.ssh/github" &>/dev/null || echo "[WARN] ssh-add failed to add github key."
                fi
            fi
        else
            # No identities in agent; try to add the key
            echo "[INFO] ssh-agent is running but has no identities. Adding github key..."
            if grep -q "ENCRYPTED" "$HOME/.ssh/github" 2>/dev/null; then
                echo "[INFO] github key is encrypted; you may be prompted for a passphrase."
                ssh-add "$HOME/.ssh/github" || echo "[WARN] ssh-add failed or was cancelled."
            else
                ssh-add "$HOME/.ssh/github" &>/dev/null || echo "[WARN] ssh-add failed to add github key."
            fi
        fi
    else
        echo "[INFO] No ssh-agent socket found; key installed but not added to agent." >&2
    fi
}

clone_dotfiles() {
    # If yadm already manages dotfiles, skip cloning
    if yadm list 2>/dev/null | grep -q ".zshrc"; then
        echo "[OK] Dotfiles already managed by yadm. Skipping clone."
        return 0
    fi

    echo "[INFO] Cloning dotfiles (SSH-only policy)..."

    # Quick TCP reachability check for GitHub SSH (port 22). This helps
    # fail fast with a clear message when outbound SSH is blocked by the
    # network/firewall. If nc isn't available we skip this check.
    if command -v nc >/dev/null 2>&1; then
        if ! nc -vz github.com 22 >/dev/null 2>&1; then
            echo "[WARN] TCP connection to github.com:22 failed. Port 22 may be blocked by a firewall or network policy." >&2
            echo "[WARN] If port 22 is blocked you can either enable outbound SSH or use an SSH-over-443 fallback (not enabled by this script)." >&2
        else
            echo "[INFO] TCP connection to github.com:22 looks reachable."
        fi
    else
        echo "[INFO] 'nc' (netcat) not found; skipping quick TCP reachability test for github.com:22"
    fi

    # Require the GitHub identity to be present
    if [ ! -f "$HOME/.ssh/github" ]; then
        echo "[ERROR] Required SSH identity ~/.ssh/github not found. Run setup_ssh_key or place your GitHub key at ~/.ssh/github." >&2
        return 1
    fi

    # Ensure ssh-agent has the key. Try non-interactive add; fail if it can't be added.
    if [ -S "${SSH_AUTH_SOCK:-}" ] && ssh-add -l &>/dev/null; then
        echo "[INFO] ssh-agent available and has identities.";
        # If agent doesn't list our key, attempt to add it non-interactively
        if ! ssh-add -l | grep -q "$(ssh-keygen -lf "$HOME/.ssh/github.pub" 2>/dev/null | awk '{print $2}')"; then
            ssh-add "$HOME/.ssh/github" >/dev/null 2>&1 || {
                echo "[ERROR] Failed to add ~/.ssh/github to the ssh-agent non-interactively. Please add it manually with 'ssh-add ~/.ssh/github' or unlock the key." >&2
                return 1
            }
        fi
    else
        # Try to add the key (this will start failing if agent isn't running or if key is encrypted)
        ssh-add "$HOME/.ssh/github" >/dev/null 2>&1 || {
            echo "[ERROR] No usable ssh-agent or failed to add ~/.ssh/github. Start an agent and add the key (ssh-add ~/.ssh/github)." >&2
            return 1
        }
    fi

    # Test SSH auth to GitHub using agent (BatchMode to avoid prompts)
    SSH_TEST_OUTPUT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true)
    if echo "$SSH_TEST_OUTPUT" | grep -qi "successfully authenticated\|You've successfully authenticated"; then
        echo "[INFO] SSH authentication to GitHub succeeded. Cloning via yadm (SSH)..."
        if yadm clone "$DOTFILES_REPO_SSH"; then
            echo "[INFO] Forcing checkout of dotfiles to overwrite local files.";
            yadm checkout --force || true
            return 0
        else
            echo "[ERROR] yadm SSH clone failed despite successful SSH auth. Output:" >&2
            echo "$SSH_TEST_OUTPUT" >&2
            return 1
        fi
    else
        echo "[ERROR] SSH authentication to GitHub failed. ssh output:" >&2
        echo "$SSH_TEST_OUTPUT" >&2
        echo "Ensure ~/.ssh/github is authorized in your GitHub account and the key is loaded into your ssh-agent." >&2
        return 1
    fi
}

main() {
    # Ensure we append all output from this run to a persistent debug log in the user's home
    LOG="$HOME/initial-setup-debug.log"
    # Show that we'll append to this log and keep a small header per run
    echo "[INFO] Appending run output to $LOG"
    echo "--- initial-setup run: $(date -u) ---" >> "$LOG" 2>/dev/null || true
    # Redirect remaining stdout/stderr to both the console and the debug log
    exec > >(tee -a "$LOG") 2>&1 || true

    # Robust ssh-agent logic: tie to existing agent or start a new one
    if [ -z "${SSH_AUTH_SOCK:-}" ] || ! [ -S "${SSH_AUTH_SOCK:-}" ]; then
        AGENT_SOCK=$(find /tmp/ssh-* -type s 2>/dev/null | head -n 1)
        if [ -n "$AGENT_SOCK" ]; then
            export SSH_AUTH_SOCK="$AGENT_SOCK"
            echo "[INFO] Found existing ssh-agent at ${SSH_AUTH_SOCK:-}"
        else
            eval "$(ssh-agent -s)"
            echo "[INFO] Started new ssh-agent"
        fi
    else
        echo "[INFO] SSH agent already available at ${SSH_AUTH_SOCK:-}"
    fi
    # Now that the ssh-agent is available, ensure the private key is present
    setup_ssh_key || echo "[WARN] setup_ssh_key reported issues; continuing"
    # Attempt to add key but do not let a failing ssh-add terminate the whole script
    ssh-add ~/.ssh/github || echo "[WARN] ssh-add failed or was cancelled; continuing without agent identity"
    install_zsh
    install_yadm
    install_oh_my_zsh
    install_autosuggestions
    clone_dotfiles

    # Change default shell to zsh if not already
    if [ "$SHELL" != "$ZSH_PATH" ]; then
        echo "[INFO] Changing default shell to $ZSH_PATH"
        $SUDO chsh -s "$ZSH_PATH" "$USER"
    else
        echo "[OK] Default shell is already zsh."
    fi

    echo "[SUCCESS] Zsh environment setup complete!"
}

main