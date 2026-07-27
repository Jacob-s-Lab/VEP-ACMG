#!/bin/bash
#SBATCH -p ngs26G
#SBATCH -c 4
#SBATCH --mem=26g
#SBATCH -A MST109178
#SBATCH -J ACMG_sample_name
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-type=FAIL,END

source config_file

SAMPLE="sample_name"

WKDIR=${OUTPUT_DIR}/${SAMPLE}
LOGDIR=${WKDIR}/logs
OUTDIR=${WKDIR}/ACMG_output

mkdir -p $LOGDIR $OUTDIR

# log file print info setting
source ${UTILS_DIR}/job_utils.sh
set -euo pipefail


# Arguments
FILE=("$@")
SAMPLE_INPUT=${FILE[$SLURM_ARRAY_TASK_ID]}

## If the input file does not exist, skip this task
if [[ ! -f "$SAMPLE_INPUT" ]]; then
    echo "[Warning] $(date '+%Y-%m-%d %H:%M:%S') - Input file $SAMPLE_INPUT does not exist. Skipping this task."
    exit 0
fi

SAMPLE_ID=$(basename "$SAMPLE_INPUT" .tsv)
SAMPLE_OUTPUT="${SAMPLE_ID}.ACMG.tsv"
CONFIG_FILE="$ACMG_UTILS_DIR/config.json"


TIME=`date +%Y%m%d%H%M`
logfile=${LOGDIR}/${TIME}_${SAMPLE_ID}_ACMG.log
# call function from job_utils.sh to initialize log file
start_job

# Activate conda environment
activate_conda_env

# Run python
python ${ACMG_SCRIPT}/main.py \
    --config $CONFIG_FILE \
    --input $SAMPLE_INPUT \
    --output $OUTDIR/$SAMPLE_OUTPUT \
    --sampleID $SAMPLE_ID

