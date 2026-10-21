// This program works from the command line
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Configure local PostgreSQL connection
const pool = new Pool({
    user: 'mdulworth',
    host: 'localhost',
    database: 'hw2-bank-example',
    password: '', 
    port: 5432,
});

// Customer Side: Asynchronous endpoint to process a bank transaction
app.post('/simulate-transaction', async (req, res) => {
    const { fromAccountId, toAccountId, amountString } = req.body;
    const client = await pool.connect();

    // All transaction statements are inside one block and sent as one string[cite: 2, 4]
    // Money is withdrawn from one account and added to another
    // Recording a transaction instead of logging
    const transactionSQL = `
    START TRANSACTION;
    UPDATE t1 SET a = a - ${amountString} WHERE k1 = ${fromAccountId};
    UPDATE t1 SET a = a + ${amountString} WHERE k1 = ${toAccountId};
    INSERT INTO t2 (account_id, amount, tx_type) VALUES (${fromAccountId}, ${amountString}, 'WITHDRAWAL');
    INSERT INTO t2 (account_id, amount, tx_type) VALUES (${toAccountId}, ${amountString}, 'DEPOSIT');
    END;
    `;

    try {
        await client.query(transactionSQL);
        res.json({ 
            success: true, 
            message: `Transaction successful: Withdrew $${amountString} from Account ${fromAccountId} and deposited to Account ${toAccountId}.`
        });
    } catch (error) {
        console.error('Transaction failed:', error);
        res.status(500).json({ success: false, message: error.message });
    } finally {
        client.release();
    }
});

// Company Side: Endpoint to fetch back-office administrative records
app.get('/company-records', async (req, res) => {
    try {
        const accountsRes = await pool.query('SELECT k1, a, b FROM t1 ORDER BY k1 ASC');
        const transactionsRes = await pool.query('SELECT tx_id, account_id, amount, tx_type, tx_timestamp FROM t2 ORDER BY tx_timestamp DESC LIMIT 50');
        res.json({ 
            success: true, 
            accounts: accountsRes.rows, 
            transactions: transactionsRes.rows 
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

app.listen(3000, () => console.log('Bank App API running on http://localhost:3000'));