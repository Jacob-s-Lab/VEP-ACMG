#!/bin/bash
# ============================================================
# Usage:
#   bash submit_acmg.sh
#
# sample_acmg.list: one VEP file per line, e.g.
#   /path/to/sample1.vep.tsv
#   /path/to/sample1.vep.mane_plus_clinical.tsv
#   /path/to/sample2.vep.tsv
# ============================================================

# ----------- Config file ------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "[Error] 找不到設定檔 config.sh。"
    exit 1
fi
set -euo pipefail


# -------- log file settings ---------
mkdir -p "$SUBMIT_LOG_DIR"
TIME=`date +%Y%m%d%H%M`
logfile=${SUBMIT_LOG_DIR}/${TIME}_submit_acmg.log
# Redirect standard output and error to the log file
exec > "$logfile" 2>&1


# -------- temp argument for auto-generated sample list ---------
AUTO_GENERATED_TMP=""
trap 'if [[ -n "$AUTO_GENERATED_TMP" && -f "$AUTO_GENERATED_TMP" ]]; then rm -f "$AUTO_GENERATED_TMP"; fi' EXIT


# -------- Checking conda environment ---------
echo "[Info] 正在檢查分析環境配置..."
# 呼叫 config.sh 裡的啟動函式，若失敗就終止
if ! activate_conda_env; then
    echo "[Error] Conda 環境啟動失敗，請重新執行 /work/${USER}/VEP-ACMG/utils/setup_env.sh 修復環境。"
    exit 1
fi


## Define the sample list file that contains the absolute paths for the VEP outputs.
if [[ ! -f "$ACMG_SAMPLE_LIST" || ! -s "$ACMG_SAMPLE_LIST" ]]; then
    echo "[Info] $ACMG_SAMPLE_LIST 不存在或為空，自動抓取 $OUTPUT_DIR 下所有 VEP TSV"
    shopt -s nullglob
    all_tsvs=()
    for f in $OUTPUT_DIR/*/VEP_output/*.vep*.tsv; do
        all_tsvs+=("$(realpath "$f")")
    done
    shopt -u nullglob

    if [[ "${#all_tsvs[@]}" -eq 0 ]]; then
        echo "[Error] $OUTPUT_DIR 中找不到任何 VEP TSV 檔案"
        exit 1
    fi

    AUTO_GENERATED_TMP="$(mktemp)"
    ACMG_SAMPLE_LIST="$AUTO_GENERATED_TMP"
    printf "%s\n" "${all_tsvs[@]}" > "$ACMG_SAMPLE_LIST"
    echo "[Info] 找到 ${#all_tsvs[@]} 個 VEP TSV，寫入暫存 list: $ACMG_SAMPLE_LIST"
fi

GENERATED_SCRIPTS=()
declare -A SCRIPT_TO_TSVS
SKIP_LOG="${OUTPUT_DIR}/acmg_skipped_samples.warnings"
echo "These samples list in $ACMG_SAMPLE_LIST are skipped:" > "$SKIP_LOG"

while IFS= read -r smdir; do
    # Strip Windows line endings and leading/trailing whitespace
    smdir="${smdir%$'\r'}"
    smdir="${smdir#"${smdir%%[![:space:]]*}"}"
    smdir="${smdir%"${smdir##*[![:space:]]}"}"
    [[ -z "$smdir" || "$smdir" =~ ^# ]] && continue

    if [[ ! -f "$smdir" ]]; then
        echo "[Warning] File $smdir does not exist. Skipping."
        echo "$smdir" >> "$SKIP_LOG"
        continue
    fi

    SAMPLE_ID="$(basename "$smdir" .tsv)"
    SAMPLE="$(echo "$SAMPLE_ID" | sed 's/\.vep.*//')"
    SCRIPT_PATH="$(dirname "$smdir")/../script"
    mkdir -p "$SCRIPT_PATH"

    # Generate per-sample run script from template
    SAMPLE_SCRIPT="${SCRIPT_PATH}/${SAMPLE}_run_acmg.sh"
    if [[ ! -f "$SAMPLE_SCRIPT" ]]; then
        cp "${ACMG_SCRIPT}/run_acmg.sh" "$SAMPLE_SCRIPT"
        sed -i "s|config_file|${CONFIG_FILE}|g"  "$SAMPLE_SCRIPT"
        sed -i "s|sample_name|${SAMPLE}|g"       "$SAMPLE_SCRIPT"
        GENERATED_SCRIPTS+=("$SAMPLE_SCRIPT")
    fi

    SCRIPT_TO_TSVS["$SAMPLE_SCRIPT"]+="$smdir "

done < "$ACMG_SAMPLE_LIST"

if [[ "${#SCRIPT_TO_TSVS[@]}" -eq 0 ]]; then
    echo "[Error] No TSV files found."
    exit 1
fi

## Remove empty skip log if no samples were skipped
if [[ $(wc -l < "$SKIP_LOG") -le 1 ]]; then
    rm -f "$SKIP_LOG"
fi


echo "[Info] Generated scripts: ${#GENERATED_SCRIPTS[@]}"
echo "[Info] Submitting ACMG array job for ${#SCRIPT_TO_TSVS[@]} sample(s)"
for script in "${!SCRIPT_TO_TSVS[@]}"; do
    tsvs=(${SCRIPT_TO_TSVS["$script"]})
    n=${#tsvs[@]}
    sbatch --array=0-$(( n - 1 )) \
        --mail-user="${USERMAIL}" \
        "$script" \
        "${tsvs[@]}"
done

echo "[Info] 已送出, squeue --me 或 sacct 查看進度"
