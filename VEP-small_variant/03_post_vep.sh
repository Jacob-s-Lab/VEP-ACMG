#!/bin/bash
#SBATCH -p ngs7G
#SBATCH -c 1
#SBATCH --mem=7g
#SBATCH -A MST109178
#SBATCH -J CONCAT_sample_name
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-type=FAIL,END

source config_file

SAMPLE="sample_name"
OUTPUT_VCF_PATH="output_vcf_path"

# modules and environment setting
module load biology
module load BCFtools/1.18
# log file print info setting
source ${UTILS_DIR}/job_utils.sh
set -euo pipefail

LOGDIR="${OUTPUT_DIR}/${SAMPLE}/logs"
TIME=`date +%Y%m%d%H%M`
logfile=${LOGDIR}/${TIME}_${SAMPLE}_concat.log
start_job


#############################
echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Starting to concatenate VCFs\n"
#############################
cd $OUTPUT_VCF_PATH
rm -rf $OUTPUT_VCF_PATH/temp_chr
rm -f $OUTPUT_VCF_PATH/vcf_file_list.txt

# concat all annotated VCFs
echo -e "--- Concatenating annotated VCFs ---"

VEP_FILES=($(ls ${SAMPLE}.vep.chr*.vcf.gz | sort -V | sed '/chrM/{H;d}; $G' | sed '/^$/d'))
FINAL_VCF=${SAMPLE}.vep.vcf.gz

bcftools concat --naive-force -f <(printf "%s\n" "${VEP_FILES[@]}") -Oz -o $FINAL_VCF
bcftools index -t -f $FINAL_VCF

echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Concat complete. Saving to $FINAL_VCF\n"

rm -rf ${SAMPLE}.vep.chr*.vcf.gz

variant_count=$(bcftools view -H "$FINAL_VCF" | wc -l)
echo -e "[INFO] - Total variants in final VEP annotated VCF: $variant_count"

FINAL_VCF_MANE=${SAMPLE}.vep.mane_plus_clinical.vcf.gz
if [[ -f "$FINAL_VCF_MANE" ]]; then
    bcftools index -t -f $FINAL_VCF_MANE
    variant_count=$(bcftools view -H "$FINAL_VCF_MANE" | wc -l)
    echo -e "[INFO] - Total variants with both MANE select and MANE plus clinical in VEP annotated VCF: ${variant_count}\n"
else
    echo -e "[INFO] - MANE plus clinical VCF not found. Skipping...\n"
fi

# generate tsv
### pipefail temporarily disabled to avoid script exit when encountering error in this step
set +o pipefail
checkFMT=$(zgrep -v '^#' $FINAL_VCF | head -n 1 | awk '{print $9}')
set -o pipefail

# Determine fill-tags args based on available FORMAT fields
if [[ "$checkFMT" =~ GT ]] && [[ "$checkFMT" =~ AD ]] && [[ "$checkFMT" =~ DP ]] && [[ "$checkFMT" =~ VAF ]]; then
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - VCF contains GT & AD & DP & VAF in FORMAT, generating TSV..."
    FILL_TAGS_ARGS=""
elif [[ "$checkFMT" =~ GT ]] && [[ "$checkFMT" =~ AD ]] && [[ "$checkFMT" =~ DP ]]; then
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - VCF contains GT & AD & DP in FORMAT, calculating VAF and generating TSV..."
    FILL_TAGS_ARGS="FORMAT/VAF"
elif [[ "$checkFMT" =~ GT ]] && [[ "$checkFMT" =~ AD ]]; then
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - VCF contains GT & AD in FORMAT, calculating DP & VAF and generating TSV..."
    FILL_TAGS_ARGS="FORMAT/DP:1=int(smpl_sum(FORMAT/AD)),FORMAT/VAF"
else
    echo "[Warning] $(date '+%Y-%m-%d %H:%M:%S') - VCF does not contain expected FORMAT fields (GT, AD, DP). Generating TSV without sample-level genotype information."
    FILL_TAGS_ARGS="NONE"
fi

# Shared post-processing pipeline
split_vep_with_gt='bcftools +split-vep -H -f "%CHROM\t%POS\t%REF\t%ALT\t%FILTER\t[%GT\t%DP\t%AD{0}\t%AD{1}\t%VAF]\t%CSQ\n" -A tab'
split_vep_no_gt='bcftools +split-vep -H -f "%CHROM\t%POS\t%REF\t%ALT\t%FILTER\t%CSQ\n" -A tab'
fix_header() {
    sed -E '1s/\[[0-9]+\]//g' | \
    sed 's/\#//' | \
    awk 'BEGIN{FS=OFS="\t"} NR==1 {for(i=1;i<=NF;i++) if($i=="AD") {if(!f) {$i="AD_ref"; f=1} else $i="AD_alt"}} 1'
}

run_tsv() {
    local input_vcf="$1"
    local output_tsv="$2"

    if [[ "$FILL_TAGS_ARGS" == "NONE" ]]; then
        bcftools +split-vep -H -f '%CHROM\t%POS\t%REF\t%ALT\t%FILTER\t%CSQ\n' -A tab "$input_vcf" | \
            sed -E '1s/\[[0-9]+\]//g' | sed 's/\#//' \
            > "$output_tsv"
    elif [[ -z "$FILL_TAGS_ARGS" ]]; then
        bcftools +split-vep -H -f '%CHROM\t%POS\t%REF\t%ALT\t%FILTER\t[%GT\t%DP\t%AD{0}\t%AD{1}\t%VAF]\t%CSQ\n' -A tab "$input_vcf" | \
            fix_header \
            > "$output_tsv"
    else
        bcftools +fill-tags "$input_vcf" -- -t "$FILL_TAGS_ARGS" | \
            bcftools +split-vep -H -f '%CHROM\t%POS\t%REF\t%ALT\t%FILTER\t[%GT\t%DP\t%AD{0}\t%AD{1}\t%VAF]\t%CSQ\n' -A tab | \
            fix_header \
            > "$output_tsv"
    fi
}
run_tsv "$FINAL_VCF"      "${SAMPLE}.vep.tsv"
if [[ -f "$FINAL_VCF_MANE" ]]; then
    run_tsv "$FINAL_VCF_MANE" "${SAMPLE}.vep.mane_plus_clinical.tsv"
fi

echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') - Generate TSV done"


# clean up warning files
mkdir -p ${OUTPUT_VCF_PATH}/warnings
find . -maxdepth 1 -type f -name '*warnings.txt' -exec mv {} warnings/ \;
rmdir --ignore-fail-on-non-empty ${OUTPUT_VCF_PATH}/warnings

rm -rf $OUTPUT_DIR/_staged_input
