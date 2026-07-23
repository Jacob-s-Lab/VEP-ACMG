#!/bin/bash
#SBATCH -p ngs13G
#SBATCH -c 2
#SBATCH --mem=13g
#SBATCH -A MST109178
#SBATCH -J QCnorm_sample_name
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-type=FAIL

source config_file

SAMPLE="sample_name"
INPUT_VCF="input_vcf"
OUTPUT_VCF_PATH="output_vcf_path"

mkdir -p $OUTPUT_VCF_PATH
cd $OUTPUT_VCF_PATH

# setup environment & modules
module load biology
module load BCFtools/1.18

# log file print info setting
source ${UTILS_DIR}/job_utils.sh
set -euo pipefail

LOGDIR="${OUTPUT_DIR}/${SAMPLE}/logs"
mkdir -p $LOGDIR
TIME=`date +%Y%m%d%H%M`
logfile=${LOGDIR}/${TIME}_${SAMPLE}_preprocess.log

# call function from job_utils.sh to initialize log file
start_job


########################
# Input VCF preprocess #
########################
## Check chromosome format
### pipefail temporarily disabled to avoid script exit when encountering error in this step
set +o pipefail
checkCHR=$(zgrep -v '^#' $INPUT_VCF | head -n 1 | awk '{print $1}')
set -o pipefail

CHRpresent1="chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10,chr11,chr12,chr13,chr14,chr15,chr16,chr17,chr18,chr19,chr20,chr21,chr22,chrX,chrY,chrM,chrMT"
CHRpresent2="1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,X,Y,M,MT"

# Step 1. Keep only chr1-22, X, Y, M (or MT)
if [[ "$checkCHR" =~ ^chr ]]; then
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - Chromosomes have 'chr' prefix. Filtering with 'chr'..."
    bcftools view -t $CHRpresent1 $INPUT_VCF -Oz -o ${SAMPLE}.exChr.vcf.gz
    REF_FASTA=/staging/reserve/jacobhsu/reference/VEP/Homo_sapiens_assembly38.fasta
    MANE_PLUS_CLINICAL_BED=${VEP_UTILS_DIR}/mane_plus_clinical.wchr.buffer5000bp.bed
else
    echo "[Info] $(date '+%Y-%m-%d %H:%M:%S') - Chromosomes do not have 'chr' prefix. Filtering without 'chr'..."
    bcftools view -t $CHRpresent2 $INPUT_VCF -Oz -o ${SAMPLE}.exChr.vcf.gz
    REF_FASTA=/staging/reserve/jacobhsu/reference/VEP/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz
    MANE_PLUS_CLINICAL_BED=${VEP_UTILS_DIR}/mane_plus_clinical.wochr.buffer5000bp.bed
fi

# Step 2. Normalize & remove duplicate sites
bcftools norm -m -any -cs ${SAMPLE}.exChr.vcf.gz -f $REF_FASTA -Oz -o ${SAMPLE}.norm1.vcf.gz
bcftools norm --no-version -d none ${SAMPLE}.norm1.vcf.gz -Oz -o ${SAMPLE}.norm2.vcf.gz

# Step 3. Keep only SNV/indel/MNV, exclude SV and other ALT
bcftools view --type snps,indels,mnps ${SAMPLE}.norm2.vcf.gz \
	-e 'ILEN>51 | ILEN<-51 | ALT~"R" | ALT~"Y" | ALT~"K" | ALT~"M" | ALT~"S" | ALT~"W" | ALT~"B" | ALT~"V" | ALT~"D" | ALT~"H" | ALT~"N" | ALT~"\*"' \
	-Oz -o ${SAMPLE}.cleaned.vcf.gz
bcftools index -t -f ${SAMPLE}.cleaned.vcf.gz

rm ${SAMPLE}.exChr.vcf.gz ${SAMPLE}.norm*.vcf.gz

echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') Sample QC and normalization done\n"


#############
# Split VCF #
#############
# Split by chromosome
OUTPUT_CHR_DIR="${OUTPUT_VCF_PATH}/temp_chr"
mkdir -p "$OUTPUT_CHR_DIR"

if [[ "$checkCHR" =~ ^chr ]]; then
    IFS=',' read -r -a CHR_ARRAY <<< "$CHRpresent1"
else
    IFS=',' read -r -a CHR_ARRAY <<< "$CHRpresent2"
fi

for CHROM in "${CHR_ARRAY[@]}"; do 
    if [[ $CHROM =~ ^chr ]]; then
        OUTPUT_VCF="${OUTPUT_CHR_DIR}/${SAMPLE}.${CHROM}.vcf.gz"
    else
        OUTPUT_VCF="${OUTPUT_CHR_DIR}/${SAMPLE}.chr${CHROM}.vcf.gz"
    fi

    bcftools view -r $CHROM ${SAMPLE}.cleaned.vcf.gz -Oz -o $OUTPUT_VCF
    
    ### remove the vcf if no variants found
    variant_count=$(bcftools view -H "$OUTPUT_VCF" | wc -l)
    if [ "$variant_count" -eq 0 ]; then
        echo "  - ${CHROM}: No variants found. Removing $OUTPUT_VCF"
        rm $OUTPUT_VCF
    else
        echo "  - ${CHROM}: Found $variant_count variants. File saved to $OUTPUT_VCF"
    fi
done

# Extract MANE PLUS CLINICAL variants
## variants locate on the gene that have both MANE SELECT and MANE PLUS CLINICAL
OUTPUT_VCF="${OUTPUT_CHR_DIR}/${SAMPLE}.mane_plus_clinical.vcf.gz"
bcftools view -R $MANE_PLUS_CLINICAL_BED ${SAMPLE}.cleaned.vcf.gz -Oz -o $OUTPUT_VCF

### remove the vcf if no variants found
variant_count=$(bcftools view -H "$OUTPUT_VCF" | wc -l)
if [ "$variant_count" -eq 0 ]; then
    echo "  - MANE PLUS CLINICAL: No variants found. Removing $OUTPUT_VCF"
    rm $OUTPUT_VCF
else
    echo "  - MANE PLUS CLINICAL: Found $variant_count variants. File saved to $OUTPUT_VCF"
fi

ls "${OUTPUT_CHR_DIR}"/*.vcf.gz | sort -V > "${OUTPUT_VCF_PATH}/vcf_file_list.txt"
