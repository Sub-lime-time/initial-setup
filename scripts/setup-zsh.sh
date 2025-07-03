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
    INSTALL_CMD="sudo apt-get -y install"
    ZSH_PATH="/usr/bin/zsh"
    SUDO="sudo"
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
            exit 1
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

    # Fetch Homelab private key from 1Password if not present
    if [ ! -f "$HOME/.ssh/homelab" ]; then
        if command -v op &>/dev/null; then
            echo "[INFO] Fetching Homelab private key from 1Password..."
            op read "op://Private/id_ed25519_homelab/private key" > "$HOME/.ssh/homelab"
            chmod 600 "$HOME/.ssh/homelab"
        else
            echo "[ERROR] 1Password CLI (op) not found. Please install it or manually place your key at ~/.ssh/homelab."
            exit 1
        fi
    fi

    # Fetch Homelab public key from 1Password if not present
    if [ ! -f "$HOME/.ssh/homelab.pub" ]; then
        if command -v op &>/dev/null; then
            echo "[INFO] Fetching Homelab public key from 1Password..."
            op read "op://Private/id_ed25519_homelab/public key" > "$HOME/.ssh/homelab.pub"
            chmod 644 "$HOME/.ssh/homelab.pub"
        else
            echo "[ERROR] 1Password CLI (op) not found. Please install it or manually place your key at ~/.ssh/homelab.pub."
            exit 1
        fi
    fi

    # Add GitHub to known_hosts if not already present
    if ! grep -q github.com "$HOME/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan github.com >> "$HOME/.ssh/known_hosts"
    fi

    # Optionally add SSH config for GitHub
    if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
        cat <<EOF >> "$HOME/.ssh/config"
Host github.com
    User git
    IdentityFile ~/.ssh/homelab
    IdentitiesOnly yes
    ForwardAgent yes
EOF
        chmod 600 "$HOME/.ssh/config"
    fi
}

clone_dotfiles() {
    # Only clone if yadm is not already managing dotfiles
    if yadm list | grep -q ".zshrc"; then
        echo "[OK] Dotfiles already managed by yadm. Skipping clone."
        return
    fi

    if [ -f "$HOME/.ssh/homelab" ]; then
        echo "[INFO] Cloning dotfiles with yadm (SSH)..."
        if yadm clone "$DOTFILES_REPO_SSH"; then
            echo "[INFO] Forcing checkout of dotfiles to overwrite local files."
            yadm checkout --force
        else
            echo "[WARN] SSH clone failed, falling back to HTTPS..."
            if yadm clone "$DOTFILES_REPO"; then
                echo "[INFO] Forcing checkout of dotfiles to overwrite local files."
                yadm checkout --force
            else
                echo "[ERROR] Failed to clone dotfiles via both SSH and HTTPS."; exit 1;
            fi
        fi
    else
        echo "[INFO] Homelab SSH key not found, cloning dotfiles with HTTPS..."
        if yadm clone "$DOTFILES_REPO"; then
            echo "[INFO] Forcing checkout of dotfiles to overwrite local files."
            yadm checkout --force
        else
            echo "[ERROR] Failed to clone dotfiles via HTTPS."; exit 1;
        fi
    fi
}

main() {
    setup_ssh_key
    eval "$(ssh-agent -s)"
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        ssh-add ~/.ssh/homelab
    else
        echo "[ERROR] ssh-agent did not start or SSH_AUTH_SOCK is not set."
        exit 1
    fi
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