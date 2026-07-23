#!/bin/bash
#SBATCH -A MST109178
#SBATCH -J filter
#SBATCH -p ngs7G
#SBATCH -c 1
#SBATCH --mem=7g
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-user=
#SBATCH --mail-type=END,FAIL

###############################################################################
# filter_acmg.py 設定檔式啟動器(本檔、filter_acmg.py、gene.list 同放 ACMG_filter/)
#   - 篩選條件:要用就把該行前面的 # 拿掉;不用就留 #
#
# Usage:
#   bash run_filter.sh sample.vep.ACMG.tsv 
# 或
#   sbatch run_filter.sh sample.vep.ACMG.tsv
###############################################################################
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
logfile=${SUBMIT_LOG_DIR}/${TIME}_acmg_filter.log
# Redirect standard output and error to the log file
exec > "$logfile" 2>&1


# ACMG_output 目錄(輸入/輸出/filter_acmg.py 所在)。
# 用 sbatch 送出時 Slurm 會把腳本複製到 /var/spool/slurm/... 執行,
# $BASH_SOURCE 會指到 spool 目錄(造成 mkdir filtered 權限錯誤),
# 故改用固定絕對路徑;換帳號改這行,或用環境變數 ACMG_OUTPUT_DIR 覆蓋。
SAMPLE_FILE=$1

SAMPLE_ID="$(echo "$SAMPLE_FILE" | sed 's/\.vep.*//')"
SAMPLE_PREFIX="$(basename "$SAMPLE_FILE" .tsv)"

ACMG_OUTPUT_DIR="${OUTPUT_DIR}/${SAMPLE_ID}/ACMG_output"
ACMG_FILTER_DIR="$ACMG_OUTPUT_DIR/filtered"
mkdir -p "$ACMG_FILTER_DIR"

# ============ 1) 輸入 / 輸出 =============
INPUT="$ACMG_OUTPUT_DIR/${SAMPLE_FILE}"
OUTPUT="$ACMG_FILTER_DIR/${SAMPLE_PREFIX}.filtered.tsv"

# ============ 2) 篩選條件:要用就把 # 拿掉;不用就留 # ============
#   兩種模式二擇一(輸出一律自動含 ACMG_point 欄,不需 --add-score):
#   【分類模式】用到下面「分類」任一旗標 = 它們的 OR 聯集,且忽略「流程」所有條件。
#   【流程模式】完全不用分類旗標時,才會依固定順序做 AND 篩選。
OPTS=()

# ----- 分類模式(獨立;多選= OR 聯集;一旦選用就忽略下方流程條件) -----
#OPTS+=(--plp)                                             # ACMG 分類 = Pathogenic / Likely_pathogenic
#OPTS+=(--clinVar-plp)                                    # ClinVar = Pathogenic / Likely_pathogenic
#OPTS+=(--dvd-plp)                                        # DVD 分類 = Pathogenic / Likely_pathogenic

# ----- 流程模式(AND;固定順序;不用上方分類旗標時才生效) -----
OPTS+=(--pass-only)                                      # 只留 FILTER = PASS
OPTS+=(--min-dp 10)                                      # 保留 DP >= 10
OPTS+=(--acmg-ex BA1)                                    # 刪除 ACMG_rules 含 BA1 者(精確 token)
OPTS+=(--ex-blb)                                         # 去掉 ClinVar 純良性
#OPTS+=(--min-vaf 0.2)                                    # 保留 VAF >= 0.2
OPTS+=(--max-af 0.01)                                    # genome+exome AF 皆 <= 0.01(空值保留)
# OPTS+=(--gene-list "$SCRIPT_DIR/gene.list")                     # 只留清單內基因(gene.list 放同資料夾)
OPTS+=(--exonic)                                         # exonic(含 synonymous)+ splice donor/acceptor
#OPTS+=(--noncoding)                                      # 只留 non-coding(與 --exonic 擇一)
#OPTS+=(--consequence missense_variant,stop_gained)      # 自訂 consequence(搭配下一行 --mode)
#OPTS+=(--mode include)                                   # include=只留 / exclude=刪去(搭配上一行 --consequence)
OPTS+=(--acmg-ex-b-rule-only)                            # 刪除只有 B rule、無 P rule 者
OPTS+=(--vushigh)                                        # 只留 ACMG_point 總分 >= 3(VUS-high)

OPTS+=(-v)                                                # 顯示每步剩餘列數

# ============ 3) 啟用環境並執行(以下不用改) ============
activate_conda_env

# 用 tee 讓輸出(含 -v 每步計數)同時顯示並寫進 logs/(bash 直接跑也留得住 log)
python "$SCRIPT_DIR/filter_acmg.py" -i "$INPUT" -o "$OUTPUT" "${OPTS[@]+"${OPTS[@]}"}" 2>&1 | tee "$logfile"
