/* 
 author: Carlos
 file: hw3-trans-transfer
 
 transfer
 delete from table T_1 and insert into T_2
 row by row
 keep pk to transfer updated
 count transfers
*/
CREATE TABLE C_transfer(i int,transfers int);
INSERT INTO C_transfer VALUES(1,0);

CREATE TABLE T_1(i int,j int,v real,primary key(i));
CREATE TABLE T_2(i int,j int,v real,primary key(i));

\set ON_ERROR_ROLLBACK=on
/* reset */
UPDATE C_transfer SET i=1,transfers=0;

DELETE FROM T_1;
INSERT INTO T_1 VALUES(3,3,10);
INSERT INTO T_1 VALUES(1,1,100);
INSERT INTO T_1 VALUES(2,2,100);
INSERT INTO T_1 VALUES(20,2,10);
INSERT INTO T_1 VALUES(30,1,100);
INSERT INTO T_1 VALUES(15,1,100);
DELETE FROM T_2;


# repeat this transaction on multiple threads
START TRANSACTION;`
 /* choose i randomly from existing rows */
 UPDATE C_transfer  
 /* SET i=(select i from t_1 limit 1); not random */
 SET i=(SELECT i 
        FROM (SELECT i,random() AS r 
              FROM t_1 
              ORDER BY r limit 1)t_r
        );

 /* abort if i does not exist */
 INSERT INTO T_2
 SELECT T_1.i,T_1.j,T_1.v
 FROM T_1 RIGHT JOIN C_transfer ON T_1.i= C_transfer.i; 
/* FROM T_1 RIGHT JOIN C_transfer ON T_1.i=100; */ /* bad key */

 DELETE FROM T_1
 WHERE T_1.i = (SELECT i FROM C_transfer);

 UPDATE C_transfer  
 SET transfers=transfers+1;
 
 COMMIT;
END TRANSACTION;
 
