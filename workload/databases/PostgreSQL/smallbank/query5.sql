SELECT DISTINCT t.custid, t.name,
    SUM(t.total_bal) AS total_bal,
    AVG(t.sav_bal) AS avg_sav_bal,
    AVG(t.chk_bal) AS avg_chk_bal,
    COUNT(*) AS cnt
FROM (
    SELECT a.custid AS custid,
        a.name AS name,
        SUM(s.bal + c.bal) AS total_bal,
        AVG(s.bal) AS sav_bal,
        AVG(c.bal) AS chk_bal,
        (SELECT SUM(s2.bal + c2.bal)
         FROM SAVINGS s2
         JOIN CHECKING c2 ON c2.custid = s2.custid
         WHERE s2.custid = a.custid) AS verify_total
    FROM ACCOUNTS a
    JOIN SAVINGS s ON s.custid = a.custid
    JOIN CHECKING c ON c.custid = a.custid
    JOIN ACCOUNTS a2 ON a2.custid = a.custid
    WHERE s.bal BETWEEN 1000 AND 50000
      AND c.bal BETWEEN 1000 AND 50000
      AND s.bal >= 1000
      AND s.bal <= 50000
      AND c.bal >= 1000
      AND c.bal <= 50000
      AND a.custid IN (
        SELECT s3.custid
        FROM SAVINGS s3
        WHERE s3.bal BETWEEN 1000 AND 50000
    )
    GROUP BY a.custid, a.name
) AS t
GROUP BY t.custid, t.name
HAVING SUM(t.total_bal) > 2000;
