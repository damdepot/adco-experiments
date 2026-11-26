SELECT a.custid, s.bal FROM ACCOUNTS a JOIN SAVINGS s ON a.custid = s.custid WHERE a.custid = 100 FOR UPDATE;
