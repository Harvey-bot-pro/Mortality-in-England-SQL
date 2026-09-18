-- =========================================================
-- 1. SELECT DATABASES;
-- =========================================================
SHOW DATABASES;
use nhs_mortality_analysis;

-- =========================================================
-- 2. CHECK ALL TABLES
-- =========================================================

SHOW TABLES;


-- =========================================================
-- 3. CHECK TABLE ROW COUNTS
-- =========================================================
SELECT COUNT(*) AS fact_rows
FROM fact_mortality;

SELECT COUNT(*) AS date_rows
FROM dim_date;

SELECT COUNT(*) AS area_rows
FROM dim_area;

SELECT COUNT(*) AS sex_rows
FROM dim_sex;

SELECT COUNT(*) AS age_group_rows
FROM dim_age_group;


-- =========================================================
-- 4. CHECK FOR DUPLICATES
-- Grain = date + area + sex + age group
-- =========================================================
SELECT
    date_key,
    area_key,
    sex_key,
    age_group_key,
    COUNT(*) AS row_count
FROM fact_mortality
GROUP BY
    date_key,
    area_key,
    sex_key,
    age_group_key
HAVING COUNT(*) > 1;


-- =========================================================
-- 5. CHECK FOR NULL VALUES
-- =========================================================
SELECT
    SUM(date_key IS NULL) AS null_date_key,
    SUM(area_key IS NULL) AS null_area_key,
    SUM(sex_key IS NULL) AS null_sex_key,
    SUM(age_group_key IS NULL) AS null_age_group_key,
    SUM(registered_deaths IS NULL) AS null_deaths,
    SUM(directly_standardised_rate IS NULL) AS null_rate,
    SUM(lower_95_ci IS NULL) AS null_lower_ci,
    SUM(upper_95_ci IS NULL) AS null_upper_ci
FROM fact_mortality;


-- =========================================================
-- 6. CHECK FOR TEMPORARY SENTINEL VALUES (-999)
-- =========================================================
SELECT
    SUM(directly_standardised_rate = -999) AS sentinel_rate,
    SUM(lower_95_ci = -999) AS sentinel_lower_ci,
    SUM(upper_95_ci = -999) AS sentinel_upper_ci
FROM fact_mortality;


-- =========================================================
-- 7. CONVERT -999 VALUES TO NULL
-- =========================================================
SET SQL_SAFE_UPDATES = 0;

UPDATE nhs_mortality_analysis.fact_mortality
SET
    directly_standardised_rate =
        NULLIF(directly_standardised_rate, -999),
    lower_95_ci =
        NULLIF(lower_95_ci, -999),
    upper_95_ci =
        NULLIF(upper_95_ci, -999)
WHERE directly_standardised_rate = -999
   OR lower_95_ci = -999
   OR upper_95_ci = -999;

SET SQL_SAFE_UPDATES = 1;


-- =========================================================
-- 8. VERIFY FINAL ROW COUNT + NULLS
-- =========================================================
SELECT
    COUNT(*) AS total_rows,
    SUM(directly_standardised_rate IS NULL) AS null_rate,
    SUM(lower_95_ci IS NULL) AS null_lower_ci,
    SUM(upper_95_ci IS NULL) AS null_upper_ci
FROM fact_mortality;


-- =========================================================
-- 9. CHECK FOR IMPOSSIBLE NEGATIVE VALUES
-- =========================================================
SELECT *
FROM fact_mortality
WHERE registered_deaths < 0
   OR directly_standardised_rate < 0
   OR lower_95_ci < 0
   OR upper_95_ci < 0;


-- =========================================================
-- 10. CHECK CONFIDENCE INTERVAL LOGIC
-- Lower CI should not be greater than Upper CI
-- =========================================================
SELECT *
FROM fact_mortality
WHERE lower_95_ci > upper_95_ci;


-- =========================================================
-- 11. CHECK FOREIGN KEY / ORPHAN RECORDS
-- =========================================================
SELECT
    SUM(d.date_key IS NULL) AS orphan_date,
    SUM(a.area_key IS NULL) AS orphan_area,
    SUM(s.sex_key IS NULL) AS orphan_sex,
    SUM(ag.age_group_key IS NULL) AS orphan_age_group
FROM nhs_mortality_analysis.fact_mortality AS f

LEFT JOIN nhs_mortality_analysis.dim_date AS d
    ON f.date_key = d.date_key

LEFT JOIN nhs_mortality_analysis.dim_area AS a
    ON f.area_key = a.area_key

LEFT JOIN nhs_mortality_analysis.dim_sex AS s
    ON f.sex_key = s.sex_key

LEFT JOIN nhs_mortality_analysis.dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key;


-- =========================================================
-- 12. VIEW DIMENSION TABLES
-- =========================================================
-- Sex categories
SELECT *
FROM dim_sex
ORDER BY sex_key;

-- Age-group categories
SELECT *
FROM dim_age_group
ORDER BY age_group_key;

-- Geographic areas
SELECT *
FROM dim_area
ORDER BY area_key;
-- =========================================================
-- 13. CHECK DATE RANGE
-- =========================================================
SELECT
    MIN(`date`) AS start_date,
    MAX(`date`) AS end_date,
    COUNT(DISTINCT `year`) AS number_of_years
FROM dim_date;


-- =========================================================
-- 14. TEST THE FULL STAR-SCHEMA JOIN
-- ========================================================
DESCRIBE dim_date;
USE nhs_mortality_analysis;

ALTER TABLE nhs_mortality_analysis.dim_date
CHANGE COLUMN `  month_name` `month_name` VARCHAR(15) NOT NULL;

SELECT month_name
FROM nhs_mortality_analysis.dim_date
LIMIT 10;


SELECT
    d.`date` AS mortality_date,
    d.`year`,
    d.month_name,
    a.area_name,
    s.sex,
    ag.age_group,
    f.registered_deaths,
    f.directly_standardised_rate,
    f.lower_95_ci,
    f.upper_95_ci
FROM fact_mortality AS f
INNER JOIN dim_date AS d
    ON f.date_key = d.date_key
INNER JOIN dim_area AS a
    ON f.area_key = a.area_key
INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key
INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key
ORDER BY
    d.`date`,
    a.area_name,
    s.sex,
    ag.age_group
LIMIT 20;
-- =========================================================
-- 16. DESCRIBE TABLE STRUCTURE
-- =========================================================
DESCRIBE fact_mortality;
DESCRIBE dim_date;
DESCRIBE dim_area;
DESCRIBE dim_sex;
DESCRIBE dim_age_group;

--Overall yearly mortality trend


SELECT DISTINCT sex
FROM dim_sex;

SELECT DISTINCT age_group
FROM dim_age_group;

SELECT DISTINCT area_name
FROM dim_area;



SELECT
    current_year.mortality_year,
    current_year.total_deaths,
    previous_year.total_deaths AS previous_year_deaths,
    ROUND(
        (
            current_year.total_deaths - previous_year.total_deaths
        ) / previous_year.total_deaths * 100,
        2
    ) AS yoy_change_pct

FROM
(
    SELECT
        d.`Year` AS mortality_year,
        SUM(f.registered_deaths) AS total_deaths
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name = 'All regions'

    GROUP BY d.`Year`
) AS current_year

LEFT JOIN
(
    SELECT
        d.`Year` AS mortality_year,
        SUM(f.registered_deaths) AS total_deaths
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name = 'All regions'

    GROUP BY d.`Year`
) AS previous_year

ON current_year.mortality_year = previous_year.mortality_year + 1

ORDER BY current_year.mortality_year;

USE nhs_mortality_analysis;
-----------------------------------------------------
--# directly standardised mortality rate over time.
-----------------------------------------------------
SELECT
    d.`Year` AS mortality_year,
    ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_date AS d
    ON f.date_key = d.date_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE s.sex = 'Persons'
  AND ag.age_group = 'All ages'
  AND a.area_name = 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY d.`Year`

ORDER BY d.`Year`;
-------------------------------------------------
-- Which regions have the highest and lowest mortality rates?
--------------------------------------------------
SELECT
    a.area_name,
    ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE s.sex = 'Persons'
  AND ag.age_group = 'All ages'
  AND a.area_name <> 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY a.area_name

ORDER BY avg_mortality_rate DESC;
-- ================================================
#Has this regional gap changed over time?
-- ===========================================

SELECT
    d.`Year` AS mortality_year,
    a.area_name,
    ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_date AS d
    ON f.date_key = d.date_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE s.sex = 'Persons'
  AND ag.age_group = 'All ages'
  AND a.area_name <> 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY
    d.`Year`,
    a.area_name

ORDER BY
    d.`Year`,
    avg_mortality_rate DESC;

-- =================================================================================
#using CTE/Window functions to find the highest and lowest mortality rates by year
-- ==================================================================================
SELECT
    yearly.mortality_year,
    yearly.area_name,
    yearly.avg_mortality_rate
FROM
(
    SELECT
        d.`Year` AS mortality_year,
        a.area_name,
        ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY
        d.`Year`,
        a.area_name
) AS yearly

INNER JOIN
(
    SELECT
        rates.mortality_year,
        MAX(rates.avg_mortality_rate) AS highest_rate
    FROM
    (
        SELECT
            d.`Year` AS mortality_year,
            a.area_name,
            ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
        FROM fact_mortality AS f

        INNER JOIN dim_date AS d
            ON f.date_key = d.date_key

        INNER JOIN dim_area AS a
            ON f.area_key = a.area_key

        INNER JOIN dim_sex AS s
            ON f.sex_key = s.sex_key

        INNER JOIN dim_age_group AS ag
            ON f.age_group_key = ag.age_group_key

        WHERE s.sex = 'Persons'
          AND ag.age_group = 'All ages'
          AND a.area_name <> 'All regions'
          AND f.directly_standardised_rate IS NOT NULL

        GROUP BY
            d.`Year`,
            a.area_name
    ) AS rates

    GROUP BY rates.mortality_year
) AS highest

ON yearly.mortality_year = highest.mortality_year
AND yearly.avg_mortality_rate = highest.highest_rate

ORDER BY yearly.mortality_year;
-- ===============================================
#Which region improved the most?
-- =================================================
SELECT
    r2019.area_name,
    r2019.mortality_rate_2019,
    r2025.mortality_rate_2025,

    ROUND(
        r2025.mortality_rate_2025 -
        r2019.mortality_rate_2019,
        2
    ) AS rate_change,

    ROUND(
        (
            r2025.mortality_rate_2025 -
            r2019.mortality_rate_2019
        )
        / r2019.mortality_rate_2019 * 100,
        2
    ) AS pct_change

FROM
(
    SELECT
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS mortality_rate_2019
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2019
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY a.area_name
) AS r2019

INNER JOIN
(
    SELECT
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS mortality_rate_2025
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2025
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY a.area_name
) AS r2025

ON r2019.area_name = r2025.area_name

ORDER BY pct_change ASC;
-- ============================================================
#Age-group analysis, Which age groups carry the greatest mortality burden?
-- ==========================================================

SELECT
    ag.age_group,
    SUM(f.registered_deaths) AS total_deaths,
    ROUND(AVG(f.directly_standardised_rate), 2) AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

WHERE s.sex = 'Persons'
  AND a.area_name = 'All regions'
  AND ag.age_group <> 'All ages'

GROUP BY ag.age_group

ORDER BY total_deaths DESC;

-- =============================================================
#Male vs Female mortality Are mortality patterns different between males and females?
-- ==============================================================
SELECT
    s.sex,
    SUM(f.registered_deaths) AS total_deaths,
    ROUND(AVG(f.directly_standardised_rate), 2)
        AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE s.sex IN ('Males', 'Females')
  AND ag.age_group = 'All ages'
  AND a.area_name = 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY s.sex

ORDER BY avg_mortality_rate DESC;
-- ================================================================
#investigating where that male/female gap comes from
-- ==================================================================

SELECT
    ag.age_group,
    s.sex,
    SUM(f.registered_deaths) AS total_deaths,
    ROUND(AVG(f.directly_standardised_rate), 2)
        AS avg_mortality_rate
FROM fact_mortality AS f

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

WHERE s.sex IN ('Males', 'Females')
  AND ag.age_group <> 'All ages'
  AND a.area_name = 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY
    ag.age_group,
    s.sex

ORDER BY
    ag.age_group,
    avg_mortality_rate DESC;
-- ================================================================
#male–female mortality-rate gap by age group
-- ===============================================================
SELECT
    male.age_group,
    male.male_rate,
    female.female_rate,

    ROUND(
        male.male_rate - female.female_rate,
        2
    ) AS rate_difference,

    ROUND(
        ((male.male_rate - female.female_rate)
        / female.female_rate) * 100,
        2
    ) AS male_rate_higher_pct

FROM
(
    SELECT
        ag.age_group,
        AVG(f.directly_standardised_rate) AS male_rate
    FROM fact_mortality AS f

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    WHERE s.sex = 'Males'
      AND ag.age_group <> 'All ages'
      AND a.area_name = 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY ag.age_group
) AS male

INNER JOIN
(
    SELECT
        ag.age_group,
        AVG(f.directly_standardised_rate) AS female_rate
    FROM fact_mortality AS f

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    WHERE s.sex = 'Females'
      AND ag.age_group <> 'All ages'
      AND a.area_name = 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY ag.age_group
) AS female

ON male.age_group = female.age_group

ORDER BY male_rate_higher_pct DESC;
-- ==============================================================
#Which age group experienced the largest increase in mortality rate from 2019 to 2020?
-- ==============================================================
SELECT
    y2019.age_group,
    
    ROUND(y2019.mortality_rate_2019, 2) AS mortality_rate_2019,
    ROUND(y2020.mortality_rate_2020, 2) AS mortality_rate_2020,

    ROUND(
        y2020.mortality_rate_2020 - y2019.mortality_rate_2019,
        2
    ) AS rate_increase,

    ROUND(
        (
            y2020.mortality_rate_2020 - y2019.mortality_rate_2019
        ) / y2019.mortality_rate_2019 * 100,
        2
    ) AS pct_change

FROM
(
    SELECT
        ag.age_group,
        AVG(f.directly_standardised_rate) AS mortality_rate_2019
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    WHERE d.`Year` = 2019
      AND s.sex = 'Persons'
      AND a.area_name = 'All regions'
      AND ag.age_group <> 'All ages'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY ag.age_group
) AS y2019

INNER JOIN
(
    SELECT
        ag.age_group,
        AVG(f.directly_standardised_rate) AS mortality_rate_2020
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    WHERE d.`Year` = 2020
      AND s.sex = 'Persons'
      AND a.area_name = 'All regions'
      AND ag.age_group <> 'All ages'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY ag.age_group
) AS y2020

ON y2019.age_group = y2020.age_group

ORDER BY pct_change DESC;

==============================================================
-which regions experienced the largest increase in mortality rate from 2019 to 2020?
========================================================= 
SELECT
    y2019.area_name,

    ROUND(y2019.mortality_rate_2019, 2)
        AS mortality_rate_2019,

    ROUND(y2020.mortality_rate_2020, 2)
        AS mortality_rate_2020,

    ROUND(
        y2020.mortality_rate_2020 -
        y2019.mortality_rate_2019,
        2
    ) AS rate_increase,

    ROUND(
        (
            y2020.mortality_rate_2020 -
            y2019.mortality_rate_2019
        )
        / y2019.mortality_rate_2019 * 100,
        2
    ) AS pct_change

FROM
(
    SELECT
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS mortality_rate_2019
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2019
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY a.area_name
) AS y2019

INNER JOIN
(
    SELECT
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS mortality_rate_2020
    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2020
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY a.area_name
) AS y2020

ON y2019.area_name = y2020.area_name

ORDER BY pct_change DESC;
-- =================================================================
#Which months tend to have the highest mortality rates?
-- =================================================================
SELECT
    d.month_number,
    d.month_name,
    ROUND(AVG(f.directly_standardised_rate), 2)
        AS avg_mortality_rate,
    SUM(f.registered_deaths) AS total_registered_deaths

FROM fact_mortality AS f

INNER JOIN dim_date AS d
    ON f.date_key = d.date_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE s.sex = 'Persons'
  AND ag.age_group = 'All ages'
  AND a.area_name = 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY
    d.month_number,
    d.month_name

ORDER BY
    d.month_number;
-- =========================================================
    # investigate 2020 specifically
-- =========================================================
    SELECT
    d.month_number,
    d.month_name,
    SUM(f.registered_deaths) AS total_deaths,
    ROUND(AVG(f.directly_standardised_rate), 2)
        AS avg_mortality_rate

FROM fact_mortality AS f

INNER JOIN dim_date AS d
    ON f.date_key = d.date_key

INNER JOIN dim_area AS a
    ON f.area_key = a.area_key

INNER JOIN dim_sex AS s
    ON f.sex_key = s.sex_key

INNER JOIN dim_age_group AS ag
    ON f.age_group_key = ag.age_group_key

WHERE d.`Year` = 2020
  AND s.sex = 'Persons'
  AND ag.age_group = 'All ages'
  AND a.area_name = 'All regions'
  AND f.directly_standardised_rate IS NOT NULL

GROUP BY
    d.month_number,
    d.month_name

ORDER BY
    d.month_number;
-- =========================================================
    # How abnormal was April 2020 compared with the same month before the pandemic-era spike?
-- =========================================================

    SELECT
    y2019.month_name,

    y2019.total_deaths AS deaths_2019,
    y2020.total_deaths AS deaths_2020,

    y2020.total_deaths - y2019.total_deaths
        AS increase_in_deaths,

    ROUND(
        ((y2020.total_deaths - y2019.total_deaths)
        / y2019.total_deaths) * 100,
        2
    ) AS deaths_pct_change,

    ROUND(y2019.mortality_rate, 2)
        AS mortality_rate_2019,

    ROUND(y2020.mortality_rate, 2)
        AS mortality_rate_2020,

    ROUND(
        y2020.mortality_rate - y2019.mortality_rate,
        2
    ) AS rate_increase,

    ROUND(
        ((y2020.mortality_rate - y2019.mortality_rate)
        / y2019.mortality_rate) * 100,
        2
    ) AS rate_pct_change

FROM
(
    SELECT
        d.month_name,
        SUM(f.registered_deaths) AS total_deaths,
        AVG(f.directly_standardised_rate) AS mortality_rate

    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2019
      AND d.month_number = 4
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name = 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY d.month_name
) AS y2019

INNER JOIN
(
    SELECT
        d.month_name,
        SUM(f.registered_deaths) AS total_deaths,
        AVG(f.directly_standardised_rate) AS mortality_rate

    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key
    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key
    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key
    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE d.`Year` = 2020
      AND d.month_number = 4
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name = 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY d.month_name
) AS y2020

ON y2019.month_name = y2020.month_name;

-- ================================================================
-- Did mortality recover after 2020?
-- ================================================================
SELECT
    y2019.mortality_rate AS mortality_rate_2019,
    y2020.mortality_rate AS mortality_rate_2020,
    y2025.mortality_rate AS mortality_rate_2025,

    ROUND(
        ((y2020.mortality_rate - y2019.mortality_rate)
        / y2019.mortality_rate) * 100,
        2
    ) AS change_2019_to_2020_pct,

    ROUND(
        ((y2025.mortality_rate - y2020.mortality_rate)
        / y2020.mortality_rate) * 100,
        2
    ) AS change_2020_to_2025_pct,

    ROUND(
        ((y2025.mortality_rate - y2019.mortality_rate)
        / y2019.mortality_rate) * 100,
        2
    ) AS change_2019_to_2025_pct

FROM
(
    SELECT ROUND(AVG(f.directly_standardised_rate), 2) AS mortality_rate
    FROM fact_mortality f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_area a ON f.area_key = a.area_key
    JOIN dim_sex s ON f.sex_key = s.sex_key
    JOIN dim_age_group ag ON f.age_group_key = ag.age_group_key
    WHERE d.`Year` = 2019
      AND a.area_name = 'All regions'
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
) y2019

CROSS JOIN
(
    SELECT ROUND(AVG(f.directly_standardised_rate), 2) AS mortality_rate
    FROM fact_mortality f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_area a ON f.area_key = a.area_key
    JOIN dim_sex s ON f.sex_key = s.sex_key
    JOIN dim_age_group ag ON f.age_group_key = ag.age_group_key
    WHERE d.`Year` = 2020
      AND a.area_name = 'All regions'
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
) y2020

CROSS JOIN
(
    SELECT ROUND(AVG(f.directly_standardised_rate), 2) AS mortality_rate
    FROM fact_mortality f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_area a ON f.area_key = a.area_key
    JOIN dim_sex s ON f.sex_key = s.sex_key
    JOIN dim_age_group ag ON f.age_group_key = ag.age_group_key
    WHERE d.`Year` = 2025
      AND a.area_name = 'All regions'
      AND s.sex = 'Persons'
      AND ag.age_group = 'All ages'
) y2025;
-- ========================================================   

-- =========================================================

SELECT
    yearly.mortality_year,

    ROUND(MAX(yearly.avg_mortality_rate), 2)
        AS highest_regional_rate,

    ROUND(MIN(yearly.avg_mortality_rate), 2)
        AS lowest_regional_rate,

    ROUND(
        MAX(yearly.avg_mortality_rate) -
        MIN(yearly.avg_mortality_rate),
        2
    ) AS mortality_gap,

    ROUND(
        (
            MAX(yearly.avg_mortality_rate) -
            MIN(yearly.avg_mortality_rate)
        )
        / MIN(yearly.avg_mortality_rate) * 100,
        2
    ) AS gap_pct

FROM
(
    SELECT
        d.`Year` AS mortality_year,
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS avg_mortality_rate

    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY
        d.`Year`,
        a.area_name
) AS yearly

GROUP BY yearly.mortality_year

ORDER BY yearly.mortality_year;
-- =============================================================
-- Did the regional mortality gap narrow or widen?
-- =============================================================

SELECT
    yearly.mortality_year,

    ROUND(MAX(yearly.avg_mortality_rate), 2)
        AS highest_regional_rate,

    ROUND(MIN(yearly.avg_mortality_rate), 2)
        AS lowest_regional_rate,

    ROUND(
        MAX(yearly.avg_mortality_rate) -
        MIN(yearly.avg_mortality_rate),
        2
    ) AS mortality_gap,

    ROUND(
        (
            MAX(yearly.avg_mortality_rate) -
            MIN(yearly.avg_mortality_rate)
        )
        / MIN(yearly.avg_mortality_rate) * 100,
        2
    ) AS gap_pct

FROM
(
    SELECT
        d.`Year` AS mortality_year,
        a.area_name,
        AVG(f.directly_standardised_rate)
            AS avg_mortality_rate

    FROM fact_mortality AS f

    INNER JOIN dim_date AS d
        ON f.date_key = d.date_key

    INNER JOIN dim_area AS a
        ON f.area_key = a.area_key

    INNER JOIN dim_sex AS s
        ON f.sex_key = s.sex_key

    INNER JOIN dim_age_group AS ag
        ON f.age_group_key = ag.age_group_key

    WHERE s.sex = 'Persons'
      AND ag.age_group = 'All ages'
      AND a.area_name <> 'All regions'
      AND f.directly_standardised_rate IS NOT NULL

    GROUP BY
        d.`Year`,
        a.area_name
) AS yearly

GROUP BY yearly.mortality_year

ORDER BY yearly.mortality_year;