#!/bin/bash

# ==============================================================================
# Customize the variables in this section before running the pipeline.
# ------------------------------------------------------------------------------
# Fill the mail address if you want to receive email notifications when the job ends or fails.
export USERMAIL=""

# Your working directory (i.e., where this script is located)
export WKDIR="/work/${USER}/VEP-ACMG"

# Automatically run ACMG after VEP completion
## 1 = annotation + pathogenicity classification
## 0 = Only annotation
export RUN_ACMG=1
# ==============================================================================


# ==============================================================================
# Central Configuration for Annotation and Pathogenicity Classification Pipeline
# ==============================================================================
# -------- Input/Output directories --------
export INPUT_DIR="${WKDIR}/input_vcf"
export OUTPUT_DIR="${WKDIR}/results"
export STAGE_DIR="${OUTPUT_DIR}/_staged_input"

export SUBMIT_LOG_DIR="${OUTPUT_DIR}/logs"

# -------- Original scripts --------
export VEP_SCRIPT="${WKDIR}/VEP-small_variant"
export ACMG_SCRIPT="${WKDIR}/ACMG-small_variant"

export UTILS_DIR="${WKDIR}/utils"
export VEP_UTILS_DIR="${WKDIR}/utils/VEP"
export ACMG_UTILS_DIR="${WKDIR}/utils/ACMG"
export ACMG_FILTER_UTILS_DIR="${WKDIR}/utils/ACMG_filter"

# -------- Sample list --------
## sample list for running annotation (+ ACMG) pipeline
## (used in submit.sh)
export SAMPLE_LIST="${WKDIR}/sample.list"
## sample list for running ACMG classification pipeline by yourself
## (used in acmg_batch_submitter.sh)
export ACMG_SAMPLE_LIST="${ACMG_SCRIPT}/sample_acmg.list"


# -----------------------------------------------------------------------------
# Environment Management Setup
# -----------------------------------------------------------------------------
CONFIG_RECORD="${UTILS_DIR}/.env_path_config"

if [ -f "$CONFIG_RECORD" ]; then
    source "$CONFIG_RECORD"
else
    if [ -d "${UTILS_DIR}/.venv" ]; then
        export CONDA_ENV_MODE="MODE_2"
        export CONDA_ENV="${UTILS_DIR}/.venv"
        export CONDA_PKGS_DIRS="/work/${USER}/.conda/pkgs"
    else
        YML_FILE="${UTILS_DIR}/environment.yml"
        export CONDA_ENV_MODE="MODE_1"
        export CONDA_ENV="acmg_rule"
    fi
fi


activate_conda_env() {
    ml biology Anaconda/Anaconda3

    case "${CONDA_ENV_MODE:-MODE_1}" in
        "MODE_1")
            conda activate "$CONDA_ENV"
            ;;
            
        "MODE_2")
            if [ -n "${CONDA_PKGS_DIRS:-}" ]; then
                export CONDA_PKGS_DIRS="$CONDA_PKGS_DIRS"
            fi
            conda activate "$CONDA_ENV"
            ;;
            
        "MODE_3")
            if [ -n "${CONDA_PKGS_DIRS:-}" ]; then
                export CONDA_PKGS_DIRS="$CONDA_PKGS_DIRS"
            fi
            conda activate "$CONDA_ENV"
            ;;            
    esac
}