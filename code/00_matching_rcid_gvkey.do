*************************************************************
* 00_matching_rcid_gvkey.do
*
* Matches Revelio companies (rcid) to Compustat firms (gvkey)
* in four steps: (1) gvkey link provided by Revelio,
* (2) historical CUSIP, (3) historical CIK, (4) EIN. Matches
* are then combined, subsidiaries are assigned to their
* ultimate parent's gvkey, and potential false-positive
* matches are screened; see the appendix of our paper for a
* description of the manual (LLM) verification process.
*
* Output: rcid_gvkey_match_final.dta (rcid-year-gvkey panel)
*
* Required inputs:
*   $matching/compustat_identifier.dta           Compustat identifiers (gvkey, fyear, emp, ein, cusip, cik, conm, address)
*   $matching/company_mapping_revelio_short.dta  Revelio company mapping (rcid, gvkey, cusip, cik, ein, company, hq_*, ...)
*   $matching/rcid_emp.dta                       Revelio rcid-year employment counts
*   $wrds/ccmxpf_lnkhist.dta                     CRSP/Compustat merged link history (WRDS)
*   $wrds/msenames.dta                           CRSP stock names file (WRDS)
*   $wrds/wciklink_gvkey.dta                     WRDS SEC CIK-gvkey link
*   $subsidiary/subsidiary_structure_revelio.dta  Revelio parent-subsidiary structure file
*   $temp/year.dta                               helper file: one observation per calendar year (temp=1), for joinby
*   $temp/state.dta                              helper file: state abbreviation to full state name crosswalk
*   $matching/false positive/*_manualcheck.dta   manual review results (see the appendix of our paper)
*
**************************************************************/

* Set these paths to your own data locations before running.
* matching: Compustat identifiers, Revelio company mapping, rcid employment,
*           and the false positive subfolder containing manual-review inputs.
* temp: existing folder containing year.dta and state.dta; also stores intermediates.
* wrds: folder containing the three WRDS link files listed above.
* subsidiary: folder containing subsidiary_structure_revelio.dta.
* Create the output folders before running. Install unique and matchit if needed.
* The final crosswalk is saved in $matching. For 002_AI_panel.do, copy it to
* that script's $data folder alongside the Python output CSV.
global matching   "path/to/mapping/data"
global temp       "$matching/temp"
global wrds       "path/to/wrds/link/files"
global subsidiary "path/to/subsidiary/structure"

*get compustat gvkey year with positive employment

use "$matching/compustat_identifier", clear
ren cusip cusip_current
ren cik cik_current
ren fyear year
keep if emp>0 & emp<.
keep if year>=1990
keep gvkey year ein
save "$temp/compustat_posemp", replace

*******************************
*match gvkey to rcid using gvkey from revelio
*******************************

*get one to one rcid gvkey match from revelio
use "$matching/company_mapping_revelio_short", clear
keep if gvkey!=.
keep gvkey rcid
save "$temp/gvkey_rcid_revelio", replace

use "$temp/compustat_posemp", clear
merge m:1 gvkey using "$temp/gvkey_rcid_revelio", keep(1 3) nogen
keep if rcid!=.
gen match_on = "gvkey" 
save "$temp/gvkey_rcid_match_gvkey", replace

*******************************
*match gvkey to rcid using using historical cusip***
*******************************

*get one to one rcid cusip match from revelio
use "$matching/company_mapping_revelio_short", clear
keep if cusip!=""
replace cusip=substr(cusip,1,8)
*check that 8-digit cusip still uniquely match to rcid
unique cusip
keep cusip rcid
save "$temp/cusip_rcid", replace

use "$wrds/ccmxpf_lnkhist.dta", clear
drop if lpermno==.
gen firstyear=year(linkdt)
gen lastyear=year(linkenddt)
drop if lastyear<=1990
drop linktype liid lpermco linkprim
duplicates drop
save "$temp/gvkey_permno", replace

use "$wrds/msenames.dta", clear
gen firstyear=year(namedt)
gen lastyear=year(nameendt)
keep permno cusip firstyear lastyear name*
save "$temp/permno_cusip", replace

use "$temp/permno_cusip", clear
keep permno
duplicates drop
gen temp=1
joinby using "$temp/year"
sort permno year
drop temp
joinby permno using "$temp/permno_cusip"
drop if year<firstyear
drop if year>lastyear
keep permno cusip year
duplicates drop
*note: the permno-to-cusip link is the same across all years
save "$temp/permno_cusip_panel", replace

use "$temp/gvkey_permno", clear
keep gvkey
duplicates drop
gen temp=1
joinby using "$temp/year"
sort gvkey year
drop temp
joinby gvkey using "$temp/gvkey_permno"
drop if year<firstyear
drop if year>lastyear
ren lpermno permno
merge m:1 permno year using "$temp/permno_cusip_panel", keep(3) nogen
*if a year is the end of period 1 and start of period 2, use period 2 link
gsort gvkey year -firstyear
by gvkey year: gen count=_n
keep if count==1
keep gvkey year cusip
save "$temp/gvkey_cusip_panel", replace

use "$temp/compustat_posemp", clear
merge 1:1 gvkey year using "$temp/gvkey_cusip_panel", keep(1 3) nogen
merge m:1 cusip using "$temp/cusip_rcid", keep(1 3) nogen
drop if rcid==.
gen match_on = "cusip"
save "$temp/gvkey_rcid_match_cusip", replace


*******************************
*match gvkey to rcid using using historical cik***
*******************************

*get rcid cik match from revelio
use "$matching/company_mapping_revelio_short", clear
keep if cik!=""
bysort cik: gen count=_N
unique cik if count>1
*note: some CIKs match to multiple rcids; keep all candidate matches here (resolved when combining matches below)
keep cik rcid
save "$temp/cik_rcid", replace

use "$wrds/wciklink_gvkey", clear
drop if gvkey==.
* a lot of missing start dates, drop if start date missing
drop if link_start_date==.
gen firstyear=year(link_start_date)
gen lastyear=year(link_end_date)
keep cik gvkey firstyear lastyear link_start_date link_end_date
save "$temp/gvkey_cik", replace

use "$temp/gvkey_cik", clear
keep gvkey
duplicates drop
gen temp=1
joinby using "$temp/year"
sort gvkey year
drop temp
joinby gvkey using "$temp/gvkey_cik"
drop if year<firstyear
drop if year>lastyear
keep gvkey year cik
duplicates drop
joinby cik using "$temp/cik_rcid"
save "$temp/gvkey_cik_panel", replace

use "$temp/compustat_posemp", clear
joinby gvkey year using "$temp/gvkey_cik_panel"
gen match_on = "cik" 
save "$temp/gvkey_rcid_match_cik", replace


*******************************
*match gvkey to rcid using using ein (not historical)***
*******************************

*get one to one rcid ein match from revelio
use "$matching/company_mapping_revelio_short", clear
keep if ein!=.
*checked that ein uniquely match to rcid
keep rcid ein
save "$temp/ein_rcid", replace

use "$temp/compustat_posemp", clear
replace ein=subinstr(ein,"-","",.)
destring ein, replace
merge m:1 ein using "$temp/ein_rcid", keep(1 3) nogen
keep if rcid!=.
gen match_on = "ein" 
save "$temp/gvkey_rcid_match_ein", replace


*******************************
*clean dynamic parent-subsidiary file***
*******************************

use "$subsidiary/subsidiary_structure_revelio", clear
keep rcid ultimate_parent_rcid startdate1 enddate1
gen subsidiary=(rcid!=ultimate_parent_rcid)
gen startyear=year(startdate1)
gen endyear=year(enddate1) 
drop if endyear<=2000
bysort rcid: egen sum_subsidiary=sum(subsidiary)
drop if sum_subsidiary==0
gen temp=1
joinby using "$temp/year"
drop if year<startyear
drop if year>endyear
bysort rcid year: gen temp2=_N
drop if year==endyear & temp2>1
drop temp*
save "$temp/parent_subsidiary_panel", replace


*******************************
**combine all matches***
*******************************

use "$temp/gvkey_rcid_match_gvkey", clear

append using "$temp/gvkey_rcid_match_cusip"
append using "$temp/gvkey_rcid_match_cik"
drop ein
append using "$temp/gvkey_rcid_match_ein"

gen match_on_num=1 if match_on=="gvkey"
replace match_on_num=2 if match_on=="cusip"
replace match_on_num=3 if match_on=="cik"
replace match_on_num=4 if match_on=="ein"

bysort gvkey rcid year: egen temp_min_match_on=min(match_on_num)
forv i=1/4 {
	bysort gvkey rcid year: egen match_on_`i'=sum(match_on_num==`i')
}

keep if match_on_num==temp_min_match_on
unique gvkey rcid year

merge m:1 rcid year using "$matching/rcid_emp", keep(1 3) nogen

tab match_on


*multiple rcid per gvkey-year
bysort gvkey year: gen temp=_N
bysort gvkey year: gen temp_2=_n
tab temp if temp_2==1 & employment_count>0 & employment_count<.


*multiple gvkey per rcid-year
bysort rcid year: gen temp2=_N
bysort rcid year: gen temp2_2=_n
tab temp2 if temp2_2==1 & employment_count>0 & employment_count<.

*drop rcid with no job

keep if employment_count>0 & employment_count<.

*resolve remaining cases of one rcid-year to multiple gvkey matches

drop temp*

*if there is a gvkey match, keep the gvkey match (as we'll see later in validation, gvkey match is the most reliable one)
bysort rcid year: egen temp_min_match_on=min(match_on_num)
drop if match_on_num>1 & temp_min_match_on==1

*if there is cusip, keep cusip
drop if match_on_num>2 & temp_min_match_on==2

*deduplicate
bysort rcid year: gen temp=_n
bysort rcid year: gen temp2=_N
keep if temp==1
drop temp*

preserve 

ren rcid ultimate_parent_rcid
ren gvkey ultimate_parent_gvkey
ren match_on match_on_parent
keep ultimate* year match_on_parent

save "$temp/temp_ultimate_parent_gvkey", replace


use "$temp/parent_subsidiary_panel", clear
merge m:1 ultimate_parent_rcid year using "$temp/temp_ultimate_parent_gvkey", keep(1 3) nogen
drop if ultimate_parent_gvkey==.
keep if subsidiary==1
keep rcid year ultimate_parent_rcid ultimate_parent_gvkey subsidiary match_on_parent
save "$temp/ultimate_parent_gvkey", replace

keep rcid ultimate_parent_gvkey
duplicates drop
bysort rcid: gen temp=_n
reshape wide ultimate_parent_gvkey, i(rcid) j(temp)
save "$temp/ultimate_parent_gvkey_wide", replace

restore

merge m:1 rcid year using "$temp/ultimate_parent_gvkey"

cap drop employment_count
merge m:1 rcid year using "$matching/rcid_emp", keep(1 3) nogen
keep if employment_count>0 & employment_count<.
 
*drop false positives (cases where rcid is matched to parent's gvkey before acquisition)
merge m:1 rcid using "$temp/ultimate_parent_gvkey_wide", keep(1 3) nogen
forv i=1/5 {
	replace gvkey=. if subsidiary==. & gvkey==ultimate_parent_gvkey`i'
}
drop if gvkey==. & ultimate_parent_gvkey==.

replace subsidiary=0 if subsidiary==.

*replace gvkey with parent's gvkey after acquisition
replace gvkey=ultimate_parent_gvkey if subsidiary==1
replace match_on=match_on_parent if subsidiary==1

keep rcid year gvkey subsidiary match_on employment_count
bysort rcid: egen always_subsidiary=min(subsidiary)

sort rcid year
compress
save "$matching/rcid_gvkey_match", replace


**************************************************
******Validation*********************************
*************************************************

use "$matching/rcid_gvkey_match", clear

*for validation, only consider 2000 and later
keep if year>=2000

gen fyear=year
merge m:1 gvkey fyear using "$matching/compustat_identifier", keep(1 3) nogen keepus(conm addzip city state naics emp sich ipodate)

merge m:1 rcid using "$matching/company_mapping_revelio_short", keep(1 3) nogen keepus(company year_founded exchange_name naics_code ultimate_parent_company_name hq_zip_code hq_city hq_state hq_country) 

*compare industry
*note: naics is not historical in compustat, it has sich which is historical sic but not for naics
gen match_naics2=(substr(naics,1,2)==substr(naics_code,1,2))
gen match_naics4=(substr(naics,1,4)==substr(naics_code,1,4))
gen match_naics6=(naics==naics_code)

*compare location
merge m:1 state using "$temp/state", keep(1 3) nogen

gen match_state=(state_full==hq_state)
gen match_city=(city==hq_city)
gen match_zip=(addzip==hq_zip_code)

*compare names
foreach var in conm company ultimate_parent_company_name {
	replace `var'=subinstr(`var',".","",.)
	replace `var'=subinstr(`var',",","",.)
	replace `var'=proper(`var')
}

matchit conm company

*check date (year founded in Revelio should be before ipo date in Compustat)
gen year_ipo=year(ipodate)
gen wrong_date=(year_founded>year_ipo & year_founded!=.)

sum match_naics* match_state match_city match_zip similscore wrong_date

foreach id in gvkey cusip cik ein {
sum match_naics* match_state match_city match_zip similscore wrong_date if match_on=="`id'"
}

*export candidate false-positive matches for manual review
*(the manual verification process is described in the appendix of our paper)
preserve

keep if ((match_naics4==0 & match_state==0 & match_city==0 & match_zip==0 & similscore<0.9) | wrong==1 | employment_count/emp/1000>2) & subsidiary==0 & emp>=0.05 & employment_count >=50

save "$matching/false positive/nonsubsidiary", replace

restore

keep if subsidiary==1 & emp>=0.05 & employment_count >=50 & employment_count/emp/1000>=0.05

save "$matching/false positive/subsidiary", replace


**************************************************
******Finalize Matching*********************************
*************************************************


use "$matching/rcid_gvkey_match", clear

*for validation, only consider 2000 and later
keep if year>=2000

gen fyear=year
merge m:1 gvkey fyear using "$matching/compustat_identifier", keep(1 3) nogen keepus(conm addzip city state naics emp sich ipodate)

merge m:1 rcid using "$matching/company_mapping_revelio_short", keep(1 3) nogen keepus(company year_founded exchange_name naics_code ultimate_parent_company_name hq_zip_code hq_city hq_state hq_country) 

*compare industry
gen match_naics2=(substr(naics,1,2)==substr(naics_code,1,2))
gen match_naics4=(substr(naics,1,4)==substr(naics_code,1,4))
gen match_naics6=(naics==naics_code)

*compare location
merge m:1 state using "$temp/state", keep(1 3) nogen

gen match_state=(state_full==hq_state)
gen match_city=(city==hq_city)
gen match_zip=(addzip==hq_zip_code)

*compare names
foreach var in conm company ultimate_parent_company_name {
	replace `var'=subinstr(`var',".","",.)
	replace `var'=subinstr(`var',",","",.)
	replace `var'=proper(`var')
}

matchit conm company

*check date (year founded in Revelio should be before ipo date in Compustat)
gen year_ipo=year(ipodate)
gen wrong_date=(year_founded>year_ipo & year_founded!=.)

sum match_naics* match_state match_city match_zip similscore wrong_date

foreach id in gvkey cusip cik ein {
sum match_naics* match_state match_city match_zip similscore wrong_date if match_on=="`id'"
}



*merge in the results of the manual verification of potential false-positive
*matches; see the appendix of our paper for a description of this process
merge 1:1 rcid year using "$matching/false positive/subsidiary_manualcheck", keep(1 3) nogen
merge 1:1 rcid year using "$matching/false positive/nonsubsidiary_manualcheck", keep(1 3) nogen

gen fp=((match_naics4==0 & match_state==0 & match_city==0 & match_zip==0 & similscore<0.9) | wrong==1 | employment_count/emp/1000>2) & subsidiary==0 

replace fp=1 if subsidiary==1 

gen confirm=1 if fp==1 & subsidiary==0 & emp>=0.05 & employment_count >=50
replace confirm=1 if subsidiary==1 & emp>=0.05 & employment_count >=50 & employment_count/emp/1000>=0.05
replace confirm=0 if samefirm==0 | subsidiary_manual==0

bysort rcid gvkey: egen maxconfirm=max(confirm)
bysort rcid gvkey: egen minconfirm=min(confirm)

replace confirm=1 if minconfirm==1 & subsidiary==0 & fp==1

*fill in gaps
gen temp=year if confirm==1
bysort rcid gvkey: egen maxyear_confirm=max(temp)
bysort rcid gvkey: egen minyear_confirm=min(temp)
gen temp2=1 if confirm==0 & year>minyear_confirm & year<maxyear_confirm & subsidiary==1 & fp==1
bysort rcid gvkey: egen temp3=sum(temp2)
replace confirm=1 if year>minyear_confirm & year<maxyear_confirm & subsidiary==1 & fp==1 & temp3==0
drop temp*

drop if fp==1 & confirm!=1

keep rcid year gvkey match_on subsidiary employment_count company
compress
sort rcid year
order rcid year
save "$matching/rcid_gvkey_match_final", replace




