#!/bin/bash
#SBATCH -p ngs92G
#SBATCH -c 14
#SBATCH --mem=92g
#SBATCH -A MST109178
#SBATCH -J VEP_sample_name
#SBATCH -o /dev/null
#SBATCH -e /dev/null
#SBATCH --mail-type=FAIL

source config_file

SAMPLE="sample_name"
OUTPUT_VCF_PATH="output_vcf_path"
LIST_FILE="${OUTPUT_VCF_PATH}/vcf_file_list.txt"

mkdir -p $OUTPUT_VCF_PATH
cd $OUTPUT_VCF_PATH

##############################
# Paths and general settings #
##############################
# Path of VEP
VEP_CACHE=/staging/reserve/jacobhsu/reference/VEP/Cache
VEP_FASTA=/staging/reserve/jacobhsu/reference/VEP/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz
VEP_PLUGIN_DIR=/staging/reserve/jacobhsu/reference/VEP/plugins
VEP_PLUGIN_DATA=/staging/reserve/jacobhsu/reference/VEP/plugins_data
Custom_Annotation=/staging/reserve/jacobhsu/reference/VEP/custom_annotation

# plugin paths
SpliceAI_snv=${VEP_PLUGIN_DATA}/SpliceAI/spliceai_scores.masked.snv.hg38.vcf.gz
SpliceAI_indel=${VEP_PLUGIN_DATA}/SpliceAI/spliceai_scores.masked.indel.hg38.vcf.gz
PrimateAI=${VEP_PLUGIN_DATA}/PrimateAI/PrimateAI_scores_v0.2_GRCh38_sorted.tsv.bgz
dbNSFP=${VEP_PLUGIN_DATA}/dbNSFP_4.9a/dbNSFP4.9a_grch38.gz
dbscSNV=${VEP_PLUGIN_DATA}/dbscSNV1.1/dbscSNV1.1_GRCh38.txt.gz
DosageSensitivity=${VEP_PLUGIN_DATA}/DosageSensitivity/Collins_rCNV_2022.dosage_sensitivity_scores.tsv.gz
satMutMPRA=${VEP_PLUGIN_DATA}/satMutMPRA/satMutMPRA_GRCh38_ALL.gz
MaxEntScan=${VEP_PLUGIN_DATA}/MaxEntScan/fordownload
LOEUF=${VEP_PLUGIN_DATA}/LOEUF_GRCH38/loeuf_dataset_grch38.tsv.gz
LoFtool=${VEP_PLUGIN_DIR}/LoFtool_scores.txt
pLI=${VEP_PLUGIN_DIR}/pLI_values.txt

# custom annotation file paths
DVD=${Custom_Annotation}/DVD/DVDv9.2_GRCh38.filter.vcf.gz
ClinVar=${Custom_Annotation}/ClinVar20251109_DB/clinvar_20251109.cleaned.vcf.gz
MitoMap=${Custom_Annotation}/MitoMap/MitoMap_disease_20260418.norm.vcf.gz
TWB_NTU_SNV=${Custom_Annotation}/TWB_NTU_SNV/TWB1490_snv_custom_addAF.vcf.bgz
TWB_official_SNV=${Custom_Annotation}/TWB_official_SNV/TWB_official_snv_indel_AF.vcf.gz
SG10K_SNV="${Custom_Annotation}/SG10K/SG10K_Health_r5.3.2.sites.chr###CHR###.filtered.vcf.gz"
gnomADv4exome="${Custom_Annotation}/gnomAD_v4.1_SNV/exomes/gnomad.exomes.v4.1.sites.chr###CHR###.vcf.bgz"
gnomADv4genome="${Custom_Annotation}/gnomAD_v4.1_SNV/genomes/gnomad.genomes.v4.1.sites.chr###CHR###.vcf.bgz"
gnomADv3cov=${Custom_Annotation}/gnomAD_v4.1_SNV/gnomad.genomes.r3.0.1.meanDP.bed.gz
rmsk=${Custom_Annotation}/RepeatMasker20221018/repeatMasker.bed.gz
plp_aachange=${Custom_Annotation}/ClinVar20251109_DB/hg38_pathogenicDB_AAchange_vClinVar20251109.select.vcf.gz
TWB_mtDNA=${Custom_Annotation}/TWB_mtDNA/twb1465_mtDNA_af.vcf.bgz
gnomAD_mtDNA=${Custom_Annotation}/TWB_mtDNA/gnomad_mtDNA_af.vcf.bgz

# custom annotation setting
custom_dvd="file=${DVD},short_name=DVD_SNV,format=vcf,type=exact,fields=GENE%Variant_Classification"
custom_clinvar="file=${ClinVar},short_name=ClinVar,format=vcf,type=exact,coords=0,fields=ALLELEID%CLNSIG%CLNSIGCONF%CLNREVSTAT%NumberSubmitters%NAME"
custom_mitomap="file=${MitoMap},short_name=MitoMap,format=vcf,type=exact,fields=aachange%DiseaseStatus"
custom_twb_ntu_snv="file=${TWB_NTU_SNV},short_name=TWB1490_SNV,format=vcf,type=exact,fields=AF"
custom_twb_official_snv="file=${TWB_official_SNV},short_name=TWB_official_SNV,format=vcf,type=exact,fields=AF"
custom_sg10k_snv="file=${SG10K_SNV},short_name=SG10K,format=vcf,type=exact,fields=AF%AF_SgChinese%AF_SgMalay%AF_SgIndian"
custom_gnomade="file=${gnomADv4exome},short_name=gnomAD_exome,format=vcf,type=exact,fields=FILTER%AN%AF%nhomalt%AN_eas%AF_eas%nhomalt_eas"
custom_gnomadg="file=${gnomADv4genome},short_name=gnomAD_genome,format=vcf,type=exact,fields=FILTER%AN%AF%nhomalt%AN_eas%AF_eas%nhomalt_eas"
custom_gnomad_cov="file=${gnomADv3cov},short_name=gnomAD_genome_cov,format=bed,type=overlap,coords=0"
custom_rmsk="file=${rmsk},short_name=RepeatMasker,format=bed,type=overlap,coords=1"
custom_plp_aachange="file=${plp_aachange},short_name=CLN_VEP,format=vcf,type=exact,fields=Feature%AAchange%Protein_position"
custom_twb_mtdna="file=${TWB_mtDNA},short_name=TWB_mtDNA,format=vcf,type=exact,fields=AF_het_vaf05"
custom_gnomad_mtdna="file=${gnomAD_mtDNA},short_name=gnomAD_mtDNA,format=vcf,type=exact,fields=AF_hom%AF_het%AF_hom_eas%AF_het_eas"

# modules and environment setting
source /etc/profile.d/lmod.sh
module load biology Anaconda/Anaconda3
conda activate /opt/ohpc/Taiwania3/pkg/biology/vep/vep_v115

# log file print info setting
source ${UTILS_DIR}/job_utils.sh
set -euo pipefail


################
# Define array #
################
ARRAY_OFFSET=$((SLURM_ARRAY_TASK_ID + 1)) 

# Extract input VCF file for this array task
INPUT_VCF_FILE=$(sed -n "${ARRAY_OFFSET}p" "$LIST_FILE")

# Check if the INPUT_VCF_FILE is valid
if [ -z "$INPUT_VCF_FILE" ] || [ ! -f "$INPUT_VCF_FILE" ]; then
    echo "[Error] $(date '+%Y-%m-%d %H:%M:%S') - Cannot find VCF file for array task ID $SLURM_ARRAY_TASK_ID."
    exit 1
fi

# Extract chromosome from filename
VCF_BASENAME=$(basename "$INPUT_VCF_FILE" .vcf.gz)
CHROM=$(echo "$VCF_BASENAME" | awk -F'.' '{print $NF}') 

LOGDIR="${OUTPUT_DIR}/${SAMPLE}/logs"
TIME=`date +%Y%m%d%H%M`
logfile=${LOGDIR}/${TIME}_${SAMPLE}_${CHROM}_vep.log

# call function from job_utils.sh to initialize log file
start_job


############################
# For transcript selection #
############################
if [[ $CHROM =~ "mane_plus_clinical" ]]; then
    plp_aachange="${Custom_Annotation}/ClinVar20251109_DB/hg38_pathogenicDB_AAchange_vClinVar20251109.clinical.vcf.gz"
    custom_plp_aachange="file=${plp_aachange},short_name=CLN_VEP,format=vcf,type=exact,fields=Feature%AAchange%Protein_position"
    
    MANE_ORDER="mane_plus_clinical,mane_select"
else
    MANE_ORDER="mane_select,mane_plus_clinical"
fi

###########
# run vep #
###########
vep --cache --offline \
    -i $INPUT_VCF_FILE \
    --dir_cache $VEP_CACHE \
    --dir_plugin $VEP_PLUGIN_DIR \
    --merged \
    --format vcf \
    --assembly GRCh38 \
    --variant_class \
    --regulatory \
    --uniprot \
    --numbers \
    --mirna \
    --no_escape \
    --no_stats \
    --hgvs \
    --symbol \
    --mane \
    --biotype \
    --check_existing \
    --af_gnomade \
    --af_gnomadg \
    --distance 200 \
    --pick --pick_order ${MANE_ORDER},rank,canonical,appris,biotype,length \
    --force_overwrite \
    --plugin dbscSNV,${dbscSNV} \
    --plugin dbNSFP,${dbNSFP},GERP++_RS,SIFT_score,SIFT_pred,Polyphen2_HVAR_score,Polyphen2_HVAR_pred,Polyphen2_HDIV_score,Polyphen2_HDIV_pred,MutationTaster_score,MutationTaster_pred,FATHMM_score,FATHMM_pred,PROVEAN_score,PROVEAN_pred,MetaSVM_score,MetaSVM_pred,MetaLR_score,MetaLR_pred,LRT_score,LRT_pred,MutationAssessor_score,MutationAssessor_pred,M-CAP_score,M-CAP_pred,CADD_raw,CADD_phred,DANN_score,DANN_rankscore,fathmm-MKL_coding_score,fathmm-MKL_coding_pred \
    --plugin SpliceAI,snv=${SpliceAI_snv},indel=${SpliceAI_indel} \
    --plugin LOEUF,file=${LOEUF},match_by=gene \
    --plugin PrimateAI,${PrimateAI} \
    --plugin MaxEntScan,${MaxEntScan},SWA,NCSS \
    --plugin DosageSensitivity,file=${DosageSensitivity} \
    --plugin satMutMPRA,file=${satMutMPRA} \
    --plugin LoFtool,${LoFtool} \
    --plugin pLI,${pLI} \
    --plugin NMD \
    --custom "${custom_dvd}" \
    --custom "${custom_clinvar}" \
    --custom "${custom_mitomap}" \
    --custom "${custom_twb_ntu_snv}" \
    --custom "${custom_twb_official_snv}" \
    --custom "${custom_sg10k_snv}" \
    --custom "${custom_gnomade}" \
    --custom "${custom_gnomadg}" \
    --custom "${custom_gnomad_cov}" \
    --custom "${custom_rmsk}" \
    --custom "${custom_plp_aachange}" \
    --custom "${custom_twb_mtdna}" \
    --custom "${custom_gnomad_mtdna}" \
    --fasta $VEP_FASTA \
    --vcf \
    --compress_output bgzip \
    -o ${SAMPLE}.vep.${CHROM}.vcf.gz

