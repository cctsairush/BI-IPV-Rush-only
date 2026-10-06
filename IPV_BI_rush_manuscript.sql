---===========================================================================================================
---=== Project:  Brain Injury & Intimate Partner Violence (Rush)
---===
---=== Description: This query aims to identify patients with intimate partner violence (IPV) with or without traumatic brain injury (TBI).
---===				The query will produce de-identified encounter level data for the conditions of interest as well as 
---===				demographic variables, conditions, meds, and labs for the cohort during the study period.
---===				The script also produce analytical dataset for the BI-IPV Rush only manuscript. 
---===
---=== Programmer: Jonathan Tsai (Rush). Please reach out to chuan-ching_tsai@rush.edu if you have questions
---===
---=== Data Source: Standard CAPriCORN tables  
---===
---===========================================================================================================


USE [CAPriCORN database]  
GO

/*=================================================
	0. PREPARATION 
=================================================*/


---- 1) create the codelists ----

if OBJECT_ID('tempdb..#bi_codes') is not null drop table #bi_codes
CREATE TABLE #bi_codes (
	    [code]	varchar(50),
	    [desc]  varchar(max),
	    );
INSERT INTO #bi_codes
(code, [desc])
VALUES 	
('S09.90XA', 'Closed head injury, initial encounter'),
('F07.81', 'Post concussive syndrome'),
('S06.0X1A', 'Concussion with LOC <=30 minutes, initial encounter'),
('S06.0X0A', 'Concussion with no LOC, initial encounter'),
('S00.03XA', 'Scalp contusion, initial encounter'),
('T71.193A', 'Assault by manual strangulation'),
('S01.01XA', 'Scalp laceration, initial encounter'),
('S02.91XA', 'Closed fracture of skull'),
('I60.9', 'Subarachnoid hemorrhage'),
('S06.5X9A', 'Subdural hematoma'),
('S06.5X7A', 'Subdural hematoma'),
('S06.5X8A', 'Subdural hematoma'),
('S06.309A', 'Traumatic intracranial hemorrhage'),
('S06.307A', 'Traumatic intracranial hemorrhage'),
('S06.308A', 'Traumatic intracranial hemorrhage'),
('S06.0', 'Concussion'),
('S06.1', 'Traumatic cerebral edema'),
('S06.2', 'Diffuse traumatic brain injury'),
('S06.3', 'Focal traumatic brain injury'),
('S06.4', 'Epidural hemorrhage'),
('S06.5', 'Traumatic subdural hemorrhage'),
('S06.6', 'Traumatic subarachnoid hemorrhage'),
('S06.8', 'Other specified intracranial injuries'),
('S06.9', 'Unspecified intracranial injury'),
('S06.0X0', 'Concussion without loss of consciousness'),
('S06.0X1', 'Concussion with loss of consciousness of 30 minutes or less'),
('S06.0X9', 'Concussion with loss of consciousness of unspecified duration')
;

if OBJECT_ID('tempdb..#ipv_codes') is not null drop table #ipv_codes
CREATE TABLE #ipv_codes (
	    [code]	varchar(50),
	    [desc]  varchar(max),
	    );
INSERT INTO #ipv_codes
(code, [desc])
VALUES 	
('T74.11XA','Adult Physical abuse, confirmed, initial encounter'),
('T74.11XD', 'Adult physical abuse, confirmed, subsequent encounter'),
('T74.11XS', 'Adult physical abuse, confirmed, sequela'),
('T74.21XA','adult sexual abuse, confirmed, initial encounter'),
('T74.21XD', 'Adult sexual abuse, confirmed, subsequent encounter'),
('T74.21XS', 'Adult sexual abuse, confirmed, sequela'), 
('T74.31XA','Adult psychological abuse, confirmed, initial encounter'),
('T74.31XD', 'Adult psychological abuse, confirmed, subsequent encounter'), 
('T74.31XS', 'Adult psychological abuse, confirmed, sequela'), 
('T74.91XA','unspecified adult maltreatment, confirmed, initial encounter'),
('T74.91XD', 'Unspecified adult maltreatment, confirmed, subs encntr'), 
('T74.91XS', 'Unspecified adult maltreatment, confirmed, sequela'), 
('T76.11XA','Adult Physical abuse, suspected'),
('T76.11XD', 'Adult physical abuse, suspected, subsequent encounter'),
('T76.11XS', 'Adult physical abuse, suspected, sequela'),
('T76.21XA','adult sexual abuse, suspected, initial encounter'),
('T76.21XD', 'Adult sexual abuse, suspected, subsequent encounter'),
('T76.21XS', 'Adult sexual abuse, suspected, sequela'), 
('T76.31XA','Adult psychological abuse, suspected, initial encounter'),
('T76.31XD', 'Adult psychological abuse, suspected, subsequent encounter'), 
('T76.31XS', 'Adult psychological abuse, suspected, sequela'), 
('T76.91XA','unspecified adult maltreatment, suspected, initial encounter'),
('T76.91XD', 'Unspecified adult maltreatment, suspected, subs encntr'), 
('T76.91XS', 'Unspecified adult maltreatment, suspected, sequela'), 
('Y07.01', 'Husband, perpetrator of maltreatment and neglect'),   
('Y07.02', 'Wife, perpetrator of maltreatment and neglect'), 
('Y07.03', 'Male Partner, perpetrator'), 
('Y07.04',  'female partner, perpetrator'), 
('Y07.05', 'Non-Binary partner perpetrator of maltreatment and neglect')
;

----- 2) GET RAW BI DIAGNOSIS RECORDS 
if OBJECT_ID('tempdb..#enc_bi_raw') is not null drop table #enc_bi_raw
select distinct 
		enc.patid
		, enc.ENCOUNTERID
		, dx.DX
		, bi.[desc]
		, ISNULL(dx.DX_DATE, dx.ADMIT_DATE) as DX_DATE
into #enc_bi_raw
from dbo.ENCOUNTER enc
inner join dbo.diagnosis dx on enc.ENCOUNTERID = dx.ENCOUNTERID and enc.patid = dx.PATID
inner join #bi_codes bi on dx.DX = bi.code
where 
	enc.ADMIT_DATE between '01/01/2016' and '12/31/2025'  --- study timeframe 
	and dx.dx_type = '10' --- ICD-10 
;


---- 3) get raw IPV diagnosis records 
if OBJECT_ID('tempdb..#enc_ipv_raw') is not null drop table #enc_ipv_raw
select distinct enc.patid
				, enc.ENCOUNTERID
				, enc.RAW_SITEID   ---dept name 
				, dx.DX
				, ipv.[desc]
				, ISNULL(dx.DX_DATE, dx.ADMIT_DATE) as DX_DATE
into #enc_ipv_raw
from dbo.encounter enc
inner join dbo.diagnosis dx on enc.ENCOUNTERID = dx.ENCOUNTERID and enc.patid = dx.PATID
inner join #ipv_codes ipv on dx.DX = ipv.code
where 
	enc.ADMIT_DATE between '01/01/2016' and '12/31/2025' --- study timeframe 
	and dx.dx_type = '10'  --- ICD-10
;




/* -----------------------------------------------------------
	1. COHORT BUILDING: IPV+BI VS IPV-ALONE


   1) IPV encounters that qualify (have ANY TBI within +/-180d)
----------------------------------------------------------- */
DROP TABLE IF EXISTS #ipv_qualifying;
SELECT DISTINCT
    i.patid,
    i.encounterid AS ipv_encounterid,
    i.dx_date     AS ipv_date
INTO #ipv_qualifying
FROM #enc_ipv_raw i
WHERE EXISTS (
    SELECT 1
    FROM #enc_bi_raw t
    WHERE t.patid = i.patid
      AND t.dx_date BETWEEN DATEADD(DAY, -180, i.dx_date)
                        AND DATEADD(DAY,  180, i.dx_date)
);

/* -----------------------------------------------------------
   2) IPV+TBI index = first qualifying IPV encounter per patient
----------------------------------------------------------- */
DROP TABLE IF EXISTS #ipv_bi_index;
WITH ranked AS (
    SELECT
        patid,
        ipv_encounterid,
        ipv_date,
        ROW_NUMBER() OVER (
            PARTITION BY patid
            ORDER BY ipv_date ASC, ipv_encounterid ASC
        ) AS rn
    FROM #ipv_qualifying
)
SELECT
    patid,
    ipv_encounterid AS index_ipv_encounterid,
    ipv_date        AS index_ipv_date
INTO #ipv_bi_index
FROM ranked
WHERE rn = 1;

/* -----------------------------------------------------------
   3) IPV-only index = first IPV encounter overall
      (only among patients NOT in IPV+TBI)
----------------------------------------------------------- */
DROP TABLE IF EXISTS #ipv_only_index;
WITH all_ipv AS (
    SELECT DISTINCT 
			patid
			, encounterid
			, dx_date
    FROM #enc_ipv_raw
),
ranked AS (
    SELECT
        a.patid,
        a.encounterid,
        a.dx_date,
        ROW_NUMBER() OVER (
            PARTITION BY a.patid
            ORDER BY a.dx_date ASC, a.encounterid ASC
        ) AS rn
    FROM all_ipv a
    LEFT JOIN #ipv_bi_index x
      ON x.patid = a.patid
    WHERE x.patid IS NULL
)
SELECT
    patid,
    encounterid AS index_ipv_encounterid,
    dx_date     AS index_ipv_date
INTO #ipv_only_index
FROM ranked
WHERE rn = 1;

/* -----------------------------------------------------------
   4) Final patient-level cohort + index table
----------------------------------------------------------- */
DROP TABLE IF EXISTS #pt_ipv_labeled_indexed_18plus;

WITH combined AS (
    SELECT
        patid,
        'IPV+TBI' AS cohort_label,
        index_ipv_encounterid,
        index_ipv_date
    FROM #ipv_bi_index

    UNION ALL

    SELECT
        patid,
        'IPV-alone' AS cohort_label,
        index_ipv_encounterid,
        index_ipv_date
    FROM #ipv_only_index
),
with_age AS (
    SELECT
        c.*,
        d.BIRTH_DATE,
        DATEDIFF(YEAR, d.BIRTH_DATE, c.index_ipv_date) AS age_at_index_ipv
    FROM combined c
    JOIN dbo.DEMOGRAPHIC d
      ON d.PATID = c.patid
)
SELECT *
INTO #pt_ipv_labeled_indexed_18plus
FROM with_age
WHERE age_at_index_ipv >= 18;  --- age constraint 

/*	==========================================
	add insurance status + enc_type + dept to table 1 
========================================== */
drop table if exists #ipv_table1;
with payer_raw as 
(
select a.*
		, e.PAYER_TYPE_PRIMARY
		, case when PAYER_TYPE_PRIMARY like '1%' then 'medicare'
			   when PAYER_TYPE_PRIMARY like '2%' then 'medicaid'
			   when PAYER_TYPE_PRIMARY like '5%' then 'private'
			   when PAYER_TYPE_PRIMARY like '6%' then 'private' 
			   when PAYER_TYPE_PRIMARY like '3%' then 'other/unknown'
			   when PAYER_TYPE_PRIMARY like '4%' then 'other/unknown'
			   when PAYER_TYPE_PRIMARY like '8%' then 'other/unknown'
			   when PAYER_TYPE_PRIMARY like '9%' then 'other/unknown'
			   when PAYER_TYPE_PRIMARY = 'UN' then 'other/unknown'
			   when PAYER_TYPE_PRIMARY is null then 'other/unknown'
			   end as payer_cat
		, case when e.ENC_TYPE = 'AV' then 'AV'
			   when e.ENC_TYPE in ('ED', 'EI') then 'ED'
			   else 'other' 
			   end as enc_type
		, case when e.RAW_SITEID like '%primary care%' then 1 else 0 
			   end as primary_care_flag
from #pt_ipv_labeled_indexed_18plus a
join dbo.ENCOUNTER e
	on a.index_ipv_encounterid = e.ENCOUNTERID
	)
select 
	p.cohort_label,
    p.PATID,
    p.index_ipv_date index_date,
    p.age_at_index_ipv age_at_index,

    d.SEX,
    d.RACE,
    d.HISPANIC,
    d.SEXUAL_ORIENTATION,
    d.GENDER_IDENTITY,
    d.PAT_PREF_LANGUAGE_SPOKEN,
	p.payer_cat
into #ipv_table1
from payer_raw p
join dbo.DEMOGRAPHIC d
	on p.PATID = d.PATID




/* ============================================================
   2. Injury type 

   A) categorize all qualifying injuries 
   ============================================================ */

DROP TABLE IF EXISTS #injury_qualifying_to_index;

SELECT
    p.patid,
    p.cohort_label,
    p.index_ipv_encounterid,
    p.index_ipv_date,
    p.age_at_index_ipv,

    t.encounterid AS injury_encounterid,
    t.dx_date     AS injury_date,
    t.dx          AS injury_dx,

    DATEDIFF(DAY, p.index_ipv_date, t.dx_date) AS days_from_index,

    CASE
        /* Traumatic brain injury */
        WHEN t.dx = 'F07.81'
		  OR t.dx = 'S02.91XA'
          OR t.dx LIKE 'S06.0%'
          OR t.dx LIKE 'S06.1%'
          OR t.dx LIKE 'S06.2%'
          OR t.dx LIKE 'S06.3%'
          OR t.dx LIKE 'S06.4%'
          OR t.dx LIKE 'S06.5%'
          OR t.dx LIKE 'S06.6%'
		  OR t.dx LIKE 'S06.8%'
		  OR t.dx LIKE 'S06.9%'
          OR t.dx = 'I60.9'
        THEN 'traumatic_brain_injury'

        /* Strangulation */
        WHEN t.dx = 'T71.193A'
        THEN 'strangulation'

        /* Unspecified / other head injury */
        WHEN t.dx IN ('S09.90XA', 'S00.03XA', 'S01.01XA')
        THEN 'unspecified_or_other_head_injury'

        ELSE NULL
    END AS injury_type
INTO #injury_qualifying_to_index
FROM #pt_ipv_labeled_indexed_18plus p
JOIN #enc_bi_raw t
  ON t.patid = p.patid
WHERE p.cohort_label = 'IPV+TBI'
  AND t.dx_date BETWEEN DATEADD(DAY, -180, p.index_ipv_date)
                    AND DATEADD(DAY,  180, p.index_ipv_date);

/* ============================================================
   B) Patient-level flags for each injury type 
   This first flags whether each patient had:

		--any traumatic brain injury
		--any strangulation
		--any unspecified/other head injury code

	Then it applies the rule:

		--unspecified/other counts only if no TBI and no strangulation
   ============================================================ */

DROP TABLE IF EXISTS #pt_injury_pattern;

WITH per_patient AS (
    SELECT
        patid,
        MAX(CASE WHEN injury_type = 'traumatic_brain_injury' THEN 1 ELSE 0 END) AS has_tbi,
        MAX(CASE WHEN injury_type = 'strangulation' THEN 1 ELSE 0 END) AS has_strangulation,
        MAX(CASE WHEN injury_type = 'unspecified_or_other_head_injury' THEN 1 ELSE 0 END) AS has_unspecified_raw
    FROM #injury_qualifying_to_index
    WHERE injury_type IS NOT NULL
    GROUP BY patid
)
SELECT
    patid,
    has_tbi,
    has_strangulation,
    CASE
        WHEN has_tbi = 0 AND has_strangulation = 0 AND has_unspecified_raw = 1 THEN 1
        ELSE 0
    END AS has_unspecified_other
INTO #pt_injury_pattern
FROM per_patient;




/* ============================================================
   C) Cohort-level summary: percentage by injury type (IPV+TBI only)
   ============================================================ */

WITH denom AS (
    SELECT COUNT(DISTINCT patid) AS n_ipv_tbi
    FROM #pt_ipv_labeled_indexed_18plus
    WHERE cohort_label = 'IPV+TBI'
)
SELECT
    MAX(d.n_ipv_tbi) AS n_ipv_tbi,

    SUM(CASE WHEN p.has_tbi = 1 THEN 1 ELSE 0 END) AS n_traumatic_brain_injury,
    CAST(100.0 * SUM(CASE WHEN p.has_tbi = 1 THEN 1 ELSE 0 END) / MAX(d.n_ipv_tbi) AS DECIMAL(6,2)) AS pct_traumatic_brain_injury,

    SUM(CASE WHEN p.has_strangulation = 1 THEN 1 ELSE 0 END) AS n_strangulation,
    CAST(100.0 * SUM(CASE WHEN p.has_strangulation = 1 THEN 1 ELSE 0 END) / MAX(d.n_ipv_tbi) AS DECIMAL(6,2)) AS pct_strangulation,

    SUM(CASE WHEN p.has_unspecified_other = 1 THEN 1 ELSE 0 END) AS n_unspecified_or_other_head_injury,
    CAST(100.0 * SUM(CASE WHEN p.has_unspecified_other = 1 THEN 1 ELSE 0 END) / MAX(d.n_ipv_tbi) AS DECIMAL(6,2)) AS pct_unspecified_or_other_head_injury

FROM #pt_injury_pattern p
CROSS JOIN denom d;



/* ============================================
 3. COMORBIDITIES 

	look-back period: one year prior to index  
	conditions are categorized into 24 broader chronic condition categories 
============================================== */


--- A) raw diagnoses 
if OBJECT_ID('tempdb..#t4_diagnosis') is not null drop table #t4_diagnosis 
select distinct PATID
		, ENCOUNTERID
		, DX
		, DX_TYPE
		, DX_DATE
INTO #t4_diagnosis
from dbo.DIAGNOSIS
WHERE PATID IN (select PATID FROM #pt_ipv_labeled_indexed_18plus)
		and DX_DATE between '01/01/2016' and '12/31/2025'



---- B) qualifying diagnoses: row level, long
drop table if exists #comorbidity
		select distinct d.PATID, dem.cohort_label, i.category
		into #comorbidity
		from #t4_diagnosis d
		join [CONDITION MAPPING TABLE] i ---- join to the mapping table 
			on d.DX = i.ICD10
		join #pt_ipv_labeled_indexed_18plus dem 
			on dem.PATID = d.PATID
			AND d.DX_DATE between dateadd(day, -365, dem.index_ipv_date) and dateadd(day, -1, dem.index_ipv_date)   --- 1 year look back
		
--- C)	summary by cohort 	
select cohort_label, category, count(distinct PATID) as cnt ----distinct count of patients
from #comorbidity
group by cohort_label, category 
order by cohort_label, cnt desc




/* =========================================================================
	4. DENOMINATOR: all cap pt 

		all unique pt >18 y/o with a visit from 2016-2025
		A) All CAPriCORN 
		B) ED CAPriCORN  - the ED population might be different from the general Rush patients 
========================================================================= */

--- A) All CAPriCORN
DROP TABLE IF EXISTS #pt_all_capricorn;

WITH eligible_enc AS (
    SELECT
        e.PATID,
        e.ENCOUNTERID,
        e.ADMIT_DATE,
        e.ENC_TYPE,
        e.PAYER_TYPE_PRIMARY,
        e.RAW_SITEID,
        d.BIRTH_DATE,

        DATEDIFF(YEAR, d.BIRTH_DATE, e.ADMIT_DATE)
 
             AS age_at_encounter

    FROM dbo.ENCOUNTER e
    JOIN dbo.DEMOGRAPHIC d
      ON d.PATID = e.PATID

    WHERE e.ADMIT_DATE BETWEEN '2016-01-01' AND '2025-12-31'

),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PATID
            ORDER BY ADMIT_DATE ASC, ENCOUNTERID ASC
        ) AS rn
    FROM eligible_enc
    WHERE age_at_encounter >= 18
)
SELECT
    PATID,
    ENCOUNTERID AS index_encounterid,
    ADMIT_DATE  AS index_date,
    BIRTH_DATE,
    age_at_encounter AS age_at_index
INTO #pt_all_capricorn
FROM ranked
WHERE rn = 1;


/* ============================================================
   B) ALL CAPriCORN ADULT ED PATIENTS
      >=18 at first ED encounter during study period

      ED = ED or EI
============================================================ */

DROP TABLE IF EXISTS #pt_all_capricorn_ed;

WITH eligible_ed AS (
    SELECT
        e.PATID,
        e.ENCOUNTERID,
        e.ADMIT_DATE,
        e.ENC_TYPE,
        e.PAYER_TYPE_PRIMARY,
        e.RAW_SITEID,
        d.BIRTH_DATE,

        DATEDIFF(YEAR, d.BIRTH_DATE, e.ADMIT_DATE) AS age_at_encounter

    FROM dbo.ENCOUNTER e
    JOIN dbo.DEMOGRAPHIC d
      ON d.PATID = e.PATID

    WHERE e.ADMIT_DATE BETWEEN '2016-01-01' AND '2025-12-31'
      AND e.ENC_TYPE IN ('ED','EI')
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PATID
            ORDER BY ADMIT_DATE ASC, ENCOUNTERID ASC
        ) AS rn
    FROM eligible_ed
    WHERE age_at_encounter >= 18
)
SELECT
    PATID,
    ENCOUNTERID AS index_encounterid,
    ADMIT_DATE  AS index_date,
    BIRTH_DATE,
    age_at_encounter AS age_at_index
INTO #pt_all_capricorn_ed
FROM ranked
WHERE rn = 1;



/* ============================================================
    Combine two comparison populations
============================================================ */

DROP TABLE IF EXISTS #pt_capricorn_comparison;

SELECT
    PATID,
    'All CAPriCORN' AS cohort_label,
    index_encounterid,
    index_date,
    BIRTH_DATE,
    age_at_index
INTO #pt_capricorn_comparison
FROM #pt_all_capricorn

UNION ALL

SELECT
    PATID,
    'All CAPriCORN ED' AS cohort_label,
    index_encounterid,
    index_date,
    BIRTH_DATE,
    age_at_index
FROM #pt_all_capricorn_ed;



/* ============================================================
   Insurance for new comparison cohorts
      based on first qualifying encounter
============================================================ */

DROP TABLE IF EXISTS #capricorn_payer;

SELECT
    p.PATID,
    p.cohort_label,
    p.index_encounterid,
    p.index_date,
    e.PAYER_TYPE_PRIMARY,

    CASE
        WHEN e.PAYER_TYPE_PRIMARY LIKE '1%' THEN 'medicare'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '2%' THEN 'medicaid'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '5%' THEN 'private'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '6%' THEN 'private'

        WHEN e.PAYER_TYPE_PRIMARY LIKE '3%' THEN 'other/unknown'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '4%' THEN 'other/unknown'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '8%' THEN 'other/unknown'
        WHEN e.PAYER_TYPE_PRIMARY LIKE '9%' THEN 'other/unknown'
        WHEN e.PAYER_TYPE_PRIMARY = 'UN'    THEN 'other/unknown'
        WHEN e.PAYER_TYPE_PRIMARY IS NULL   THEN 'other/unknown'

        ELSE 'other/unknown'
    END AS payer_cat

INTO #capricorn_payer
FROM #pt_capricorn_comparison p
JOIN dbo.ENCOUNTER e
  ON e.ENCOUNTERID = p.index_encounterid;

select * from #capricorn_payer
/* ============================================================
    Demographic source table for Table 1
============================================================ */

DROP TABLE IF EXISTS #capricorn_table1_demo;

SELECT
    p.cohort_label,
    p.PATID,
    p.index_date,
    p.age_at_index,

    d.SEX,
    d.RACE,
    d.HISPANIC,
    d.SEXUAL_ORIENTATION,
    d.GENDER_IDENTITY,
    d.PAT_PREF_LANGUAGE_SPOKEN, 

	pay.payer_cat

INTO #capricorn_table1_demo
FROM #pt_capricorn_comparison p
JOIN #capricorn_payer pay	
	ON pay.PATID = p.PATID
		and pay.cohort_label = p.cohort_label
		and pay.index_encounterid = p.index_encounterid
left JOIN dbo.DEMOGRAPHIC d
    ON d.PATID = p.PATID;





/* ======================================================
	5. Healthcare utilization 

	ambulatory care & acute care usage within a year 
	prior to index. 
====================================================== */

WITH healthcare_util_enc AS 
(
    SELECT DISTINCT 
        c.PATID,
        c.cohort_label,
        e.enc_type
    FROM #pt_ipv_labeled_indexed_18plus c
    LEFT JOIN dbo.ENCOUNTER e 
        ON e.PATID = c.PATID
       AND e.ADMIT_DATE BETWEEN DATEADD(DAY, -365, c.index_ipv_date) 
                            AND DATEADD(DAY, -1, c.index_ipv_date)
),

pt_lvl_binary AS 
(
    SELECT 
        PATID,
        cohort_label,

        MAX(CASE 
                WHEN enc_type IN ('AV','OA','TH') 
                THEN 1 ELSE 0 
            END) AS any_ambulatory,

        MAX(CASE 
                WHEN enc_type IN ('ED','EI','IP','OS') 
                THEN 1 ELSE 0 
            END) AS any_acute

    FROM healthcare_util_enc
    GROUP BY PATID, cohort_label
)
select * from pt_lvl_binary

--SELECT
--    cohort_label,

--    COUNT(*) AS cohort_n,

--    SUM(any_ambulatory) AS cnt_any_ambulatory,
--    SUM(any_ambulatory) * 1.0 / COUNT(*) AS pct_any_ambulatory,

--    SUM(any_acute) AS cnt_any_acute,
--    SUM(any_acute) * 1.0 / COUNT(*) AS pct_any_acute

--FROM pt_lvl_binary

--GROUP BY cohort_label;

