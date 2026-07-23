#!/bin/bash
#SBATCH -p ngs7G
#SBATCH -c 1
#SBATCH --mem=7g
#SBATCH -A MST109178
#SBATCH -J VEPsubmit_sample_name
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-type=FAIL

source config_file

SAMPLE="sample_name"
OUTPUT_VCF_PATH="output_vcf_path"
SCRIPT_PATH="script_path"
NFILES_FILE="${OUTPUT_VCF_PATH}/vcf_file_list.txt"

# log file
LOGDIR="${OUTPUT_DIR}/${SAMPLE}/logs"
TIME=`date +%Y%m%d%H%M`
logfile=${LOGDIR}/${TIME}_${SAMPLE}_submit_vep.log

# Redirect standard output and error to the log file
exec > "$logfile" 2>&1

#################
# VEP array job #
#################
# Calculate last index for SLURM array
NFILES=$(cat "$NFILES_FILE" | wc -l)

if [ "$NFILES" -eq 0 ]; then
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - No VCF files were generated during preprocessing. Skipping VEP annotation"
    exit 0
fi

LAST_INDEX=$((NFILES - 1))

# Submit the VEP array job
echo "$(date '+%Y-%m-%d %H:%M:%S') - Submitting $NFILES VEP tasks (Array: 0-$LAST_INDEX) using ${SCRIPT_PATH}/${SAMPLE}_vep.sh..."
VEP_ARRAY_ID=$(sbatch --parsable --mail-user=$USERMAIL --array=0-$LAST_INDEX ${SCRIPT_PATH}/${SAMPLE}_vep.sh)

if [ -z "$VEP_ARRAY_ID" ]; then
    echo "[Error] $(date '+%Y-%m-%d %H:%M:%S') - Failed to submit VEP array job 02_vep.sh"
    exit 1
fi

echo -e "VEP Array Job ID: ${VEP_ARRAY_ID}\n"


###################
# VCF combine job #
###################
# Submit the final merge job dependent on the VEP array completion
echo "$(date '+%Y-%m-%d %H:%M:%S') - Submitting final merge task with dependency on VEP Array $VEP_ARRAY_ID..."

MERGE_JOB_ID=$(sbatch --parsable --mail-user=$USERMAIL --depend=afterok:$VEP_ARRAY_ID ${SCRIPT_PATH}/${SAMPLE}_post_vep.sh)

if [ -z "$MERGE_JOB_ID" ]; then
    echo "[Error] $(date '+%Y-%m-%d %H:%M:%S') - Failed to submit merge job 03_post_vep.sh"
    exit 1
fi

echo -e "Merge Job ID: ${MERGE_JOB_ID}\n"


############
# ACMG job #
############
if [[ ${RUN_ACMG} == 1 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Submitting ACMG classification task with dependency on Merge Job $MERGE_JOB_ID..."

    ## Predifined ACMG input files for the sample
    ACMG_FILES=(
        "${OUTPUT_VCF_PATH}/${SAMPLE}.vep.tsv"
        "${OUTPUT_VCF_PATH}/${SAMPLE}.vep.mane_plus_clinical.tsv"
    )

    ACMG_JOB_ID=$(sbatch --parsable --mail-user=$USERMAIL \
        --depend=afterok:$MERGE_JOB_ID --array=0-1 \
        ${SCRIPT_PATH}/${SAMPLE}_run_acmg.sh "${ACMG_FILES[@]}")

    if [ -z "$ACMG_JOB_ID" ]; then
        echo "[Error] $(date '+%Y-%m-%d %H:%M:%S') - Failed to submit ACMG job run_acmg.sh"
        exit 1
    fi

    echo -e "ACMG Job ID: ${ACMG_JOB_ID}\n"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ACMG classification task is disabled. Skipping ACMG job submission."
fi


echo "Pipeline control complete. All tasks chained successfully."
