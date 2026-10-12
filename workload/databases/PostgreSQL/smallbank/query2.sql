SELECT a.custid, c.bal
FROM ACCOUNTS a LEFT JOIN CHECKING c ON c.custid = a.custid
WHERE a.custid IN (100, 200);
