SELECT DISTINCT a.custid,
    a.name,
    c.bal AS checking_bal,
    (SELECT s1.bal
     FROM SAVINGS s1
     WHERE s1.custid = a.custid) AS savings_bal,
    (SELECT AVG(sa.bal)
     FROM SAVINGS sa) AS global_sav_avg
FROM ACCOUNTS a
JOIN CHECKING c ON c.custid = a.custid
JOIN SAVINGS s ON s.custid = a.custid
JOIN CHECKING c2 ON c2.custid = c.custid
JOIN ACCOUNTS a2 ON a2.custid = a.custid
WHERE c.bal BETWEEN 1000 AND 50000
  AND s.bal BETWEEN 1000 AND 50000
  AND c.bal >= 1000
  AND s.bal <= 50000
  AND c.bal < (
    SELECT s3.bal
    FROM SAVINGS s3
    WHERE s3.custid = a.custid
  )
  AND EXISTS (
    SELECT 1
    FROM SAVINGS sx
    WHERE sx.custid = a.custid
      AND sx.bal BETWEEN 1000 AND 50000
  )
  AND ((c.bal < s.bal AND c.bal >= 1000)
    OR (c.bal < s.bal AND s.bal <= 50000))
ORDER BY checking_bal
LIMIT 100;
