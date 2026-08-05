# Germline Small-Variant Annotation and Pathogenicity Classification on NCHC

*A VEP-based annotation and point-based in-house ACMG classification workflow for germline small variants — GRCh38.*

*Workflow developed by 李婕瑜 (Chieh-Yu Lee) · 袁自航 (Tzu-Hang Yuan) · Dr. 陳俞安 (Dr. Yu-An Chen) and Taiwan AI Labs GDK teams. Advisors: Dr. 陳沛隆 (Dr. Pei-Lung Chen) · Dr. 許書睿 (Dr. Jacob Shu-Jui Hsu) · Dr. 陳倩瑜 (Dr. Chien-Yu Chen). Computation on NCHC · Draft 2026.*

## 1. Summary

This workflow provides standardized annotation and automated pathogenicity classification for germline small variants on the National Center for High-performance Computing (NCHC) environment. It accepts a **GRCh38** germline small-variant VCF produced by either GATK or DRAGEN, performs Ensembl VEP annotation on MANE transcripts, and applies an automated ACMG/AMP classification using a **point-based** scheme adapted from the ACMG/AMP/CAP/ClinGen Sequence Variant Interpretation (SVC) v4 draft. It succeeds the previous, rule-based GenDiseak (GDK) platform, and is designed to be team-accessible, reproducible, and maintainable.

Benchmarked against ClinVar (review status ≥ 2 stars, N = 629,412), the workflow reproduces expert classifications with high concordance — **99.6%** for benign/likely-benign and **97.5%** for pathogenic/likely-pathogenic variants — and, unlike the rule-based predecessor, resolves roughly a quarter of ClinVar variants of uncertain significance (VUS) toward a definitive class where the evidence supports it.

## 2. Background & Motivation

### 2.1 Annotation drives classification

Variant interpretation under the ACMG/AMP framework depends heavily on annotation. Different annotation tools can assign different HGVS descriptions and coding-impact consequences to the same variant; even on the same transcripts, based on our previous study, different annotation tools reach a concordance of only about 58.5% for HGVSc and 85.6% for coding impact, which in turn affects downstream ACMG classification. Standardized transcript sets (MANE) and a single, well-maintained annotation engine are therefore prerequisites for reliable, reproducible classification.

### 2.2 Why a new workflow

The legacy GDK platform (rule-based combining) will no longer be actively maintained. To keep analysis running and shareable across the team, the pipeline was rebuilt on NCHC and modernized:

- **GRCh38 + Ensembl VEP** — actively maintained, a rich plugin ecosystem, and alignment with current databases.
- **MANE Select + MANE Plus Clinical** transcript annotation for standardized, clinically relevant reporting.
- **Point-based ACMG classification** adapted from the SVC v4 draft — reducing conflicting evidence combinations, enabling VUS sub-classification (e.g., VUS-High) for triage, and adding prediction scores absent from the previous ANNOVAR/GDK flow.

## 3. Annotation Pipeline

Pipeline overview: FASTQ (sequencing) → GATK / DRAGEN variant calling (GRCh38) → small-variant VCF (SNV / indel / MNV) → VEP annotation (MANE Select + Plus Clinical) → in-house ACMG point-based class → annotated TSV → filter · review.

<img width="1463" height="915" alt="image" src="https://github.com/user-attachments/assets/12807459-7b64-4e02-8659-1913612368ce" />

### 3.1 Input and VCF preprocessing

The workflow accepts a germline small-variant VCF (or `.vcf.gz`) generated on GRCh38 by GATK or DRAGEN; the upstream calling process is unchanged. Preprocessing standardizes the input in four steps:

1. Retain only chromosomes 1–22, X, Y, and M (MT).
2. Normalize (split multiallelic sites, left-align) and remove duplicate sites.
3. Keep only SNV / indel / MNV; exclude non-standard ALT alleles and structural variants.
4. Split by chromosome and extract the 65 MANE Plus Clinical transcript regions (with a 5,000 bp buffer) for dedicated handling.

### 3.2 Transcript model — MANE

Annotation uses the Matched Annotation from NCBI and EMBL-EBI (MANE) transcript set — a genome-wide set of representative transcripts agreed between RefSeq and Ensembl/GENCODE. This workflow uses **MANE v1.4** on GRCh38, applying both MANE Select and MANE Plus Clinical; 65 genes carry both a MANE Select and a MANE Plus Clinical transcript. Transcript selection priority differs by gene set so that clinically relevant transcripts are preferred where they exist.

**Table 1. Transcript selection order.**

| Variant set | Selection priority |
| --- | --- |
| All variants (general) | mane_select, mane_plus_clinical, rank, canonical, appris, biotype, length |
| Genes with both MANE Select + Plus Clinical (65) | mane_plus_clinical, mane_select, rank, canonical, appris, biotype, length |

### 3.3 Annotation — Ensembl VEP v115

Annotation is performed with Ensembl VEP v115, combining a set of plugins with custom database annotations.

**Table 2. VEP plugins and custom annotation sources.**

| Category | Sources |
| --- | --- |
| Splicing predictions | SpliceAI, dbscSNV, MaxEntScan |
| Pathogenicity predictions | dbNSFP, PrimateAI, LoFtool |
| Gene tolerance to variation | pLI, LOEUF, DosageSensitivity |
| Transcript / NMD | NMD (nonsense-mediated decay escape) |
| Phenotype & citations | satMutMPRA |
| Custom databases | RepeatMasker, DVD (v9.2), MitoMap, ClinVar, gnomAD, TWB, SG10K |

### 3.4 Runtime and storage

As a whole-genome (WGS) reference point, sample HRD441 (original N = 4,864,719 variants; final N = 4,932,880 after normalization) completed in approximately 920 CPU-hours with a peak storage footprint of 4.7 GB (TSV ≈ 3.5 GB).

**Table 3. Stage-level resource profile (WGS, HRD441).**

| Stage | Cores / memory | Wall-clock time |
| --- | --- | --- |
| Preprocess | 2 / 13 GB | 4 m 05 s |
| Annotate (per chromosome) | 14 / 92 GB | 8 s – 5 h 04 m 09 s |
| Merge & generate TSV | 1 / 7 GB | 5 m 16 s |
| Total | ≈ 920 CPU-hours | Peak storage 4.7 GB |

## 4. Pathogenicity Classification

### 4.1 From combining rules to points

The classifier is built on the ACMG/AMP 2015 five-tier system (Pathogenic, Likely Pathogenic, VUS, Likely Benign, Benign) with its evidence codes. Rather than the 2015 discrete combining rules, it aggregates evidence on a point scale adapted from the SVC v4 draft (Tavtigian 2020): Very Strong **+8**, Strong **+4**, Moderate **+2**, Supporting **+1**, with benign criteria taking the corresponding negative points. The aggregated score maps to the five tiers as follows: Benign **≤ −4**, Likely Benign **−3 to −1**, Uncertain Significance (VUS) **0 to 5**, Likely Pathogenic **6 to 9**, and Pathogenic **≥ 10**. Point aggregation reduces conflicting combinations and allows VUS sub-classification. The predecessor GenDiseak (GDK) was rule-based; the NCHC classifier — like Varsome — is point-based.

> **NOTE** The scheme is *adapted from* the SVC v4 draft; it is not a full implementation of the final v4 specification. Exact point thresholds for the final class are defined in the tool configuration (`utils/ACMG/config.json`) and should be cited from there for any formal report. In `config.json` the tunable items are the **CADD, DANN, SpliceAI, LOEUF, and gnomAD allele-frequency (AF) thresholds** and the **file paths** of the reference resources; the point/score scheme itself is adjusted separately in **`ACMG_filter/rescore.py`**.

### 4.2 Implemented evidence criteria

The classifier evaluates the following criteria automatically from annotation and reference data. Criteria that require clinical, family, functional, or case-level information are not automated and remain for manual review.

**Table 4. Automated ACMG criteria, implemented strength, and evidence used.**

| Criterion | Evidence used | Logic (summary) |
| ------------------------ | ------------------ | ------------------------------------ |
| PVS1 (VeryStrong / Strong) | VEP consequence, LOEUF, NMD, LoF gene list | Null variant (stop-gain, frameshift, splice donor/acceptor) in a gene where LoF is a known mechanism; LOEUF ≤ 0.6; NMD-escape logic modulates strength. |
| PS1 / PM5 | pathogenicDB (VEP-annotated ClinVar) | Same amino-acid change (PS1) or same residue, different change (PM5) as an established pathogenic variant, on the same transcript. |
| PS3 | GoF list (ClinVar + HGMD) | Variant present in a curated gain-of-function set supportive of a damaging functional effect. |
| PM1 | pathogenicDB region | ≥ 4 pathogenic variants within ±25 bp; mitochondrial variants excluded per ClinGen. |
| PM2 / BA1 / BS1 / BS2 | MOI + gnomAD frequency | Frequency thresholds conditioned on mode of inheritance; see Table 6. QC: AN > 2000, coverage > 20, FILTER = PASS. |
| PM4 / BP3 | VEP consequence, RepeatMasker | Protein-length change (in-frame indel / stop-loss) in a non-repeat (PM4) vs repeat (BP3) region. |
| PP3 / BP4 / BP7 | SpliceAI, CADD, DANN | Computational support for (PP3) or against (BP4) impact; BP7 for synonymous variants with no predicted splice effect. See Table 6. |
| PP5 / BP6 (scaled) | ClinVar, DVD, MitoMap | Reputable-source classification; strength scales with ClinVar review status (0–4 stars). |

> **REQUIRES MANUAL REVIEW** PS2 / PM6 (de novo), PS4 (case–control), PM3 (in trans), PP1 / BS4 (segregation), PP2 / BP1 (gene spectrum), PP4 (phenotype), and BP2 / BP5 (allelic / alternate cause) depend on clinical, family, or functional data and are not assigned automatically.

### 4.3 Reference data for interpretation

Reference resources are built and versioned so that each assignment is traceable.

**Table 5. Curated reference data underpinning the automated criteria.**

| Resource | Construction / source |
| ------------------------------ | ------------------------------------------------ |
| LoF gene list (PVS1) | ClinVar 20251109 P/LP, ≥2★, LoF molecular consequence (frameshift, nonsense, splice donor/acceptor); genes with > 2 qualifying variants. |
| pathogenicDB — AA change (PS1/PM5) | VEP-annotated ClinVar P/LP, ≥2★, missense; keyed by transcript, amino-acid change and position. |
| pathogenicDB — region (PM1) | ClinVar P/LP, ≥2★, missense / in-frame indel / start-loss; mitochondrial variants excluded (ClinGen). |
| GoF list (PS3) | Aggregated from ClinVar and HGMD. |
| Mode of inheritance (PM2/BS2) | Aggregated from CGD, ClinGen, and PanelApp. |
| Population frequency | gnomAD (exome & genome); QC AN > 2000, coverage > 20, PASS. |
| BA1 exception list | ClinGen BA1 exception variants excluded from stand-alone benign. |
| Reputable source (PP5/BP6) | ClinVar (CLNSIG, CLNREVSTAT), DeafnessVD (DVD v9.2), MitoMap. |

### 4.4 Selected decision thresholds

**Table 6. Representative thresholds for frequency- and score-based criteria.**

| Criterion | Threshold |
| ------------- | ------------------------------------------------------------------------ |
| PM2 | MOI = AD/XL/YL/blank & AF ≤ 1.44×10<sup>-5</sup>; or MOI = AR & AF ≤ 1×10<sup>-4</sup> or nhomalt ≤ 2 (absent/rare after QC). |
| BA1 / BS1 | gnomAD AF ≥ 0.05 (BA1, unless in ClinGen exception list); AF ≥ 0.01 (BS1). |
| BS2 | Observed in healthy adults at frequency above the MOI-conditioned PM2 threshold. |
| PP3 | SpliceAI DS (AG/AL/DG/DL) ≥ 0.2; or CADD-phred ≥ 25.3 (Supporting) / ≥ 28.1 (Moderate); or DANN rankscore ≥ 0.999 when CADD is null. |
| BP4 | SpliceAI DS_AG/AL/DG/DL ≤ 0.1 (all) **AND** CADD-phred ≤ 22.7 (Supporting) / ≤ 17.3 (Moderate) / ≤ 0.15 (Strong); or, when CADD is null, DANN rankscore ≤ 0.974 (Supporting) / ≤ 0.915 (Moderate) / ≤ 0.478 (Strong) with the same SpliceAI condition. |
| BP7 | Synonymous variant **AND** SpliceAI DS_AG/AL/DG/DL ≤ 0.1 (all); no predicted splice effect. |
| PP5 / BP6 | Strength scaled by ClinVar review status: 0–1★ Supporting → 2★ Moderate/Strong → 3–4★ Strong/Very Strong. |

### 4.5 Rule interaction (avoiding double-counting)

Related criteria are disabled by design so that the same underlying evidence is not scored twice.

**Table 7. Disable logic between criteria.**

| Trigger | Disables | Rationale |
| --- | --- | --- |
| BA1 / PM2 | BS1, BS2 | Frequency evidence not counted twice across benign strong and moderate pathogenic. |
| PVS1 | PP3, PM4, BP4 | LoF / splice and length-change evidence already captured by PVS1. |
| PM1 | BP3; (MT variants) | Region evidence supersedes BP3; PM1 disabled for mitochondrial variants (ClinGen). |
| PM4 | PP3 | Length-change and computational evidence overlap. |
| (MT variants) | BP3, PM1 | Mitochondrial-specific exclusions per ClinGen guidance. |

## 5. Benchmark

The classifier was benchmarked against ClinVar (release 20251109; composition at review status ≥ 2 stars, N = 629,412: B/LB 271,884; P/LP 84,611; VUS 272,472; other 108). Performance was evaluated on the updated configuration and separately for two ClinVar confidence levels (review status ≥ 2★ and ≥ 3★), with the reputable-source criteria **PP5/BP6 either included or excluded**, to show their effect on recall.

**Table 8. NCHC classification performance vs ClinVar, by configuration.**
*Footnote: based on the updated version — LoF gene list and LOEUF ≤ 0.6.*

*Panel A — Benign / Likely-benign (B/LB)*

| Metric | Exclude PP5/BP6 (≥3★) | Exclude PP5/BP6 (≥2★) | Include PP5/BP6 (≥3★) | Include PP5/BP6 (≥2★) |
| --- | --- | --- | --- | --- |
| Precision | 0.8505 | 0.7507 | 0.9040 | 0.8197 |
| Recall | 0.6470 | 0.6637 | 0.9996 | 0.9962 |
| Accuracy | 0.8698 | 0.7555 | 0.9715 | 0.9028 |
| F1 | 0.7349 | 0.7045 | 0.9494 | 0.8993 |

*Panel B — Pathogenic / Likely-pathogenic (P/LP)*

| Metric | Exclude PP5/BP6 (≥3★) | Exclude PP5/BP6 (≥2★) | Include PP5/BP6 (≥3★) | Include PP5/BP6 (≥2★) |
| --- | --- | --- | --- | --- |
| Precision | 0.9646 | 0.9669 | 0.9664 | 0.9657 |
| Recall | 0.9260 | 0.9109 | 0.9991 | 0.9738 |
| Accuracy | 0.9316 | 0.9787 | 0.9795 | 0.9910 |
| F1 | 0.9449 | 0.9381 | 0.9825 | 0.9697 |

> **KEY RESULTS** Including the reputable-source criteria (PP5/BP6) sharply raises recall (B/LB recall 0.65 → ≈1.00; P/LP recall 0.93 → ≈1.00) at little precision cost, giving the best F1 — B/LB 0.949 and P/LP 0.983 at ≥3★. At ≥2★ (more variants, lower average review confidence) F1 is modestly lower (B/LB 0.899, P/LP 0.970). Excluding PP5/BP6 mainly costs B/LB recall, reflecting how many benign calls lean on reputable-source concordance.

The comparison below highlights the behavioural difference between the point-based NCHC classifier, the conservative rule-based GDK, and the more aggressive Varsome. For an equal-footing comparison, Varsome's VUS-toward-B/LB and VUS-toward-P/LP calls are collapsed back to VUS (VUS-BLB/PLP → VUS), and all three tools are scored on the matched ClinVar subset (N = 626,562).

**Table 9. Behaviour comparison against the same ClinVar reference (N = 626,562).**

| Metric | NCHC | GDK | Varsome (VUS-BLB/PLP → VUS) |
| --- | --- | --- | --- |
| ClinVar B/LB reproduced | 99.6% | 86.8% | 99.8% |
| ClinVar P/LP reproduced | 97.5% | 81.7% | 98.0% |
| ClinVar VUS resolved to a definitive class | 23.0% | 0% | 55.9% |

## 6. Using the Workflow

### 6.1 Create a conda environment (first-time setup only)

``` bash
cd utils
bash setup_env.sh
```

### 6.2 Usage

After modifying the configuration file `config.sh`, execute `submit.sh`.

``` bash
bash submit.sh
```

The repository contains the batch submitter, per-chromosome preprocessing, and scripts for annotation; the rule modules (`acmg_rules.py`, `aggregation.py`, `data_loader.py`) for classification; and the shared configuration for both steps. Operational aids — a quick-start guide (commands, input formats, paths, outputs, and common error handling) and a tutorial recording — accompany the repositories, with issues tracked on GitHub and continued support via the GDK group.

## 7. Limitations & Future Work

- **Mitochondrial variants** are not yet fully supported; MT-specific handling is planned.
- **PM2 / BS2 thresholds** are currently global; disease-specific frequency thresholds are a planned refinement.
- **Decision-tree refinement** — several criteria warrant more granular sub-trees; some computational strengths (e.g., CADD-based evidence) could be extended toward higher strengths.
- **Version dependence** — results depend on reference genome, transcript set, and database versions (VEP v115, MANE v1.4, ClinVar 20251109); different transcripts can yield different HGVS and consequence.
- **Automation boundary** — clinical-evidence criteria (PS2, PS4, PM3, PP1, PP4, BS4, and related) require human review and are not automated.
- **PP5 / BP6 (reputable source)** are retained for coverage, though their use is debated because of potential double-counting; VUS is not a diagnosis, and classifications may change as databases update.
- **Scope** — the workflow is for germline small variants (SNV / indel / MNV); complex splicing, CNV, SV, and repeat-expansion loci require dedicated tools. Current use is research analysis and candidate filtering; clinical reporting still follows laboratory quality-management, validation, review, and sign-off procedures.

## 8. Availability & Versions

**Table 10. Key resources and versions used in this workflow.**

| Resource | Version / release |
| --- | --- |
| Reference genome | GRCh38 |
| Ensembl VEP | v115 |
| MANE | v1.4 |
| ClinVar | 20251109 |
| DeafnessVD (DVD) | v9.2 |
| Population frequency | gnomAD, TWB, SG10K |
| Prediction / annotation | SpliceAI, dbscSNV, MaxEntScan, dbNSFP, PrimateAI, LoFtool, pLI, LOEUF, DosageSensitivity, NMD, satMutMPRA, CADD, DANN, RepeatMasker |
| Gene / MOI curation | CGD, ClinGen, PanelApp, GenCC, HGMD, MitoMap |
| Compute | NCHC / NARLabs |

## References

1. Chen Y-A, Yuan T-H, Huang J-H, et al. Toward streamline variant classification: discrepancies in variant nomenclature and syntax for ClinVar pathogenic variants across annotation tools. *Human Genomics* 2025;19:70.
2. Richards S, Aziz N, Bale S, et al. Standards and guidelines for the interpretation of sequence variants: a joint consensus recommendation of the ACMG and AMP. *Genet Med* 2015;17(5):405–424.
3. Tavtigian SV, Greenblatt MS, Harrison SM, et al. Modeling the ACMG/AMP variant classification guidelines as a Bayesian classification framework. *Genet Med* 2018;20:1054–1060; and ACMG/AMP/CAP/ClinGen SVC v4 draft (points-based framework).
4. Morales J, Pujar S, Loveland JE, et al. A joint NCBI and EMBL-EBI transcript set for clinical genomics and research (MANE). *Nature* 2022;604:310–315.
5. McLaren W, Gil L, Hunt SE, et al. The Ensembl Variant Effect Predictor. *Genome Biol* 2016;17:122.
6. Jaganathan K, Kyriazopoulou Panagiotopoulou S, McRae JF, et al. Predicting splicing from primary sequence with deep learning (SpliceAI). *Cell* 2019;176:535–548.
7. Karczewski KJ, Francioli LC, Tiao G, et al. The mutational constraint spectrum quantified from variation in 141,456 humans (gnomAD; pLI, LOEUF). *Nature* 2020;581:434–443.
8. Landrum MJ, Lee JM, Benson M, et al. ClinVar: improving access to variant interpretations and supporting evidence. *Nucleic Acids Res* 2018;46(D1):D1062–D1067.

---

*Exact point thresholds for final classification are defined in `utils/ACMG/config.json`; score/point adjustments are made in `ACMG_filter/rescore.py`. Prepared from the NCHC workflow technical materials.*
