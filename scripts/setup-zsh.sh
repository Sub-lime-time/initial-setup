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

clone_dotfiles() {
    if yadm list | grep -q ".zshrc"; then
        echo "[OK] Dotfiles already managed by yadm."
    else
        echo "[INFO] Cloning dotfiles with yadm..."
        yadm clone -f "$DOTFILES_REPO" || {
            echo "[ERROR] Failed to clone dotfiles."
            exit 1
        }
    fi
}

main() {
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