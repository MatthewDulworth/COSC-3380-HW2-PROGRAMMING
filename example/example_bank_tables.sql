-- Drop existing tables in reverse dependency order to allow clean re-runs
DROP TABLE IF EXISTS t2;
DROP TABLE IF EXISTS t1;

-- Create t1 (Accounts table) with k1 as the primary key
CREATE TABLE t1 (
    k1 INTEGER PRIMARY KEY,
    a DECIMAL(10,2) NOT NULL,
    b INTEGER
);

-- Create t2 (Transaction table) with referential integrity pointing to t1(k1)
CREATE TABLE t2 (
    tx_id SERIAL PRIMARY KEY,
    account_id INTEGER REFERENCES t1(k1),
    amount DECIMAL(10,2) NOT NULL,
    tx_type VARCHAR(10) NOT NULL,
    tx_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Populate t1 with the requested initial state
INSERT INTO t1 (k1, a, b) VALUES 
    (1, 10.00, 1),
    (2, 20.00, 123),
    (3, 20.00, 123),
    (4, 40.00, 77),
    (5, 40.00, 77);