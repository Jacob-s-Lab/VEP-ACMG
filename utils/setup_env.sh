#!/bin/bash

set -euo pipefail

# 1. Check if the environment.yml file exists in the current directory
YML_FILE="environment.yml"
if [ ! -f "$YML_FILE" ]; then
    echo "[Error] $YML_FILE not found! Please run this script in the directory containing $YML_FILE."
    exit 1
fi

# 2. Load Conda environment
echo "Loading Conda environment via Module..."
if command -v ml &>/dev/null; then
    ml biology Anaconda/Anaconda3
elif command -v module &>/dev/null; then
    module load biology Anaconda/Anaconda3
else
    echo "[Error] Module system (ml/module) not found."
    exit 1
fi

# 3. Ask the user where they want to install the environment
echo -e "\n=============================================="
echo "       Conda Environment Auto-Installer       "
echo "=============================================="
echo "請選擇您的 Conda 環境安裝路徑："
echo "1) /home/user/.conda/envs/ (預設路徑)"
echo "2) /work/user/.conda/envs/"
echo "3) 自訂路徑（手動指定環境與快取路徑）"
echo "=============================================="
read -p "請輸入選項 (1/2/3): " CHOICE

case "$CHOICE" in
    1)
        # Mode 1: Default path, read environment name from yml
        INSTALL_CMD="conda env create -f $YML_FILE"
        echo "將環境建立於預設路徑下 (/home/user/.conda)..."
        ;;

    2)
        # Mode 2: Project path, create .venv in the current directory
        ENV_PATH="$(realpath ./.venv)"
        INSTALL_CMD="conda env create -p $ENV_PATH -f $YML_FILE"
        echo "將環境建立於 /work 下: $ENV_PATH ..."
        
        PKG_PATH="/work/$USER/.conda/pkgs"
        mkdir -p "$PKG_PATH"
        export CONDA_PKGS_DIRS="$PKG_PATH"
        ;;

    3)
        # Mode 3: Custom path, ask user for the full absolute path
        read -p "請輸入您想安裝的完整絕對路徑 (e.g., /path/to/your/.venv/envs): " CUSTOM_PATH
        if [ -z "$CUSTOM_PATH" ]; then
            echo "錯誤：路徑不能為空！"
            exit 1
        fi
        INSTALL_CMD="conda env create -p $CUSTOM_PATH -f $YML_FILE"
        echo "將環境建立於自訂路徑：$CUSTOM_PATH ..."

        read -p "請輸入 Conda 下載快取 (pkgs_dirs) 儲存路徑（建議與環境在同一個磁碟區）：" PKG_PATH
        if [ -z "$PKG_PATH" ]; then
            echo "錯誤：pkgs_dirs 路徑不能為空！"
            exit 1
        fi
        mkdir -p "$PKG_PATH"
        export CONDA_PKGS_DIRS="$PKG_PATH"
        ;;

    *)
        echo "錯誤：無效的選項！"
        exit 1
        ;;
esac

# 4. Start the installation process
echo -e "\n=============================================="
echo "開始建立 Conda 環境..."
echo "執行指令: $INSTALL_CMD"
echo -e "==============================================\n"

# Execute the installation command
$INSTALL_CMD

# Unload the Anaconda module after installation
ml unload Anaconda/Anaconda3

# =======================================
# 5. Record the environment path and mode to a config file for future reference
# =======================================
CONFIG_RECORD="./.env_path_config"

echo "# 這是自動產生的環境路徑紀錄檔，請勿手動刪除" > "$CONFIG_RECORD"

case "$CHOICE" in
    1)
        # Echo the default path mode to the config file
        echo "export CONDA_ENV_MODE='MODE_1'" >> "$CONFIG_RECORD"
        echo "export CONDA_ENV='acmg_rule'"   >> "$CONFIG_RECORD"
        ;;
    2)
        # Echo the project path mode to the config file
        echo "export CONDA_ENV_MODE='MODE_2'"     >> "$CONFIG_RECORD"
        echo "export CONDA_ENV='$ENV_PATH'"       >> "$CONFIG_RECORD"
        echo "export CONDA_PKGS_DIRS='$PKG_PATH'" >> "$CONFIG_RECORD"
        ;;
    3)
        # Echo the custom path mode to the config file
        echo "export CONDA_ENV_MODE='MODE_3'".    >> "$CONFIG_RECORD"
        echo "export CONDA_ENV='$CUSTOM_PATH'"    >> "$CONFIG_RECORD"
        echo "export CONDA_PKGS_DIRS='$PKG_PATH'" >> "$CONFIG_RECORD"
        ;;
esac
echo "已將環境設定成功紀錄至 $CONFIG_RECORD"
