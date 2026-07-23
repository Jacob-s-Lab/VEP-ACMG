import os
import re
import sys
import subprocess
import time

"""
This script automates the submission of VEP annotation jobs for multiple samples. 
It generates bash scripts for each VCF file in the input directory. 

Usage:
    module load Python/3.12.2
    python 00_vep_batch_submitter.py <input_vcf_directory> <output_directory> <config_file>

It will create a subdirectory `VEP_output` under the <output_directory>
"""

if len(sys.argv) != 4:
    print("\n" + "="*75)
    print("Error: Incorrect number of arguments.")
    print("\nUsage:")
    print(" python 00_vep_batch_submitter.py <input_vcf_directory> <output_directory> <config_file>")
    print("\nExample:")
    print(" python 00_vep_batch_submitter.py /path/to/vcfs /path/to/output /path/to/config.sh")
    print("="*75 + "\n")
    
    sys.exit(1)

# === Arguments ===
input_vcf_path = os.path.abspath(sys.argv[1])
output_vcf_path = os.path.abspath(sys.argv[2])
config_file = os.path.abspath(sys.argv[3])

vcf_files = [f for f in os.listdir(input_vcf_path) if f.endswith((".vcf.gz", ".vcf"))]

# === Bash Script Template ===
bash_template = """#!/bin/bash

source {config_file}

SAMPLE_ID={sample_id}
INPUT_VCF={input_vcf_path}/{full_vcf_name}
OUTPUT_VCF_PATH={output_vcf_path}/${{SAMPLE_ID}}/VEP_output
SCRIPT_PATH={output_vcf_path}/${{SAMPLE_ID}}/script
CONFIG_FILE={config_file}

mkdir -p ${{SCRIPT_PATH}}

##########################
# sample specific script #
##########################
## Copy and customize preprocess script
cp ${{VEP_SCRIPT}}/01_preprocess.sh ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh
sed -i 's|config_file|'${{CONFIG_FILE}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh
sed -i 's|sample_name|'${{SAMPLE_ID}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh
sed -i 's|input_vcf|'${{INPUT_VCF}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh
sed -i 's|output_vcf_path|'${{OUTPUT_VCF_PATH}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh

## Copy and customize VEP submission script
cp ${{VEP_SCRIPT}}/02_submit_vep.sh ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh
sed -i 's|config_file|'${{CONFIG_FILE}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh
sed -i 's|sample_name|'${{SAMPLE_ID}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh
sed -i 's|script_path|'${{SCRIPT_PATH}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh
sed -i 's|output_vcf_path|'${{OUTPUT_VCF_PATH}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh

## Copy and customize VEP script
cp ${{VEP_SCRIPT}}/02_vep.sh ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_vep.sh
sed -i 's|config_file|'${{CONFIG_FILE}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_vep.sh
sed -i 's|sample_name|'${{SAMPLE_ID}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_vep.sh
sed -i 's|output_vcf_path|'${{OUTPUT_VCF_PATH}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_vep.sh

## Copy and customize post-VEP script
cp ${{VEP_SCRIPT}}/03_post_vep.sh ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_post_vep.sh
sed -i 's|config_file|'${{CONFIG_FILE}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_post_vep.sh
sed -i 's|sample_name|'${{SAMPLE_ID}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_post_vep.sh
sed -i 's|output_vcf_path|'${{OUTPUT_VCF_PATH}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_post_vep.sh

## Copy and customize ACMG script
if [[ ${{RUN_ACMG}} == 1 ]]; then
    cp ${{ACMG_SCRIPT}}/run_acmg.sh ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_run_acmg.sh
    sed -i 's|config_file|'${{CONFIG_FILE}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_run_acmg.sh
    sed -i 's|sample_name|'${{SAMPLE_ID}}'|g' ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_run_acmg.sh
fi


########################
# preprocess input VCF #
########################
echo "--- Stage 1: Submit 01_preprocess.sh for ${{SAMPLE_ID}} ---"

# Use --parsable to get Job ID
JOB_ID_01=$(sbatch --parsable --mail-user=${{USERMAIL}} ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_preprocess.sh)

if [ -z "${{JOB_ID_01}}" ]; then
    echo "Error: Failed to submit 01_preprocess.sh"
    exit 1
fi

echo "Stage 1 Job ID: ${{JOB_ID_01}}"


################################
# submit vep array control job #
################################
echo "--- Stage 2: Submit 02_submit_vep.sh for ${{SAMPLE_ID}} ---"

# Execute the VEP control job only after Stage 1 completes successfully
JOB_ID_02=$(sbatch --parsable --mail-user=${{USERMAIL}} \
    --depend=afterok:${{JOB_ID_01}} \
    ${{SCRIPT_PATH}}/${{SAMPLE_ID}}_submit_vep.sh)

if [ -z "${{JOB_ID_02}}" ]; then
    echo "Error: Failed to submit 02_submit_vep.sh"
    scancel "${{JOB_ID_01}}"
    exit 1
fi

echo "Stage 2 Job ID: ${{JOB_ID_02}}"
"""

# === Write the bash scripts and run them ===
for vcf in vcf_files:
    sample_id = re.sub(r'\.vcf(\.gz)?$', '', vcf)

    script_output_dir = os.path.join(output_vcf_path, sample_id)
    os.makedirs(script_output_dir, exist_ok=True)

    bash_path = os.path.join(script_output_dir, f"{sample_id}_submit.sh")

    with open(bash_path, "w") as f:
        f.write(bash_template.format(
            sample_id=sample_id,
            input_vcf_path=input_vcf_path,
            output_vcf_path=output_vcf_path,
            config_file=config_file,
            full_vcf_name=vcf
        ))

    subprocess.run(["sh", bash_path])
    time.sleep(1)
