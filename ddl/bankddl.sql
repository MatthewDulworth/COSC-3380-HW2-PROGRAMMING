
-- Create the bank account table
CREATE TABLE account (
    account_number INTEGER PRIMARY KEY,
    balance NUMERIC(12,2) NOT NULL,

    -- An account cannot have a negative balance
    CONSTRAINT nonnegative_balance CHECK (balance >= 0)
);
SELECT * FROM account;