# AI Jobs Panel Construction

This package builds on and extends [Babina et al. (2024)](https://ssrn.com/abstract=3651052), “Artificial Intelligence, Firm Growth, and Product Innovation” (*Journal of Financial Economics*), to measure firms’ internal AI investment using their employment of AI-skilled workers. [Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627), “Canaries in the Gold Mine: Early Productivity Gains from Artificial Intelligence Creating Organization Capital” (NBER Working Paper 35684), updates and extends this measurement approach using the code and AI keyword data provided in this repository.

AI-skilled labor is a key input into firms’ AI development and deployment, complemented by inputs such as data and compute. Our human-capital-based measure therefore captures the relative intensity of firms’ internal AI investments.

The updated measures extend the firm-level AI panels through 2024 and cover seven AI subtechnology categories: general AI, machine learning, natural language processing, computer vision, generative AI, agentic AI, and Other. These measures span successive waves of AI, from early machine learning to recent advances in generative and agentic AI.

This repository includes code to construct the firm-level AI measures, an updated list of AI search terms by subcategory, and synthetic sample data. **The actual firm-level AI panel data and the underlying proprietary data are not included.**

**If you use these search terms or code, please cite both papers:** [Babina et al. (2024)](https://ssrn.com/abstract=3651052) and [Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627).

```bibtex
@article{babina2024artificial,
  title={Artificial Intelligence, Firm Growth, and Product Innovation},
  author={Babina, Tania and Fedyk, Anastassia and He, Alex and Hodson, James},
  journal={Journal of Financial Economics},
  volume={151},
  pages={103745},
  year={2024},
  publisher={Elsevier}
}
```

```bibtex
@techreport{babina2026canaries,
  title={Canaries in the Gold Mine: Early Productivity Gains from Artificial Intelligence Creating Organization Capital},
  author={Babina, Tania and He, Alex X. and Jiang, Renhao},
  institution={National Bureau of Economic Research},
  type={NBER Working Paper},
  number={35684},
  year={2026}
}
```

## Data files

### `AI_keyword_2026.csv`

**This file contains all AI search terms used in our measures and the corresponding subcategory for each term: general AI (`GeneralAI`), machine learning (`ML`), natural language processing (`NLP`), computer vision (`CV`), generative AI (`GenAI`), agentic AI (`Agent`), and Other (`Other`).**

`job_posting_skill_name` is a skill requirement listed in job postings (Lightcast data). `keyword` is a word or phrase we search for in Revelio job titles and descriptions to identify that skill. One skill can have several keywords: for example, `ML`, `ml/ai`, and `machine learning` all correspond to the skill requirement **Machine Learning**. Each keyword has its own row. For details, see Appendix **A.2.1, “AI-relevant skills from job postings data,”** for skill selection and **A.2.2, “AI keyword expansion and matching method,”** for how skills are turned into keywords and how the three matching rules work, in [Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627).

`subcategory` records each keyword’s AI category. The categories were assigned using an LLM and reviewed by the authors, as described in Appendix **A.2.4, “AI technology subcategories.”**

`tier` tells the code how to search for each keyword. `tier_matching_rule` explains that same rule in words. The file's `tier1`, `tier2`, and `tier3` correspond to Methods 1, 2, and 3 in Appendix A.2.2 of the paper.

- **Tier 1:** Case-sensitive matching; the keyword cannot be part of a longer word. For example, `ML` matches “ML” but not “ml” or “HTML”.
- **Tier 2:** Case-insensitive matching; the keyword cannot be part of a longer word. For example, `ml/ai` also matches “ML/AI”.
- **Tier 3:** Case-insensitive matching; the text can occur anywhere, including within a longer word. For example, `machine learning` also matches “Machine Learning”.

### `data/input/synthetic_rev1_mar.dta`

Synthetic job-spell data for testing the Python step and a template to show data structure. Titles, descriptions, IDs, and dates are fabricated. No real Revelio records are included. This sample alone cannot run the company-matching or final Stata steps, which require external data.

## Code files

- **`code/00_matching_rcid_gvkey.do`** — Builds the year-by-year crosswalk between Revelio companies (`rcid`) and Compustat firms (`gvkey`), including subsidiaries. Produces `rcid_gvkey_match_final.dta`.
- **`code/001_build_AI_panel_090326.py`** — Filters job spells, matches AI keywords, and aggregates U.S. job counts to the Revelio company-year level for 2010–2024. Produces `rev_allyear_072026.csv`.
- **`code/002_AI_panel.do`** — Combines the crosswalk, Python job counts, and Compustat data; aggregates to the Compustat firm-year level; and constructs AI job shares. Produces `AI_panel_2010-2024.dta`.

Configuration instructions and input-location settings are provided in comments at the top of each script.

## References

The measures in this repository are based on two papers. [Babina et al. (2024)](https://ssrn.com/abstract=3651052) introduced the approach of measuring firms’ internal AI investment through their employment of AI-skilled workers. [Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627) updates and extends that measurement approach; the code and search terms in this repository are those used in the 2026 paper.

- **[Babina et al. (2024)](https://ssrn.com/abstract=3651052).** “Artificial Intelligence, Firm Growth, and Product Innovation.” *Journal of Financial Economics* 151, 103745.

- **[Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627).** “Canaries in the Gold Mine: Early Productivity Gains from Artificial Intelligence Creating Organization Capital.” *NBER Working Paper* 35684. Its appendix describes the keyword construction and matching procedures.

## Requirements

If you use the AI search terms or code, please cite both papers: [Babina et al. (2024)](https://ssrn.com/abstract=3651052) and [Babina, He, and Jiang (2026)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7345627). BibTeX entries are provided above.

- Python with `pandas`, `polars`, and `pyarrow`. The Python script records the author's package versions.
- For the full workflow: licensed Revelio job-spell data, Compustat data, Revelio company mapping and company-year employment counts, WRDS link files, Revelio parent-subsidiary data, and LLM and human checks of potential false-positive company matches. These external inputs are not included; the matching script lists its required files.

## Workflow

1. **Build the company crosswalk — `00_matching_rcid_gvkey.do`.** Match Revelio companies to Compustat firms and incorporate parent-subsidiary links provided by Revelio and LLM and human checks of potential false-positive company matches. This step requires the external inputs listed in the script, including LLM and human checks of potential false-positive company matches; those results are not generated automatically by the script.
2. **Build Revelio AI job counts — `001_build_AI_panel_090326.py`.** Process job spells and match the keyword dictionary to generate company-year U.S. job counts. The supplied synthetic sample can be used to test this step; sample-input configuration is explained in the code comments.
3. **Build the final Compustat firm-year panel — `002_AI_panel.do`.** Combine the outputs of steps 1 and 2 with Compustat employment data and construct AI-related job shares for 2010–2024.

Steps 1 and 2 are independent, but both outputs are required for step 3. If a completed company crosswalk is already available, it can be used directly in step 3.

## Notes
- The Python script uses multiprocessing; reduce `N_PROCS` if memory is limited.
