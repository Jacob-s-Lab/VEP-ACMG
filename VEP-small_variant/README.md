# VEP Annotation

## Requirement
- Python 3.12.2
- BCFtools 1.18
- Anaconda3 23.3.1
- Ensembl VEP v115.1

## Reference Genomes
The workflow automatically detects the chromosome naming convention and applies the appropriate reference during normalization:
- **UCSC Style (with "chr" prefix):** Uses `Homo_sapiens_assembly38.fasta`.
- **Ensembl Style (without "chr" prefix):** Uses `Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz`.

### Customization: Changing Reference Genomes
If you need to use a different reference FASTA, you must manually update the `REF_FASTA` variable in `01_preprocess.sh`. 

> [!IMPORTANT]
> The script uses a conditional check to handle chromosome naming conventions (with or without the "chr" prefix). Ensure you update the correct path within the `if-else` block:
> - **With "chr" prefix**: Update `REF_FASTA` inside the `if` block.
> - **Without "chr" prefix**: Update `REF_FASTA` inside the `else` block.

**Example in `01_preprocess.sh`:**
```bash
if [[ "$checkCHR" =~ ^chr ]]; then
    # Update this path for 'chr' prefixed VCFs
    REF_FASTA=/path/to/your/custom_hg38_with_chr.fasta
else
    # Update this path for non-'chr' prefixed VCFs
    REF_FASTA=/path/to/your/custom_GRCh38_no_chr.fa.gz
fi
```

## Script description
- `00_vep_batch_submitter.py`: Submit the slurm job(s) for annotating the VCFs under the given directory
- `01_preprocess.sh`: Normalize the input VCF and split the input VCF by chromosomes
- `02_submit_vep.sh`: Submit array job according to the number of VCFs
- `02_vep.sh`: Annotate small variants with Ensembl VEP
- `03_post_vep.sh`: Remove the temporary files and merge the annotation files

## Output description
The script will automatically create an `VEP_output` subdirectory under the sample folder.

### Result files
- `{sample}.cleaned.vcf.gz`: The VCF after normalization and remains only chr1-22, X, Y, M.
- `{sample}.vep.tsv`, `{sample}.vep.vcf.gz`: All variants, MANE Select transcripts are prioritized over MANE Plus Clinical when selecting transcripts.
- `{sample}.vep.mane_plus_clinical.tsv`, `{sample}.vep.mane_plus_clinical.vcf.gz`: Only variants located in the genes that have both MANE Select and MANE Plus Clinical transcripts; the selected transcripts in this file remain the MANE Plus Clinical transcript rather than the MANE Select transcripts.
  > A full list of these 65 genes can be found in [`utils/VEP/mane_plus_clinical.wchr.buffer5000bp.bed`](https://github.com/leechiehyu/VEP-ACMG/blob/master/utils/VEP/mane_plus_clinical.wchr.buffer5000bp.bed).

### Result columns
The final output is generated as a TSV file. Below are descriptions for some key columns:
| Column | Source | Description |
| :--- | :--- | :--- |
| CHROM <br/> POS <br/> REF <br/> ALT <br/> FILTER | Original input VCF | Basic variant information |
| Consequence <br/> IMPACT | VEP | Predicted functional effects of each allele on its respective transcripts |
| SYMBOL <br/> Gene <br/> Feature_type <br/> Feature <br/> SYMBOL_SOURCE <br/> HGNC_ID | VEP <br/> (Ensembl, Refseq, HGNC, EntrezGene, RFAM...) | Gene symbols and associated gene/transcript identifiers |
| EXON <br/> INTRON <br/> HGVSc <br/> HGVSp <br/> cDNA_position <br/> CDS_position <br/> Protein_position <br/> Amino_acids <br/> Codons | VEP <br/> (Ensembl, Refseq) | Coding and protein change nomenclature <br/> Positional information for variants affecting coding regions |
| Existing_variation <br/> CLIN_SIG <br/> SOMATIC <br/> PHENO | VEP | Known variants co-located with the query variant, including clinical significance and phenotype links |
| MANE <br/> MANE_SELECT <br/> MANE_PLUS_CLINICAL | VEP <br/> (MANE) | Flags indicating whether the transcript is designated as a MANE Select or MANE Plus Clinical transcript |
| SWISSPROT <br/> TREMBL <br/> UNIPARC <br/> UNIPROT_ISOFORM | VEP <br/> (UniProt) | Best-match accessions for translated protein products from UniProt-related databases |
| SIFT_pred <br/> SIFT_score <br/> Polyphen2_HDIV_pred <br/> Polyphen2_HDIV_score <br/> Polyphen2_HVAR_pred <br/> Polyphen2_HVAR_score <br/> PROVEAN_pred <br/> PROVEAN_score <br/> MutationAssessor_pred <br/> MutationAssessor_score <br/> MutationTaster_pred <br/> MutationTaster_score | VEP plugin <br/> (dbNSFP - SIFT / Polyphen-2 / PROVEAN / MutationAssessor / MutationTaster 2) | **Pathogenicity & Conservation Scores** <br/> Classic protein-level prediction tools based on amino acid substitution impact and conservation |
| LRT_pred <br/> LRT_score | VEP plugin <br/> (dbNSFP - LRT) | **Pathogenicity & Conservation Scores** <br/> Likelihood Ratio Test used to detect protein-coding variants affected by negative selection |
| FATHMM_pred <br/> FATHMM_score <br/> fathmm_MKL_coding_pred <br/> fathmm_MKL_coding_score | VEP plugin <br/> (dbNSFP - FATHMM) | **Pathogenicity & Conservation Scores** <br/> Hidden Markov Model-based scores for predicting the functional effects of protein variants |
| CADD_phred <br/> CADD_raw <br/> DANN_rankscore <br/> DANN_score | VEP plugin <br/> (dbNSFP - CADD / DANN) | **Pathogenicity & Conservation Scores** <br/> Integrative scores that combine multiple annotations into a single metric |
| MetaLR_pred <br/> MetaLR_score <br/> MetaSVM_pred <br/> MetaSVM_score <br/> M_CAP_pred <br/> M_CAP_score | VEP plugin <br/> (dbNSFP - Meta-predictors) | **Pathogenicity & Conservation Scores** <br/> Ensemble methods that combine several individual prediction tools to improve accuracy |
| GERP++_RS | VEP plugin <br/> (dbNSFP - GERP++) | **Pathogenicity & Conservation Scores** <br/> Measures evolutionary constraint; higher scores indicate highly conserved (and potentially functional) sites |
| PrimateAI | VEP plugin <br/> (PrimateAI) | **Pathogenicity & Conservation Scores** <br/> A deep learning network trained on primate genetic variation to predict human variant pathogenicity |
| SpliceAI_pred_DP_AG <br/> SpliceAI_pred_DP_AL <br/> SpliceAI_pred_DP_DG <br/> SpliceAI_pred_DP_DL <br/> SpliceAI_pred_DS_AG <br/> SpliceAI_pred_DS_AL <br/> SpliceAI_pred_DS_DG <br/> SpliceAI_pred_DS_DL <br/> SpliceAI_pred_SYMBOL | VEP plugin <br/> (SpliceAI) | **Splicing Prediction Scores** <br/> Deep learning-based scores (Delta Score and Delta Position) predicting the probability of a variant causing cryptic splicing |
| ada_score <br/> rf_score | VEP plugin <br/> (dbscSNV) | **Splicing Prediction Scores** <br/> Machine learning scores (AdaBoost and Random Forest) specifically for variants in splice site consensus regions |
| MaxEntScan_alt <br/> MaxEntScan_diff <br/> MaxEntScan_ref <br/> MES_NCSS_downstream_acceptor <br/> MES_NCSS_downstream_donor <br/> MES_NCSS_upstream_acceptor <br/> MES_NCSS_upstream_donor <br/> MES_SWA_acceptor_alt <br/> MES_SWA_acceptor_diff <br/> MES_SWA_acceptor_ref <br/> MES_SWA_acceptor_ref_comp <br/> MES_SWA_donor_alt <br/> MES_SWA_donor_diff <br/> MES_SWA_donor_ref <br/> MES_SWA_donor_ref_comp | VEP plugin <br/> (MaxEntScan) | **Splicing Prediction Scores** <br/> Predicts the strength of splice sites based on the Maximum Entropy principle, including upstream/downstream and alternative sites |
| pLI_gene_value <br/> LOEUF | VEP plugin <br/> (pLI / LOEUF) | **Gene Constraints & Sensitivity Metrics** <br/> Measures gene intolerance to Loss-of-Function (LoF) variants |
| LoFtool | VEP plugin <br/> (LoFtool) | **Gene Constraints & Sensitivity Metrics** <br/> A rank-based score for gene intolerance to loss-of-function variants |
| pHaplo <br/> pTriplo | VEP plugin <br/> (DosageSensitivity, Collins et al.) | **Gene Constraints & Sensitivity Metrics** <br/> Probabilities that a gene is sensitive to haploinsufficiency (loss of one copy) or triplosensitivity (gain of a copy) |
| NMD | VEP plugin <br/> (NMD) | **Gene Constraints & Sensitivity Metrics** <br/> Predicts whether a variant is likely to trigger Nonsense-Mediated Decay (NMD) |
| satMutMPRA | VEP plugin <br/> (satMutMPRA) | **Gene Constraints & Sensitivity Metrics** <br/> Data from saturated mutagenesis and Massively Parallel Reporter Assays (MPRA) to assess variant effects |
| RepeatMasker | RepeatMasker | Genomic repeat regions identified by RepeatMasker |
| gnomADe_AF <br/> gnomADe_AFR_AF <br/> gnomADe_AMR_AF <br/> gnomADe_ASJ_AF <br/> gnomADe_EAS_AF <br/> gnomADe_FIN_AF <br/> gnomADe_MID_AF <br/> gnomADe_NFE_AF <br/> gnomADe_REMAINING_AF <br/> gnomADe_SAS_AF <br/> gnomADg_AF <br/> gnomADg_AFR_AF <br/> gnomADg_AMI_AF <br/> gnomADg_AMR_AF <br/> gnomADg_ASJ_AF <br/> gnomADg_EAS_AF <br/> gnomADg_FIN_AF <br/> gnomADg_MID_AF <br/> gnomADg_NFE_AF <br/> gnomADg_REMAINING_AF <br/> gnomADg_SAS_AF | VEP <br/> (gnomAD) | Allele frequency (AF) across various gnomAD populations |
| gnomAD_exome <br/> gnomAD_exome_FILTER <br/> gnomAD_exome_AN <br/> gnomAD_exome_AF <br/> gnomAD_exome_nhomalt <br/> gnomAD_exome_AN_eas <br/> gnomAD_exome_AF_eas <br/> gnomAD_exome_nhomalt_eas <br/> gnomAD_genome <br/> gnomAD_genome_FILTER <br/> gnomAD_genome_AN <br/> gnomAD_genome_AF <br/> gnomAD_genome_nhomalt <br/> gnomAD_genome_AN_eas <br/> gnomAD_genome_AF_eas <br/> gnomAD_genome_nhomalt_eas <br/> gnomAD_genome_cov | gnomAD | Allele number (AN), allele frequency (AF), and homozygous individual counts across various gnomAD populations |
| DVD_SNV <br/> DVD_SNV_GENE <br/> DVD_SNV_Variant_Classification | Deafness Variation Database | Curated variant information from the Deafness Variation Database (DVD) |
| ClinVar <br/> ClinVar_ALLELEID <br/> ClinVar_CLNSIG <br/> ClinVar_CLNSIGCONF <br/> ClinVar_CLNREVSTAT <br/> ClinVar_NumberSubmitters <br/> ClinVar_NAME | ClinVar | Clinical significance, review status, and submission details retrieved directly from ClinVar |
| CLN_VEP <br/> CLN_VEP_Feature <br/> CLN_VEP_AAchange <br/> CLN_VEP_Protein_position | ClinVar | ClinVar variants re-annotated via VEP; this set is filtered to retain only missense variants for comparison | 
| TWB1490_SNV <br/> TWB1490_SNV_AF <br/> TWB_official_SNV <br/> TWB_official_SNV_AF | Taiwan Biobank | Allele frequencies calculated from internal Jacob's Lab data or official Taiwan Biobank releases |
| SG10K <br/> SG10K_AF <br/> SG10K_AF_SgChinese <br/> SG10K_AF_SgMalay <br/> SG10K_AF_SgIndian | SG10K | Allele frequencies in SG10K |
| MitoMap <br/> MitoMap_aachange <br/> MitoMap_DiseaseStatus | MitoMap | Variant and disease association information for mitochondrial DNA from MitoMap |
| TWB_mtDNA <br/> TWB_mtDNA_AF_het_vaf05 | Taiwan Biobank | Mitochondrial DNA variant data specific to the Taiwan Biobank population |
| gnomAD_mtDNA <br/> gnomAD_mtDNA_AF_hom <br/> gnomAD_mtDNA_AF_het <br/> gnomAD_mtDNA_AF_hom_eas <br/> gnomAD_mtDNA_AF_het_eas | gnomAD | Mitochondrial allele frequencies from gnomAD |

## Databases and plugins
### Data in the VEP cache
- **Ensembl database (VEP)**, version 115.1
- **MANE**, version 1.4

### Plugins
- **dbscSNV**, version 1.1
- **dbNSFP**, version 4.9a
  - **SIFT** ensembl 66, released Jan, 2015
  - **PROVEAN** ensembl 66, version 1.1, released Jan, 2015
  - **Polyphen-2**, version 2.2.2, released Feb, 2012
  - **LRT**, released November, 2009
  - **MutationTaster 2**, data retrieved in 2015
  - **MutationAssessor**, release 3
  - **FATHMM**, version 2.3
  - **fathmm-MKL**
  - **CADD**, version 1.7
  - **DANN**
  - **MetaSVM** and **MetaLR**
  - **M-CAP**, version 1.3
  - **GERP++**
- **SpliceAI** SNV and indel, version 1.3
- **LOEUF**, based on gnomAD v4, GRCh38
- **PrimateAI**, version 0.2
- **MaxEntScan**
- **DosageSensitivity**
- **satMutMPRA**
- **LoFtool**
- **pLI**
- **NMD**

### Custom datasets
- **DVD**, version 9.2
- **ClinVar**, released 20251109
- **RepeatMasker**, download from UCSC Table Browser, data last updated: 2022-10-18
- **gnomAD exome**, version 4.1
- **gnomAD genome**, version 4.1
- **gnomAD genome coverage**, version 3
- **Taiwan Biobank** SNV and indel, called by Jacob's lab
- **Taiwan Biobank** SNV and indel, released by Taiwan Biobank
- **MitoMap**, released 20260418
- **Taiwan Biobank** mitochondria SNV and indel, called by Jacob's lab
- **gnomAD mitochondria**, version 3.1