#!/bin/bash

# ----------- Config file ------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

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
logfile=${SUBMIT_LOG_DIR}/${TIME}_submit.log
# Redirect standard output and error to the log file
exec > "$logfile" 2>&1


# -------- Checking conda environment ---------
echo "[Info] 正在檢查分析環境配置..."
# 呼叫 config.sh 裡的啟動函式，若失敗就終止
if ! activate_conda_env; then
    echo "[Error] Conda 環境啟動失敗，請重新執行 setup_env.sh 修復環境。"
    exit 1
fi


# staging:只放清單中選到的 VCF 連結(每次執行前清空,不寫進 logs)
rm -rf "$STAGE_DIR" && mkdir -p "$STAGE_DIR"


# -------- Checking sample list ---------
if [[ ! -f "$SAMPLE_LIST" || ! -s "$SAMPLE_LIST" ]]; then
    echo "[Info] $SAMPLE_LIST 不存在或為空，自動抓取 $INPUT_DIR 下所有 VCF"
    shopt -s nullglob
    all_vcfs=()
    for f in "$INPUT_DIR"/*.vcf.gz "$INPUT_DIR"/*.vcf; do
        [[ "$f" == *.tbi || "$f" == *.gvcf.gz ]] && continue
        all_vcfs+=("$(basename "$f")")
    done
    shopt -u nullglob

    if [[ "${#all_vcfs[@]}" -eq 0 ]]; then
        echo "[Error] $INPUT_DIR 中找不到任何 VCF 檔案"
        exit 1
    fi

    SAMPLE_LIST="$(mktemp)"
    printf "%s\n" "${all_vcfs[@]}" > "$SAMPLE_LIST"
    echo "[Info] 找到 ${#all_vcfs[@]} 個 VCF，寫入暫存 list: $SAMPLE_LIST"
fi

# ===== 依 sample.list 挑出要跑的 case,建 symlink 到 STAGE_DIR =====
# 每行可為:
#   1) 完整路徑 / INPUT_DIR 下的完整檔名 (xxx.vcf.gz / xxx.vcf)  → 以原檔名為 sample_id
#   2) 樣本 ID(xxx,自動補 .vcf.gz / .vcf)                       → sample_id = xxx
#   3) 前綴 ID(xxx,檔名為 xxx....vcf.gz 這種帶後綴)             → sample_id = xxx(用短 ID 命名)
# 支援 .vcf.gz / .vcf(前綴比對會排除 .tbi 索引與 .gvcf.gz);# 開頭或空行跳過。
n=0
SKIP_LOG="${OUTPUT_DIR}/skipped_samples.warnings"
echo "These samples list in $SAMPLE_LIST are skipped:" > "$SKIP_LOG"

while IFS= read -r v; do
    v="${v%$'\r'}"                                    # 去掉可能的 Windows 換行
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"   # 去頭尾空白
    [[ -z "$v" || "$v" =~ ^# ]] && continue

    src=""; name=""
    if   [[ -f "$v" ]];                    then src="$v";                   name="$(basename "$src")"
    elif [[ -f "$INPUT_DIR/$v" ]];         then src="$INPUT_DIR/$v";        name="$v"
    elif [[ -f "$INPUT_DIR/$v.vcf.gz" ]];  then src="$INPUT_DIR/$v.vcf.gz"; name="$v.vcf.gz"
    elif [[ -f "$INPUT_DIR/$v.vcf" ]];     then src="$INPUT_DIR/$v.vcf";    name="$v.vcf"
    else
        # 前綴比對: 找 INPUT_DIR 下以 $v 開頭、且為 .vcf.gz/.vcf 的檔(排除 .gvcf.gz、.tbi)
        shopt -s nullglob
        matches=()
        for f in "$INPUT_DIR/$v"*.vcf.gz "$INPUT_DIR/$v"*.vcf; do
            [[ "$f" == *.tbi || "$f" == *.gvcf.gz ]] && continue
            matches+=("$f")
        done
        shopt -u nullglob
        if   [[ ${#matches[@]} -eq 1 ]]; then
            src="${matches[0]}"
            ext=".vcf.gz"; [[ "$src" == *.vcf ]] && ext=".vcf"
            name="$v$ext"                              # 用短 ID 命名,sample_id = $v
        elif [[ ${#matches[@]} -gt 1 ]]; then
            echo "[Warning] '$v' 對到多個檔,請在 sample.list 改寫更完整名稱或完整檔名:"
            printf '        %s\n' "${matches[@]}"
            echo "$v" >> "$SKIP_LOG"
            continue
        else
            echo "[Warning] input_vcf 中找不到:$v,略過"
            echo "$v" >> "$SKIP_LOG"
            continue
        fi
    fi

    ln -sf "$src" "$STAGE_DIR/$name"
    n=$((n+1))
done < "$SAMPLE_LIST"

if [[ "$n" -eq 0 ]]; then
    echo "[Error] sample.list 沒有任何可對應到 input_vcf 的 case"
    exit 1
fi

## Remove empty skip log if no samples were skipped
if [[ $(wc -l < "$SKIP_LOG") -le 1 ]]; then
    rm -f "$SKIP_LOG"
fi

echo "[Info] 本次送出 $n 個 case"

# ===== 送出 VEP pipeline (只跑 STAGE_DIR 內的 case) =====
cd "$VEP_SCRIPT"
python 00_vep_batch_submitter.py "$STAGE_DIR" "$OUTPUT_DIR" "$CONFIG_FILE"
echo "[Info] 已送出, squeue --me 或 sacct 查看進度"
