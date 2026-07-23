# ACMG Rule Implementation

This repository automates small variant classification according to ACMG guidelines using the GRCh38 reference genome. It integrates VEP annotations and multiple evidence sources to determine pathogenicity.


## Environment Setup
Use the `utils/setup_env.sh` file to setup a conda environment for running ACMG pipeline.
See the hands-on for more details.

## Usage
Only run this script manually when `RUN_ACMG=0` in `config.sh`.
List the absolute directory of the samples in `sample_acmg.list` and execute the `acmg_batch_submitter.sh` file.

``` bash 
bash acmg_batch_submitter.sh
```

> [!NOTE] 
> If no sample listed in `sample_acmg.list`, the pipeline will concurrently process all VEP-annotated TSV files.


## Configuration & Parameters
You can customize parameter cutoffs in `config.json`.

### Default mode
Set a parameter to `null` to use predefined values.

**Predefined Default Values:**
| Parameter | Default value | Note |
| --- | ---: | --- |
| AD_AF | 0.00001441287 | Allele frequency threshold for AD, XL, YL, or unspecified inheritance modes |
| AR_AF | 0.0001 | Allele frequency threshold for AR | 
| PVS1_LOEUF | 0.6 | LOEUF score <br/> follow [gnomAD](https://gnomad.broadinstitute.org/news/2024-03-gnomad-v4-0-gene-constraint/) |
| PP3_CADD_SUP | 25.3 | PP3 CADD cutoff <br/> follow [ClinGen guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC9748256/pdf/main.pdf) |
| PP3_CADD_MOD | 28.1 | PP3 moderate CADD cutoff <br/> follow [ClinGen guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC9748256/pdf/main.pdf) |
| BP4_CADD_SUP | 22.7 | BP4 CADD cutoff <br/> follow [ClinGen guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC9748256/pdf/main.pdf) |
| BP4_CADD_MOD | 17.3 | BP4 moderate CADD cutoff <br/> follow [ClinGen guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC9748256/pdf/main.pdf) |
| BP4_CADD_STR | 0.15 | BP4 strong CADD cutoff <br/> follow [ClinGen guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC9748256/pdf/main.pdf) |
| PP3_DANN | 0.999 | PP3 DANN cutoff <br/> follow [varsome](https://varsome.com/about/resources/germline-implementation/#insilicopredictions) |
| BP4_DANN_SUP | 0.974 | BP4 DANN cutoff <br/> follow [varsome](https://varsome.com/about/resources/germline-implementation/#insilicopredictions) |
| BP4_DANN_MOD | 0.915 | BP4 moderate DANN cutoff <br/> follow [varsome](https://varsome.com/about/resources/germline-implementation/#insilicopredictions) |
| BP4_DANN_STR | 0.478 | BP4 strong DANN cutoff <br/> follow [varsome](https://varsome.com/about/resources/germline-implementation/#insilicopredictions) |
| P_SPLICEAI | 0.2 | SpliceAI prediction score threshold for pathogenic |
| B_SPLICEAI | 0.1 | SpliceAI prediction score threshold for benign |

### Custom Mode
Enter a specific numeric value to override defaults.

For example, to override allele frequency settings:

```json
"acmg_params": {
    "AD_AF": 0.00001,
    "AR_AF": 0.0005
}
```

> [!Important] 
> Ensure the file maintains valid JSON syntax when switching between `null` and specific values.


## Output description
The script will automatically create an `ACMG_output` subdirectory under the sample folder.

### Result files
- `{sample}.vep.ACMG.tsv`: VEP annotated TSV with pathogenic classfication and ACMG rules.
- `{sample}.vep.mane_plus_clinical.ACMG.tsv`: Only variants located in 65 MANE Plus Clinical transcripts were included, pathogenic classfication and ACMG rules were added to the annotated TSV.

### Key Output Columns
| Column | Description |
| :--- | :--- |
| Pathogenicity_class | Final classification (e.g., Pathogenic, Likely_pathogenic, Uncertain_significance, Likely_benign, Benign). |
| ACMG_rules | A list of criteria met by the variant (e.g., PVS1,PM2,PP3). |


## Databases for pathogenicity evaluation
Detailed versions and descriptions for all databases can be found in the VEP annotation result documentations.
Key sources used for ACMG scoring include:
- ClinVar, version 20251109
- CADD, using dbNSFP version 4.9a
- DANN, using dbNSFP version 4.9a
- HGMD
- LOEUF, based on gnomAD v4, GRCh38
- DVD, version 9.2
- gnomAD genomes coverage, version 3.0.1
- gnomAD genomes, version 4.1
- gnomAD exomes, version 4.1
- RepeatMasker, download from UCSC Table Browser
- SpliceAI SNV, version 1.3
- SpliceAI indel, version 1.3
- MitoMap, version 20260418

