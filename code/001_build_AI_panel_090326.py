"""
001_build_AI_panel_090326.py
Author: Renhao Jiang
Workflow:
  1. Read AI_keyword_2026.csv -> keyword, tier, subcategory
  2. For each revelio file (parallel):
     a. Filter intern/part-time jobs (title regex)
     b. Explode job spells to job-years
     c. Match keywords -> AI_job master flag + subcategory flags
     d. Derive early/late three-way ME classification
     e. Aggregate US job-year counts to (rcid, year)
  3. Combine chunks -> firm-year panel of US job counts.

My package version is: pandas 2.3.3; polars 1.35.0b1
"""

import os, gc, glob, re, csv
import pandas as pd
import polars as pl
from multiprocessing import Pool, set_start_method, cpu_count

# ===================== PATHS =====================
# The keyword CSV is in the package's main folder, one level above this script.
# This default works regardless of the directory from which Python is launched.
KW_CSV = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "AI_keyword_2026.csv")
# Set DATA_DIR to the folder containing your Revelio input files.
# Intermediate CSVs and rev_allyear_072026.csv are also written there.
# For a synthetic test, copy synthetic_rev1_mar.dta into a test folder as
# rev1_mar.dta and point DATA_DIR to that folder.
# For the final Stata step, place the output CSV in its configured $data folder.
DATA_DIR = ".../revelio/mar_26"

# Input-file pattern: rev<N>_mar.dta (We have 20 dta files for our revelio sample and please revise this based on your case).
INPUT_RE = re.compile(r"^rev(\d+)_mar\.dta$")

# Output prefix for intermediate chunks (date-tagged)
JOB_CHUNK_PREFIX = os.path.join(DATA_DIR, "rev_byyear_072026_")

# Final firm-year panel
FINAL_JOB_CSV = os.path.join(DATA_DIR, "rev_allyear_072026.csv")

# ===================== LOAD KEYWORDS FROM CSV =====================
ALL_KW = []           # (keyword, tier, subcategory)
SUBCATEGORIES = set()
SUBCAT_MAP = {}

with open(KW_CSV, "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        kw = row["keyword"].strip()
        tier = row["tier"].strip()
        subcat = row["subcategory"].strip()
        ALL_KW.append((kw, tier, subcat))
        SUBCATEGORIES.add(subcat)
        SUBCAT_MAP[kw] = subcat

N_KW = len(ALL_KW)
n_t1 = sum(1 for _, t, _ in ALL_KW if t == "tier1")
n_t2 = sum(1 for _, t, _ in ALL_KW if t == "tier2")
n_t3 = sum(1 for _, t, _ in ALL_KW if t == "tier3")
print(f"Keywords: {n_t1} tier1 + {n_t2} tier2 + {n_t3} tier3 = {N_KW} total")
print(f"Subcategories: {sorted(SUBCATEGORIES)}")

# Build subcategory column names
SUBCAT_COL = {}
for sc in SUBCATEGORIES:
    if sc in ("AI", "GeneralAI"):
        SUBCAT_COL[sc] = "AI_only"
    elif sc == "Other":
        SUBCAT_COL[sc] = "AI_other"
    elif sc == "Agent":
        SUBCAT_COL[sc] = "agent_only"
    elif sc == "GenAI":
        SUBCAT_COL[sc] = "genai_only"
    else:
        SUBCAT_COL[sc] = f"{sc}_only"

SUBCAT_COLS = sorted(set(SUBCAT_COL.values()))
print(f"Subcategory columns: {SUBCAT_COLS}")

# Three-way mutual-exclusive flags derived from subcategory composites
ME_FLAGS = ["earlyAI", "lateAI", "only_early", "only_late", "both_earlylate"]

# ===================== INTERN / PART-TIME REGEX =====================
INTERN_TERMS = (
    r"\b(?:intern(?:ship)?|co[- ]?op|cooperative education|"
    r"summer\s+(?:analyst|associate|intern|clerk|fellow|researcher|student|trainee|job)|"
    r"(?:industrial|student)\s+placement|placement\s+(?:year|student)|"
    r"sandwich\s+(?:year|student|placement)|year\s+in\s+industry|"
    r"post[- ]?doc(?:toral)?(?:\s+(?:fellow|researcher|associate|scholar))?|"
    r"p\.?h\.?d\.?\s+(?:student|candidate)|doctoral\s+(?:student|candidate)|"
    r"graduate\s+student|grad\s+student|student\s+researcher|master'?s\s+student|mba\s+(?:student|candidate)|"
    r"undergraduate(?:\s+student)?|undergrad|bachelor'?s\s+student|college\s+student|"
    r"student\s+(?:at|@)|full[- ]?time\s+student|part[- ]?time\s+student)\b"
)
PT_TERMS = r"\bpart[- ]?time\b|\bpart time\b|\bpart-time\b"


# ===================== WORKER =====================
def init_worker(polars_threads=1):
    try:
        pl.Config.set_tbl_formatting("ASCII_FULL")
    except Exception:
        pass


def process_one(dta_path: str):
    """Process one rev<N>_mar.dta -> US job-year chunk CSV."""
    tag = os.path.splitext(os.path.basename(dta_path))[0]          # e.g. "rev1_mar"
    job_output = f"{JOB_CHUNK_PREFIX}{tag}.csv"

    columns_needed = [
        'title_raw', 'description',
        'startdate', 'enddate', 'rcid', 'country',
    ]
    df = pd.read_stata(dta_path, columns=columns_needed)
    n_raw = len(df)

    df["title_raw"] = df["title_raw"].fillna("").astype(str)
    df["description"] = df["description"].fillna("").astype(str)
    df["title_raw_lower"] = df["title_raw"].str.lower()
    df["description_lower"] = df["description"].str.lower()

    for col in ["title_raw", "description", "title_raw_lower", "description_lower"]:
        df[col] = df[col].str.replace("–", "-", regex=False).str.replace("—", "-", regex=False)

    for col in ["title_raw_lower", "description_lower"]:
        df[col] = df[col].str.replace(r"\s+", " ", regex=True)

    # ================= INTERN / PART-TIME FILTERING =================
    drop_intern = df["title_raw_lower"].str.contains(INTERN_TERMS, regex=True, na=False)
    drop_pt = df["title_raw_lower"].str.contains(PT_TERMS, regex=True, na=False)
    exclude = drop_intern | drop_pt
    n_dropped = exclude.sum()

    print(f"[{tag}] Raw positions: {n_raw:,} | intern {int(drop_intern.sum()):,} "
          f"part-time {int(drop_pt.sum()):,} | dropped {int(n_dropped):,} ({n_dropped/n_raw*100:.1f}%)")

    df = df.loc[~exclude].copy()

    # ================= DATES & EXPLODE =================
    df["startdate"] = pd.to_datetime(df["startdate"], errors="coerce")
    df["enddate"] = pd.to_datetime(df["enddate"], errors="coerce")
    df["start_year"] = df["startdate"].dt.year.astype("Int64")
    df["end_year"] = df["enddate"].dt.year.astype("Int64")
    df['start_year'] = pd.to_numeric(df['start_year'], errors='coerce')
    df['end_year'] = pd.to_numeric(df['end_year'], errors='coerce')
    # missing start_year (or rcid) -> DROP; then if missing end_year -> FILL with 2026 (assumption: ongoing jobs)
    df = df.dropna(subset=['start_year', 'rcid'])
    df['end_year'] = df['end_year'].fillna(2026)
    df = df[df['end_year'] >= df['start_year']]
    df['start_year'] = df['start_year'].astype(int)
    df['end_year'] = df['end_year'].astype(int)

    df["country"] = df["country"].fillna("").astype(str)

    pl_df = pl.from_pandas(df)
    pl_df = pl_df.with_columns(
        pl.int_ranges(pl.col("start_year"), pl.col("end_year") + 1).alias("year")
    ).explode("year")

    # ================= INITIALIZE FLAG COLUMNS =================
    init_cols = [
        pl.lit(0, dtype=pl.Int8).alias("AI_job"),
        (pl.col("country") == "United States").cast(pl.Int8).alias("US_job"),
    ]
    for col_name in SUBCAT_COLS:
        init_cols.append(pl.lit(0, dtype=pl.Int8).alias(col_name))
    pl_df = pl_df.with_columns(init_cols)

    # ================= KEYWORD MATCHING =================
    # Master AI flag + subcategory flag set per keyword match.
    for kw, tier, subcat in ALL_KW:
        if tier == "tier1":
            pat = rf"\b{re.escape(kw)}\b"
            mask = (
                pl_df["title_raw"].str.contains(pat, literal=False).fill_null(False)
                | pl_df["description"].str.contains(pat, literal=False).fill_null(False)
            )
        elif tier == "tier2":
            pat = rf"(?i)\b{re.escape(kw)}\b"
            mask = (
                pl_df["title_raw"].str.contains(pat, literal=False).fill_null(False)
                | pl_df["description"].str.contains(pat, literal=False).fill_null(False)
            )
        else:  # tier3
            mask = (
                pl_df["title_raw_lower"].str.contains(kw.lower(), literal=True).fill_null(False)
                | pl_df["description_lower"].str.contains(kw.lower(), literal=True).fill_null(False)
            )

        subcat_col = SUBCAT_COL[subcat]
        pl_df = pl_df.with_columns([
            pl.when(mask).then(1).otherwise(pl.col(subcat_col)).alias(subcat_col),
            pl.when(mask).then(1).otherwise(pl.col("AI_job")).alias("AI_job"),
        ])

    # ================= THREE-WAY ME CLASSIFICATION (early/late) =================
    #   earlyAI = max(NLP, ML, CV) ; lateAI = max(GenAI, Agent)
    pl_df = pl_df.with_columns([
        pl.max_horizontal("NLP_only", "ML_only", "CV_only").cast(pl.Int8).alias("earlyAI"),
        pl.max_horizontal("genai_only", "agent_only").cast(pl.Int8).alias("lateAI"),
    ])
    #   only_early: earlyAI=1,lateAI=0 ; only_late: earlyAI=0,lateAI=1 ; both: earlyAI=1,lateAI=1
    pl_df = pl_df.with_columns([
        ((pl.col("AI_job") == 1) & (pl.col("earlyAI") == 1) & (pl.col("lateAI") == 0)).cast(pl.Int8).alias("only_early"),
        ((pl.col("AI_job") == 1) & (pl.col("earlyAI") == 0) & (pl.col("lateAI") == 1)).cast(pl.Int8).alias("only_late"),
        ((pl.col("AI_job") == 1) & (pl.col("earlyAI") == 1) & (pl.col("lateAI") == 1)).cast(pl.Int8).alias("both_earlylate"),
    ])

    # ================= RESTRICT TO PANEL YEARS 2010-2025 =================
    pl_df = pl_df.filter((pl.col("year") >= 2010) & (pl.col("year") <= 2025))

    # ================= US JOB-YEAR CROSS-FLAGS =================
    #   total_jobs_US == US_job (one job-year per row); every count is US-only.
    us_exprs = [
        (pl.col("AI_job") * pl.col("US_job")).alias("AI_jobs_US"),
        pl.col("US_job").alias("total_jobs_US"),
    ]
    for sc_col in SUBCAT_COLS:
        us_exprs.append((pl.col(sc_col) * pl.col("US_job")).alias(f"{sc_col}_US"))
    for flag in ME_FLAGS:
        us_exprs.append((pl.col(flag) * pl.col("US_job")).alias(f"{flag}_US"))
    pl_df = pl_df.with_columns(us_exprs)

    SUM_COLS = (["AI_jobs_US", "total_jobs_US"]
                + [f"{sc}_US" for sc in SUBCAT_COLS]
                + [f"{flag}_US" for flag in ME_FLAGS])

    # ================= JOB-LEVEL AGGREGATION (US only) =================
    agg_df = pl_df.group_by(["rcid", "year"]).agg([pl.sum(c).alias(c) for c in SUM_COLS])
    agg_df.write_csv(job_output)

    print(f"[{tag}] done -> {os.path.basename(job_output)} ({agg_df.height:,} firm-years)")

    del df, pl_df, agg_df
    gc.collect()
    return job_output


# ===================== MAIN =====================
def discover_files():
    """All rev<N>_mar.dta in DATA_DIR, sorted by N (any c."""
    found = []
    for p in glob.glob(os.path.join(DATA_DIR, "rev*_mar.dta")):
        m = INPUT_RE.match(os.path.basename(p))
        if m:
            found.append((int(m.group(1)), p))
    found.sort()
    return [p for _, p in found]


def main():
    files = discover_files()
    if not files:
        raise FileNotFoundError(f"No rev<N>_mar.dta files found in {DATA_DIR}")
    N_PROCS = min(8, cpu_count(), len(files))

    total_threads = os.cpu_count() or 8
    per_proc = max(1, total_threads // N_PROCS)
    os.environ["POLARS_MAX_THREADS"] = str(per_proc)

    try:
        set_start_method("spawn")
    except RuntimeError:
        pass

    print(f"\nProcessing {len(files)} file(s) with {N_PROCS} worker(s):")
    for p in files:
        print(f"   {os.path.basename(p)}")
    print()

    with Pool(processes=N_PROCS, initializer=init_worker, initargs=(per_proc,)) as p:
        for _ in p.imap_unordered(process_one, files, chunksize=1):
            pass

    # ===================== COMBINE US JOB COUNTS =====================
    print("\n=== Combining US job-count chunks ===")
    job_files = sorted(glob.glob(f"{JOB_CHUNK_PREFIX}*.csv"))
    lf = pl.concat([pl.scan_csv(f) for f in job_files])

    SUM_COLS = (["AI_jobs_US", "total_jobs_US"]
                + [f"{sc}_US" for sc in SUBCAT_COLS]
                + [f"{flag}_US" for flag in ME_FLAGS])
    final_job = (
        lf.group_by(["rcid", "year"])
        .agg([pl.sum(c).alias(c) for c in SUM_COLS])
        .collect(streaming=True)
        .with_columns([
            pl.col("rcid").cast(pl.Int64, strict=False),
            pl.col("year").cast(pl.Int64, strict=False),
        ])
    )

    # ===================== RENAME TO REQUESTED COLUMNS + ORDER =====================
    RENAME = {
        "AI_jobs_US": "ai_jobs_us",
        "total_jobs_US": "total_jobs_us",
        "AI_only_US": "ai_only_us",
        "ML_only_US": "ml_only_us",
        "CV_only_US": "cv_only_us",
        "genai_only_US": "genai_only_us",
        "NLP_only_US": "nlp_only_us",
        "agent_only_US": "agent_only_us",
        "AI_other_US": "ai_other_us",
        "earlyAI_US": "earlyai_us",
        "lateAI_US": "lateai_us",
        "only_early_US": "only_early_us",
        "only_late_US": "only_late_us",
        "both_earlylate_US": "both_earlylate_us",
    }
    FINAL_ORDER = [
        "rcid", "year",
        "ai_jobs_us", "total_jobs_us",
        "ai_only_us", "ml_only_us", "cv_only_us", "genai_only_us", "nlp_only_us", "agent_only_us",
        "earlyai_us", "lateai_us", "ai_other_us",
        "only_early_us", "only_late_us", "both_earlylate_us",
    ]
    final_job = final_job.rename(RENAME).select(FINAL_ORDER).sort(["rcid", "year"])

    # ===================== WRITE FIRM-YEAR PANEL =====================
    final_job.write_csv(FINAL_JOB_CSV)
    print(f"\nFirm-year panel saved: {FINAL_JOB_CSV}  ({final_job.height:,} firm-years, "
          f"{len(final_job.columns)} cols)")
    print(f"Columns: {final_job.columns}")

    # Clean up intermediate chunk files
    for f in sorted(glob.glob(f"{JOB_CHUNK_PREFIX}*.csv")):
        try:
            os.remove(f)
        except OSError:
            pass
    print("Cleaned up intermediate chunk files.")


if __name__ == "__main__":
    main()
