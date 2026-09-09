/*==============================================================================
    Project:    AI Jobs — Firm-Year Panel
    Author:     Renhao Jiang
    Date:       2026-03-31
    Purpose:    Construct a gvkey-year AI jobs panel from Revelio job counts and
                Compustat employment.

    Inputs:     1. rev_allyear_072026.csv
                   - Revelio rcid-year job counts and AI category counts
                2. Compustat20260404.dta
                   - Compustat firm-year employment data
                3. rcid_gvkey_match_final.dta
                   - rcid-gvkey mapping file

    Output:     AI_panel_2010-2024.dta
                - gvkey-year panel of U.S. AI-related job counts, AI category
                  counts, Wave I / Wave II counts, Compustat
                  employment, and AI-related job shares.
==============================================================================*/

clear all
set more off

*===============================================================================
* 0. Set paths
*===============================================================================

* Set data to the folder containing BOTH rev_allyear_072026.csv (Python output)
* and rcid_gvkey_match_final.dta (matching output); copy them there if needed.
* AI_panel_2010-2024.dta is saved in the same folder.
* Set Compustat to the folder containing Compustat20260404.dta.
global data       "..."
global Compustat  "..."


*===============================================================================
* 1. Prepare Compustat employment data
*===============================================================================
* Compustat reports employment in thousands. Convert to number of employees.

use "$Compustat/Compustat20260404.dta", clear

keep gvkey fyear emp
rename fyear year
rename emp employment_count

replace employment_count = employment_count * 1000
format employment_count %20.0g

sort gvkey year

tempfile compustat
save `compustat', replace


*===============================================================================
* 2. Load Revelio AI job data and merge to gvkey
*===============================================================================
* Keep matched rcid-gvkey observations and restrict to the 2010--2024 sample period.

import delimited "$data/rev_allyear_072026.csv", clear

merge 1:1 rcid year using "$data/rcid_gvkey_match_final.dta", ///
    keep(match) nogen

keep if inrange(year, 2010, 2024)

merge m:1 gvkey year using `compustat', ///
    keep(match) nogen


*===============================================================================
* 3. Collapse from rcid-year to gvkey-year
*===============================================================================
* Sum job counts and user counts across rcids within each gvkey-year.
* Take the mean of Compustat employment because it is gvkey-year level.

local job_counts ///
    ai_jobs_us total_jobs_us ///
    ai_only_us ml_only_us cv_only_us nlp_only_us ///
    genai_only_us agent_only_us ///
    earlyai_us lateai_us ai_other_us ///
    only_early_us only_late_us both_earlylate_us

collapse (sum) `job_counts' ///
         (mean) employment_count, ///
         by(gvkey year)

sort gvkey year


*===============================================================================
* 4. Construct AI-related job shares
*===============================================================================
* Shares are multiplied by 100, so they are measured as percent of U.S. jobs.

g share_ai_all_us = 100 * ai_jobs_us / total_jobs_us
g share_ai_other_us = 100 * ai_other_us / total_jobs_us

g share_earlyai_us = 100 * earlyai_us / total_jobs_us
g share_lateai_us = 100 * lateai_us / total_jobs_us
g share_only_early_us      = 100 * only_early_us / total_jobs_us
g share_only_late_us       = 100 * only_late_us / total_jobs_us
g share_both_earlylate_us  = 100 * both_earlylate_us / total_jobs_us

foreach v in ml cv ai genai nlp agent {
    g share_`v'_only_us = 100 * `v'_only_us / total_jobs_us
}


*===============================================================================
* 5. Add variable labels
*===============================================================================

label variable ai_jobs_us             "AI-related jobs (U.S.)"
label variable total_jobs_us          "Total jobs (U.S.)"

label variable ai_only_us             "AI-related jobs: general AI category (U.S.)"
label variable ml_only_us             "AI-related jobs: machine learning category (U.S.)"
label variable cv_only_us             "AI-related jobs: computer vision category (U.S.)"
label variable genai_only_us          "AI-related jobs: generative AI category (U.S.)"
label variable nlp_only_us            "AI-related jobs: NLP category (U.S.)"
label variable agent_only_us          "AI-related jobs: agentic AI category (U.S.)"
label variable ai_other_us            "AI-related jobs: other AI category (U.S.)"

label variable earlyai_us             "Wave I AI-related jobs (U.S.)"
label variable lateai_us              "Wave II AI-related jobs (U.S.)"
label variable only_early_us          "Wave I only AI-related jobs (U.S.)"
label variable only_late_us           "Wave II only AI-related jobs (U.S.)"
label variable both_earlylate_us      "Both Wave I and Wave II AI-related jobs (U.S.)"

label variable employment_count       "Compustat employment count"

label variable share_ai_all_us        "AI-related jobs as % of U.S. jobs"
label variable share_ai_other_us      "Other AI category as % of U.S. jobs"

label variable share_ai_only_us       "General AI category as % of U.S. jobs"
label variable share_ml_only_us       "Machine learning category as % of U.S. jobs"
label variable share_cv_only_us       "Computer vision category as % of U.S. jobs"
label variable share_genai_only_us    "Generative AI category as % of U.S. jobs"
label variable share_nlp_only_us      "NLP category as % of U.S. jobs"
label variable share_agent_only_us    "Agentic AI category as % of U.S. jobs"

label variable share_earlyai_us       "Wave I AI-related jobs as % of U.S. jobs"
label variable share_lateai_us        "Wave II AI-related jobs as % of U.S. jobs"
label variable share_only_early_us    "Wave I only AI-related jobs as % of U.S. jobs"
label variable share_only_late_us     "Wave II only AI-related jobs as % of U.S. jobs"
label variable share_both_earlylate_us "Both Wave I and Wave II AI-related jobs as % of U.S. jobs"

compress
save "$data/AI_panel_2010-2024.dta", replace
