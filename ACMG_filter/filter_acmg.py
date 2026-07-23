#!/usr/bin/env python3
"""
filter_acmg.py — 篩選 ACMG-annotated TSV(v2:分類模式 + 流程模式)

兩種模式(依是否用到分類旗標自動判定;二擇一):
  【分類模式】只要用到 --plp / --clinVar-plp / --dvd-plp 任一個 →
      = 這幾個的「OR 聯集」,且【忽略】其他所有篩選條件(pass-only/min-dp/... 都不生效)。
      給一個 = 該類;給多個 = 聯集(union)。
  【流程模式】未用任何分類旗標時 → 依固定順序做 AND 篩選:
      pass-only → min-dp → acmg-ex → ex-blb → min-vaf → max-af →
      gene-list → exonic/noncoding → consequence(+mode) → acmg-ex-b-rule-only → vushigh

兩種模式在輸出前都會【自動】為每個位點計算 ACMG_point 欄(不需再手動 --add-score)。

用法:
    python filter_acmg.py -i <input.tsv> -o <output.tsv> [options]
    python filter_acmg.py -h                              # 看所有 option
    python filter_acmg.py --list-columns -i <input.tsv>   # 列出全部欄位

需先啟用 acmg_rule 環境(polars):
    ml old-module; ml biology Anaconda/Anaconda3
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate /work/d03455002/VEP-ACMG/conda/acmg_rule
"""
import argparse
import sys
import os
import re
# 注:polars 延後到 main() 內才 import,讓 `-h` 在未啟用 acmg_rule 環境時也能看說明。

# ============================================================
# ACMG 點數系統(可調)
#   基礎等級:PVS/BA=very strong, PS/BS=strong, PM/BM=moderate, PP/BP=supporting
#   P 開頭為正、B 開頭為負;token 若帶 _修飾 則以修飾字覆蓋等級
#   例:PVS1=+8, PVS1_STRONG=+4, PM2=+2, BP6_STRONG=-4, BA1=-8
# ============================================================
LEVEL_POINTS = {"very_strong": 8, "strong": 4, "moderate": 2, "supporting": 1}
MODIFIER_LEVEL = {
    "VERYSTRONG": "very_strong", "STRONG": "strong",
    "MODERATE": "moderate", "SUPPORTING": "supporting",
}
VUSHIGH_CUTOFF = 3  # 總分 >= 此值 = VUS-high

# Consequence 第 1 類:all exonic(含 synonymous)+ splicing donor/acceptor(可調)
CODING_SPLICE_CONSEQUENCES = [
    "missense_variant", "synonymous_variant", "stop_gained", "stop_lost",
    "start_lost", "frameshift_variant", "inframe_insertion", "inframe_deletion",
    "protein_altering_variant", "incomplete_terminal_codon_variant",
    "start_retained_variant", "stop_retained_variant", "coding_sequence_variant",
    "splice_acceptor_variant", "splice_donor_variant",
]


# ============================================================
# ACMG 分數計算
# ============================================================
def _base_level(base: str) -> str:
    m = re.match(r"[A-Z]+", base)
    pref = m.group() if m else ""
    if pref in ("PVS", "BA"):
        return "very_strong"
    if pref in ("PS", "BS"):
        return "strong"
    if pref in ("PM", "BM"):
        return "moderate"
    return "supporting"  # PP / BP 及其他


def token_points(tok: str) -> int:
    tok = tok.strip()
    if not tok:
        return 0
    sign = 1 if tok[0] == "P" else (-1 if tok[0] == "B" else 0)
    if sign == 0:
        return 0
    if "_" in tok:
        base, mod = tok.split("_", 1)
        level = MODIFIER_LEVEL.get(mod.upper().replace("_", ""))
        if level is None:
            level = _base_level(base)
    else:
        level = _base_level(tok)
    return sign * LEVEL_POINTS.get(level, 0)


def score_rules(s) -> int:
    if s is None or s == "":
        return 0
    return sum(token_points(t) for t in s.split(","))


# ============================================================
def parse_csv_list(s):
    return [x.strip() for x in s.split(",") if x.strip()]


def token_regex(rules):
    return rf"(^|,)({'|'.join(re.escape(r) for r in rules)})(,|$)"


# ============================================================
# argparse
# ============================================================
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="filter_acmg.py",
        description=("Filter ACMG-annotated TSV。\n"
                     "分類模式(--plp/--clinVar-plp/--dvd-plp,獨立 OR,忽略其他)\n"
                     "與流程模式(其餘為 AND,固定順序)二擇一;輸出一律含 ACMG_point。"),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    p.add_argument("-i", "--input",  required=True, help="輸入的 *.vep.ACMG.tsv")
    p.add_argument("-o", "--output", help="輸出 TSV(用 --list-columns 時可省略)")
    p.add_argument("--list-columns", action="store_true", help="只列出全部欄位後結束")
    p.add_argument("-v", "--verbose", action="store_true", help="顯示每步篩選後剩餘列數")

    # -------- 分類模式(獨立 OR;用到任一個即進入分類模式,忽略其他篩選) --------
    g1 = p.add_argument_group(
        "分類模式(獨立;用到任一個即進入分類模式 = 這些旗標的 OR 聯集,忽略其他所有篩選)")
    g1.add_argument("--plp", action="store_true",
                    help="ACMG Pathogenicity_class = Pathogenic 或 Likely_pathogenic")
    g1.add_argument("--clinVar-plp", "--clinvar-plp", dest="clinvar_plp",
                    action="store_true",
                    help=("只留 ClinVar_CLNSIG 為 Pathogenic/Likely_pathogenic\n"
                          "(--ex-blb 的相對版:留致病而非去良性)"))
    g1.add_argument("--dvd-plp", action="store_true",
                    help="DVD_SNV_Variant_Classification = Pathogenic 或 Likely_pathogenic")

    # -------- 流程模式(AND;固定順序) --------
    g2 = p.add_argument_group("流程模式(AND;固定順序,未用分類旗標時生效)")
    g2.add_argument("--pass-only", action="store_true", help="只留 FILTER == PASS")
    g2.add_argument("--min-dp", type=float, metavar="INT",
                    help="保留 DP >= 此值(空值濾掉)")
    g2.add_argument("--acmg-ex", metavar="RULE[,RULE...]",
                    help="刪除 ACMG_rules 含指定規則者(精確 token)。例:--acmg-ex BA1")
    g2.add_argument("--ex-blb", action="store_true",
                    help=("依 ClinVar_CLNSIG 去掉純良性:含 Benign/Likely_benign\n"
                          "且不含 Conflicting/VUS/Pathogenic 才刪(混合/衝突/含致病保留;空值保留)"))
    g2.add_argument("--min-vaf", type=float, metavar="FLOAT",
                    help="保留 VAF >= 此值(空值濾掉)")
    g2.add_argument("--max-af", type=float, metavar="FLOAT",
                    help=("gnomAD_genome_AF 與 gnomAD_exome_AF 皆 <= 此值才留;\n"
                          "空值視為罕見保留。常用 0.01 或 0.05"))
    g2.add_argument("--gene-list", metavar="PATH",
                    help="基因清單檔(一行一個 symbol),只留 SYMBOL 在清單中的位點")
    g2.add_argument("--exonic", action="store_true",
                    help="只留 exonic(含 synonymous)+ splicing donor/acceptor(第 1 類)")
    g2.add_argument("--noncoding", action="store_true",
                    help="只留非第 1 類(non-coding)")
    g2.add_argument("--consequence", metavar="TERM[,TERM...]",
                    help="自訂 Consequence 關鍵字(逗號分隔;任一命中)。搭配 --mode")
    g2.add_argument("--mode", choices=["include", "exclude"], default="include",
                    help="搭配 --consequence:include=只留(預設);exclude=刪去")
    g2.add_argument("--acmg-ex-b-rule-only", action="store_true",
                    help="刪除只有 Benign 證據(B)、無 Pathogenic 證據(P)者")
    g2.add_argument("--vushigh", action="store_true",
                    help=f"只留 ACMG_point 總分 >= {VUSHIGH_CUTOFF}(VUS-high)")

    # -------- 其他 --------
    p.add_argument("--add-score", action="store_true",
                   help="(相容保留;現已一律自動計算 ACMG_point,本旗標可省略)")
    return p


# ============================================================
def main() -> None:
    args = build_parser().parse_args()      # `-h` 會在此印說明並結束,不需 polars

    import polars as pl                      # 延後載入:真正要處理資料時才需要 acmg_rule 環境

    if args.list_columns:
        cols = pl.read_csv(args.input, separator="\t", n_rows=0,
                           infer_schema_length=0).columns
        for i, c in enumerate(cols, 1):
            print(f"{i}\t{c}")
        print(f"\n共 {len(cols)} 欄")
        return

    if not args.output:
        sys.exit("[Error] 需要 -o/--output(除非用 --list-columns)")
    if args.exonic and args.noncoding:
        sys.exit("[Error] --exonic 與 --noncoding 不可同時使用")

    lf = pl.scan_csv(args.input, separator="\t",
                     infer_schema_length=0, null_values=["."])

    def report(tag):
        if args.verbose:
            print(f"[step] {tag:<26} 剩餘 {lf.select(pl.len()).collect().item()} 列")

    report("(start)")

    class_used = args.plp or args.clinvar_plp or args.dvd_plp

    if class_used:
        # ---------- 分類模式:三旗標 OR 聯集,忽略其他篩選 ----------
        ignored = [n for n, on in [
            ("--pass-only", args.pass_only),
            ("--min-dp", args.min_dp is not None),
            ("--acmg-ex", bool(args.acmg_ex)),
            ("--ex-blb", args.ex_blb),
            ("--min-vaf", args.min_vaf is not None),
            ("--max-af", args.max_af is not None),
            ("--gene-list", bool(args.gene_list)),
            ("--exonic", args.exonic),
            ("--noncoding", args.noncoding),
            ("--consequence", bool(args.consequence)),
            ("--acmg-ex-b-rule-only", args.acmg_ex_b_rule_only),
            ("--vushigh", args.vushigh),
        ] if on]
        if ignored:
            print(f"[Warn] 分類模式:以下流程選項被忽略:{', '.join(ignored)}")

        preds = []
        if args.plp:
            preds.append(pl.col("Pathogenicity_class").is_in(
                ["Pathogenic", "Likely_pathogenic"]))
        if args.clinvar_plp:
            preds.append(pl.col("ClinVar_CLNSIG").fill_null("")
                         .str.contains(r"(?i)pathogenic\b"))
        if args.dvd_plp:
            preds.append(pl.col("DVD_SNV_Variant_Classification").fill_null("")
                         .is_in(["Pathogenic", "Likely_pathogenic"]))
        combined = preds[0]
        for pr in preds[1:]:
            combined = combined | pr
        lf = lf.filter(combined)
        sel = ",".join(n for n, on in [
            ("plp", args.plp), ("clinVar-plp", args.clinvar_plp),
            ("dvd-plp", args.dvd_plp)] if on)
        report(f"class-OR({sel})")

    else:
        # ---------- 流程模式:固定順序 AND ----------
        # 1) --pass-only
        if args.pass_only:
            lf = lf.filter(pl.col("FILTER") == "PASS"); report("pass-only")

        # 2) --min-dp
        if args.min_dp is not None:
            dp = pl.col("DP").cast(pl.Float64, strict=False)
            lf = lf.filter(dp.is_not_null() & (dp >= args.min_dp))
            report(f"min-dp>={args.min_dp}")

        # 3) --acmg-ex
        if args.acmg_ex:
            rules = parse_csv_list(args.acmg_ex)
            lf = lf.filter(~pl.col("ACMG_rules").fill_null("")
                           .str.contains(token_regex(rules)))
            report(f"acmg-ex({','.join(rules)})")

        # 4) --ex-blb
        if args.ex_blb:
            s = pl.col("ClinVar_CLNSIG").fill_null("")
            has_benign = s.str.contains(r"(?i)benign\b")
            has_conf = s.str.contains(r"(?i)conflicting")
            has_vus = s.str.contains(r"(?i)uncertain_significance")
            has_path = s.str.contains(r"(?i)pathogenic\b")
            lf = lf.filter(~(has_benign & ~has_conf & ~has_vus & ~has_path))
            report("ex-blb")

        # 5) --min-vaf
        if args.min_vaf is not None:
            vaf = pl.col("VAF").cast(pl.Float64, strict=False)
            lf = lf.filter(vaf.is_not_null() & (vaf >= args.min_vaf))
            report(f"min-vaf>={args.min_vaf}")

        # 6) --max-af
        if args.max_af is not None:
            g = pl.col("gnomAD_genome_AF").cast(pl.Float64, strict=False)
            e = pl.col("gnomAD_exome_AF").cast(pl.Float64, strict=False)
            lf = lf.filter((g.is_null() | (g <= args.max_af)) &
                           (e.is_null() | (e <= args.max_af)))
            report(f"max-af<={args.max_af}")

        # 7) --gene-list
        if args.gene_list:
            if not os.path.isfile(args.gene_list):
                sys.exit(f"[Error] 找不到 gene list: {args.gene_list}")
            with open(args.gene_list) as fh:
                genes = [ln.strip() for ln in fh
                         if ln.strip() and not ln.startswith("#")]
            if not genes:
                sys.exit(f"[Error] gene list 是空的: {args.gene_list}")
            lf = lf.filter(pl.col("SYMBOL").is_in(genes))
            report(f"gene-list(n={len(genes)})")

        # 8) --exonic / --noncoding
        if args.exonic or args.noncoding:
            coding_re = "|".join(re.escape(t) for t in CODING_SPLICE_CONSEQUENCES)
            is_coding = pl.col("Consequence").fill_null("").str.contains(coding_re)
            lf = lf.filter(is_coding if args.exonic else ~is_coding)
            report("exonic" if args.exonic else "noncoding")

        # 9) --consequence + --mode
        if args.consequence:
            term_re = "|".join(re.escape(t) for t in parse_csv_list(args.consequence))
            cond = pl.col("Consequence").fill_null("").str.contains(term_re)
            if args.mode == "exclude":
                cond = ~cond
            lf = lf.filter(cond); report("consequence")

        # 10) --acmg-ex-b-rule-only
        if args.acmg_ex_b_rule_only:
            r = pl.col("ACMG_rules").fill_null("")
            lf = lf.filter(~(r.str.contains(r"(^|,)B") & ~r.str.contains(r"(^|,)P")))
            report("acmg-ex-b-rule-only")

    # ---------- 一律自動計算 ACMG_point ----------
    lf = lf.with_columns(
        pl.col("ACMG_rules").map_elements(score_rules, return_dtype=pl.Int64)
        .alias("ACMG_point")
    )

    # ---------- 11/12) --vushigh(只在流程模式生效) ----------
    if args.vushigh and not class_used:
        lf = lf.filter(pl.col("ACMG_point") >= VUSHIGH_CUTOFF)
        report(f"vushigh(>={VUSHIGH_CUTOFF})")

    out = lf.collect()
    out.write_csv(args.output, separator="\t", null_value=".")
    mode = "分類(OR)" if class_used else "流程(AND)"
    print(f"[Info] [{mode}模式] 篩選後 {out.height} 列(已含 ACMG_point),已寫出:{args.output}")


if __name__ == "__main__":
    main()
