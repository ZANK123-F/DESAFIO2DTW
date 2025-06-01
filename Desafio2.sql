SELECT TOP 100000 * 
FROM [dbo].[InformeMovilidadLocal2020]
ORDER BY [date];  


-- CREAMOS UNA NUEVA TABLA PARA UNIFICAR LOS 3 AÑOS
SELECT *
INTO dbo.InformeMovilidadLocal
FROM (
    SELECT * FROM [dbo].[InformeMovilidadLocal2020]
    UNION ALL
    SELECT * FROM [dbo].[InformeMovilidadLocal2021]
    UNION ALL
    SELECT * FROM [dbo].[InformeMovilidadLocal2022]
) AS Combined;


-- CIMPROBAMOS QUE ESTEN LOS AÑOS 2020.2021.2022
SELECT YEAR([date]) AS Año, COUNT(*) AS Nfilas
FROM dbo.InformeMovilidadLocal
GROUP BY YEAR([date])
ORDER BY Año;


--creamos una nueva tabla llamada 
CREATE TABLE dbo.DimDate
(
    date_key     INT        NOT NULL PRIMARY KEY,  
    full_date    DATE       NOT NULL,
    year_num     SMALLINT   NOT NULL,
    quarter_num  TINYINT    NOT NULL,
    month_num    TINYINT    NOT NULL,
    day_num      TINYINT    NOT NULL,
    day_name     VARCHAR(10)NOT NULL,              
    is_weekend   BIT        NOT NULL
);
--insertamos data 
INSERT INTO dbo.DimDate
    (date_key, full_date, year_num, quarter_num, month_num, day_num, day_name, is_weekend)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), [date], 112)) AS date_key,
    [date]                                  AS full_date,
    YEAR([date])                            AS year_num,
    DATEPART(QUARTER, [date])               AS quarter_num,
    MONTH([date])                           AS month_num,
    DAY([date])                             AS day_num,
    DATENAME(WEEKDAY, [date])               AS day_name,
    CASE WHEN DATENAME(WEEKDAY, [date]) IN ('Saturday','Sunday') THEN 1 ELSE 0 END AS is_weekend
FROM
    (SELECT DISTINCT [date] FROM dbo.InformeMovilidadLocal) AS U
ORDER BY [date];
GO

--ahora hacemos una consulata de verificacion

SELECT COUNT(*) AS TotalFechas FROM dbo.DimDate;  
SELECT TOP 5 * FROM dbo.DimDate ORDER BY date_key;
GO


--ahora creamos una nueva tabla 
CREATE TABLE dbo.DimRegion
(
    region_key   INT         IDENTITY(1,1) PRIMARY KEY,
    country_name VARCHAR(100) NOT NULL,    
    subregion_l1 VARCHAR(100) NULL,        
    region_type  VARCHAR(20)  NOT NULL     
);
GO

--ahora poblamos la tabla
INSERT INTO dbo.DimRegion (country_name, subregion_l1, region_type)
SELECT
    country_region AS country_name,
    NULLIF(sub_region_1, '') AS subregion_l1,
    CASE 
        WHEN sub_region_1 = '' OR sub_region_1 IS NULL THEN 'Country' 
        ELSE 'Department' 
    END AS region_type
FROM
    (SELECT DISTINCT country_region, sub_region_1
     FROM dbo.InformeMovilidadLocal) AS U;
GO


--ahora verificamos la data de el pais  y los departamentos
SELECT region_type, COUNT(*) AS Cantidad
FROM dbo.DimRegion
GROUP BY region_type;

SELECT region_key, country_name, subregion_l1, region_type
FROM dbo.DimRegion
ORDER BY region_type DESC, subregion_l1;
GO


--ahora creamos otra tabla 
CREATE TABLE dbo.FactMobility
(
    fact_id                    BIGINT     IDENTITY(1,1) PRIMARY KEY,
    date_key                   INT        NOT NULL,  
    region_key                 INT        NOT NULL,  
    retail_and_recreation_pct  SMALLINT   NULL,
    grocery_and_pharmacy_pct   SMALLINT   NULL,
    parks_pct                  SMALLINT   NULL,
    transit_stations_pct       SMALLINT   NULL,
    workplaces_pct             SMALLINT   NULL,
    residential_pct            SMALLINT   NULL,
    CONSTRAINT FK_FM_DimDate   FOREIGN KEY(date_key)   REFERENCES dbo.DimDate(date_key),
    CONSTRAINT FK_FM_DimRegion FOREIGN KEY(region_key) REFERENCES dbo.DimRegion(region_key)
);
GO

INSERT INTO dbo.FactMobility
(
    date_key, region_key,
    retail_and_recreation_pct,
    grocery_and_pharmacy_pct,
    parks_pct,
    transit_stations_pct,
    workplaces_pct,
    residential_pct
)
SELECT
    D.date_key,
    R.region_key,
    S.retail_and_recreation_percent_change_from_baseline,
    S.grocery_and_pharmacy_percent_change_from_baseline,
    S.parks_percent_change_from_baseline,
    S.transit_stations_percent_change_from_baseline,
    S.workplaces_percent_change_from_baseline,
    S.residential_percent_change_from_baseline
FROM dbo.InformeMovilidadLocal AS S
    JOIN dbo.DimDate   AS D ON D.full_date = S.[date]
    JOIN dbo.DimRegion AS R
      ON R.country_name = S.country_region
     AND (
         (S.sub_region_1 = '' OR S.sub_region_1 IS NULL) AND R.subregion_l1 IS NULL
         OR
         (R.subregion_l1 = S.sub_region_1)
        );
GO

--ahora con esta consulta vamos a verificar la suma de todas las filas de los 3 años 
SELECT COUNT(*) AS total FROM dbo.FactMobility;  
SELECT TOP 25 FM.fact_id, D.full_date, R.subregion_l1, FM.workplaces_pct, FM.residential_pct
FROM dbo.FactMobility FM
 JOIN dbo.DimDate D ON FM.date_key = D.date_key
 JOIN dbo.DimRegion R ON FM.region_key = R.region_key
ORDER BY D.full_date, R.subregion_l1;
GO



--CONSULTA PARA VALIDAR SI DIMREGION TIENE COUNTRY (EL SALVADOR Y NUESTROS DEPARTAMENTOS)
SELECT region_type, COUNT(*) AS Cantidad
FROM dbo.DimRegion
GROUP BY region_type;
GO
SELECT region_key, country_name, subregion_l1, region_type
FROM dbo.DimRegion
ORDER BY region_type DESC, subregion_l1;
GO

SELECT MIN(full_date) AS FechaMin, MAX(full_date) AS FechaMax, COUNT(*) AS TotalFechas
FROM dbo.DimDate;
GO



--Evolución mensual de “workplaces_pct” a nivel nacional durante 2020
--¿En qué mes se dio la mayor caída?
--¿Cuándo empezó a recuperarse?


SELECT
    D.month_num                                                      AS Mes,
    ROUND(AVG(FM.workplaces_pct * 1.0), 2)                            AS PromedioWorkplacesPct,
   
    MIN(FM.workplaces_pct)                                            AS ValorMinimoMensual,
    MAX(FM.workplaces_pct)                                            AS ValorMaximoMensual
FROM dbo.FactMobility AS FM
JOIN dbo.DimDate AS D      ON FM.date_key   = D.date_key
JOIN dbo.DimRegion AS R    ON FM.region_key = R.region_key
WHERE
    R.region_type = 'Country'      
    AND D.year_num = 2020
GROUP BY
    D.month_num
ORDER BY
    D.month_num;
GO





--Caída más fuerte en “Retail & Recreation” por departamento en 2020
--¿Qué departamento cayó más?
--¿En qué fecha exacta registró su mínimo?
--USE DESAFIO2;
--GO

--WITH DeptRetail2020 AS
--(
--    SELECT
--        R.subregion_l1                         AS Departamento,
--        FM.retail_and_recreation_pct           AS RetailPct,
--        D.full_date                            AS Fecha
--    FROM dbo.FactMobility AS FM
--    JOIN dbo.DimDate   AS D ON FM.date_key   = D.date_key
--    JOIN dbo.DimRegion AS R ON FM.region_key = R.region_key
--    WHERE
--        R.region_type = 'Department'
--        AND D.year_num = 2020
--)
--SELECT
--    DR.Departamento,
--    MIN(DR.RetailPct)                                               AS ValorMinimo,
--    MIN(CASE 
--           WHEN DR.RetailPct = (SELECT MIN(RetailPct)
--                                FROM DeptRetail2020 AS X
--                                WHERE X.Departamento = DR.Departamento)
--           THEN DR.Fecha
--        END)                                                      AS FechaMinima
--FROM DeptRetail2020 AS DR
--GROUP BY DR.Departamento
--ORDER BY ValorMinimo ASC;
--GO






-- Relación diaria entre “Grocery & Pharmacy” y “Residential” a nivel país durante marzo–diciembre 2020
-- Cuando los supermercados bajaban, ¿las residencias subían?
--¿En qué picos se nota la mayor inversa?



SELECT
    D.full_date                                            AS Fecha,
    FM.grocery_and_pharmacy_pct                            AS GroceryPct,
    FM.residential_pct                                     AS ResidentialPct
FROM dbo.FactMobility AS FM
JOIN dbo.DimDate AS D      ON FM.date_key   = D.date_key
JOIN dbo.DimRegion AS R    ON FM.region_key = R.region_key
WHERE
    R.region_type = 'Country'       -- Solo nivel nacional
    AND D.full_date BETWEEN '2020-03-01' AND '2020-12-31'
ORDER BY
    D.full_date;
GO

SELECT
    D.full_date                                           AS Fecha,
    FM.parks_pct                                          AS ParksPct,
    FM.transit_stations_pct                               AS TransitPct
FROM dbo.FactMobility AS FM
JOIN dbo.DimDate     AS D ON FM.date_key = D.date_key
JOIN dbo.DimRegion   AS R ON FM.region_key = R.region_key
WHERE
    R.subregion_l1 = 'San Salvador Department'
    AND D.year_num = 2020
ORDER BY
    D.full_date;
GO


--Recuperación en 2021 y 2022: ¿En qué meses la movilidad volvió a valores cercanos a 0 %?
--¿Por departamento, qué área (Workplaces o Retail) se recuperó primero?





SELECT
    D.year_num                                       AS Año,
    D.month_num                                      AS Mes,
    ROUND(AVG(FM.workplaces_pct * 1.0), 2)            AS PromedioWorkplacesPct
FROM dbo.FactMobility AS FM
JOIN dbo.DimDate AS D      ON FM.date_key   = D.date_key
JOIN dbo.DimRegion AS R    ON FM.region_key = R.region_key
WHERE
    R.region_type = 'Country'
    AND D.year_num IN (2021, 2022)
GROUP BY
    D.year_num,
    D.month_num
ORDER BY
    D.year_num,
    D.month_num;
GO


--Mes donde “retail_and_recreation_pct” se acercó primero a 0 % por departamento (2021‐2022)
WITH DeptRetail AS
(
    SELECT
        R.subregion_l1                         AS Departamento,
        D.year_num                             AS Año,
        D.month_num                            AS Mes,
        ROUND(AVG(FM.retail_and_recreation_pct * 1.0), 2) AS PromedioRetailPct
    FROM dbo.FactMobility AS FM
    JOIN dbo.DimDate   AS D ON FM.date_key = D.date_key
    JOIN dbo.DimRegion AS R ON FM.region_key = R.region_key
    WHERE
        R.region_type = 'Department'
        AND D.year_num IN (2021, 2022)
    GROUP BY
        R.subregion_l1,
        D.year_num,
        D.month_num
)
-- Ahora, para cada Departamento, buscamos el “primer mes” donde PromedioRetailPct se acerca a 0 (mayor valor, menos negativo)
SELECT
    DR.Departamento,
    DR.Año,
    DR.Mes,
    DR.PromedioRetailPct
FROM
(
    SELECT
        Departamento,
        Año,
        Mes,
        PromedioRetailPct,
        ROW_NUMBER() OVER (PARTITION BY Departamento ORDER BY ABS(PromedioRetailPct) ASC) AS RN
    FROM DeptRetail
) AS DR
WHERE
    DR.RN = 1
ORDER BY
    DR.Departamento;
GO

--Mes donde “workplaces_pct” se recuperó antes que “retail” por departamento (2021‐2022)


WITH DeptMetrics AS
(
    SELECT
        R.subregion_l1                         AS Departamento,
        D.year_num                             AS Año,
        D.month_num                            AS Mes,
        ROUND(AVG(FM.workplaces_pct * 1.0), 2)            AS PromedioWorkplacesPct,
        ROUND(AVG(FM.retail_and_recreation_pct * 1.0), 2)  AS PromedioRetailPct
    FROM dbo.FactMobility AS FM
    JOIN dbo.DimDate   AS D ON FM.date_key = D.date_key
    JOIN dbo.DimRegion AS R ON FM.region_key = R.region_key
    WHERE
        R.region_type = 'Department'
        AND D.year_num IN (2021, 2022)
    GROUP BY
        R.subregion_l1,
        D.year_num,
        D.month_num
),
RankedWork AS
(
    SELECT
        Departamento,
        Año,
        Mes,
        PromedioWorkplacesPct,
        ROW_NUMBER() OVER (PARTITION BY Departamento ORDER BY ABS(PromedioWorkplacesPct) ASC) AS RN_Work
    FROM DeptMetrics
),
RankedRetail AS
(
    SELECT
        Departamento,
        Año,
        Mes,
        PromedioRetailPct,
        ROW_NUMBER() OVER (PARTITION BY Departamento ORDER BY ABS(PromedioRetailPct) ASC) AS RN_Retail
    FROM DeptMetrics
)
SELECT
    W.Departamento,
    W.Año       AS Año_Work,
    W.Mes       AS Mes_Work,
    W.PromedioWorkplacesPct,
    R.Año       AS Año_Retail,
    R.Mes       AS Mes_Retail,
    R.PromedioRetailPct
FROM RankedWork AS W
JOIN RankedRetail AS R
    ON W.Departamento = R.Departamento
WHERE
    W.RN_Work = 1  
    AND R.RN_Retail = 1 
ORDER BY
    W.Departamento;
GO
