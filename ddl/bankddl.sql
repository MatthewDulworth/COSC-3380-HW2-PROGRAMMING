
CREATE TABLE account (
    account_number INTEGER PRIMARY KEY,
    balance NUMERIC(12,2) NOT NULL,

    CONSTRAINT nonnegative_balance CHECK (balance >= 0)
);
SELECT * FROM account;
