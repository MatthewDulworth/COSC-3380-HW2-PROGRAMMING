DROP TABLE T_trans;
DROP TABLE C_trans;

/* CREATE TABLE T_trans(i int,primary key(i)); */ /* naturals */


CREATE TABLE T_trans(i int,primary key(i)); /* naturals */
CREATE TABLE C_trans(i int,primary key(i)); /* counts */
DELETE FROM C_trans;
INSERT INTO C_trans VALUES(0);

/* 
iterate this transaction
keep a counter of naturals inserted 
*/
DELETE FROM T_trans;
START TRANSACTION; /* { */

 INSERT INTO T_trans
 SELECT C_trans.i+1
 FROM C_trans;

 UPDATE C_trans
 SET i=i+1;
 COMMIT;  
END TRANSACTION;

