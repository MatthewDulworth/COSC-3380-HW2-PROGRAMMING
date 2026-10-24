const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

// Load DB_* settings from src/.env into process.env
process.loadEnvFile(path.join(__dirname, '.env'));

const app = express();
app.use(express.json());
app.use(cors());

const supermarketPool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_SUPERMARKET,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT,
});

// Configure connection to the separate bank database
const bankPool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_BANK,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT,
});

// ------------------------------------------------------------------------------
// Test Transaction Endpoint
// ------------------------------------------------------------------------------
// Endpoint to test a transaction with 1 item
app.post('/test-transaction', async (req, res) => {
    const { storeId, sku, quantity, paymentMethod, accountId } = req.body;

    // Validate storeId
    if (!Number.isInteger(storeId) || storeId <= 0) {
        return res.status(400).json({ error: 'Invalid store ID' });
    }

    // Validate SKU
    if (typeof sku !== 'string' || !sku.trim()) {
        return res.status(400).json({ error: 'Invalid SKU' });
    }

    // Validate quantity
    if (typeof quantity !== 'number' ||
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        // Reject quantities with more than three decimal places
        Math.abs(quantity * 1000 - Math.round(quantity * 1000)) > 1e-7) {
        return res.status(400).json({ error: 'Invalid quantity' });
    }

    // Validate payment method
    if (paymentMethod !== 'card' && paymentMethod !== 'cash') {
        return res.status(400).json({ error: 'Invalid payment method' });
    }

    if (paymentMethod === 'card' &&
        (!Number.isInteger(accountId) || accountId <= 0)) {
        return res.status(400).json({ error: 'Invalid account ID' });
    }

    let client;
    let bankClient;
    try {
        // Connect to the store database
        client = await supermarketPool.connect();
        await client.query('BEGIN');

        // Connect to the bank database for card payments
        if (paymentMethod === 'card') {
            bankClient = await bankPool.connect();
            await bankClient.query('BEGIN');
        }

        // Retrieve item information, inventory, and tax rate
        const storeResult = await client.query(`
            SELECT
                inv.price,
                inv.quantity_in_stock,
                i.tax_exempt,
                i.priced_by_weight,
                t.tax_rate
            FROM inventory inv
            JOIN item AS i ON inv.sku = i.sku
            JOIN store AS s ON inv.store_id = s.store_id
            JOIN tax AS t ON s.state_code = t.state_code
            WHERE inv.store_id = $1 AND inv.sku = $2
            FOR UPDATE OF inv
        `, [storeId, sku]);

        if (storeResult.rows.length === 0) {
            throw new Error('Item not found in this store');
        }

        const item = storeResult.rows[0];

        // Check that the quantity is appropriate for the item
        if (typeof quantity !== 'number' ||
            !Number.isFinite(quantity) ||
            quantity <= 0 ||
            (!item.priced_by_weight && !Number.isInteger(quantity))) {
            throw new Error('Invalid Item quantity');
        }

        // Prevent purchases exceeding available stock
        if (Number(item.quantity_in_stock) < quantity) {
            throw new Error('Not enough stock available');
        }

        // Calculate total price including applicable sales tax
        const totalResult = await client.query(`
            SELECT ROUND(
                $1::NUMERIC * $2::NUMERIC *
                (1 + CASE WHEN $3::BOOLEAN THEN 0 ELSE $4::NUMERIC END),
                2
            ) AS total
        `, [item.price, quantity, item.tax_exempt, item.tax_rate]);

        // Get the calculated total
        const total = totalResult.rows[0].total;

        // For card payments, subtract the total from the bank balance
        if (paymentMethod === 'card') {
            const bankResult = await bankClient.query(`
                UPDATE account
                SET balance = balance - $1
                WHERE account_number = $2
                  AND balance >= $1
                RETURNING account_number, balance
            `, [total, accountId]);

            if (bankResult.rows.length === 0) {
                throw new Error('Insufficient funds or account not found');
            }
        }

        const account = paymentMethod === 'card' ? accountId : null;

        // Create the supermarket transaction record
        const transactionResult = await client.query(`
            INSERT INTO store_transaction
                (store_id, account_id, total_amount, payment_method)
            VALUES ($1, $2, $3, $4)
            RETURNING transaction_id
        `, [storeId, account, total, paymentMethod]);

        const transactionId = transactionResult.rows[0].transaction_id;

        // Record the specific item purchased
        await client.query(`
            INSERT INTO item_sale
                (transaction_id, sku, quantity_sold, unit_price)
            VALUES ($1, $2, $3, $4)
        `, [transactionId, sku, quantity, item.price]);

        // Subtract purchased quantity from store inventory
        await client.query(`
            UPDATE inventory
            SET quantity_in_stock = quantity_in_stock - $1
            WHERE store_id = $2 AND sku = $3
        `, [quantity, storeId, sku]);

        if (bankClient) {
            await bankClient.query('COMMIT');
        }
        await client.query('COMMIT');

        // Return successful purchase information
        return res.json({
            success: true,
            message: 'Transaction successful',
            transactionId: transactionId,
            total: total,
            paymentMethod: paymentMethod,
        });
    } catch (error) {
        if (client) {
            await client.query('ROLLBACK').catch(console.error);
        }
        if (bankClient) {
            await bankClient.query('ROLLBACK').catch(console.error);
        }

        return res.status(400).json({
            success: false,
            message: error.message,
        });
    } finally {
        if (client) {
            client.release();
        }
        if (bankClient) {
            bankClient.release();
        }
    }
});

// ------------------------------------------------------------------------------
// Reset Endpoint
// ------------------------------------------------------------------------------
app.post('/reset-tables', async (req, res) => {
    try {
        // Reset the supermarket database
        const ddl = fs.readFileSync(path.join(__dirname, '..', 'ddl', 'ddl.sql'), 'utf8');
        await supermarketPool.query(ddl);
        console.log('Ran ddl.sql');

        // Get the stores table
        const queryStores = `SELECT * FROM store;`;
        const stores = await supermarketPool.query(queryStores);

        res.json({ 
            success: true, 
            stores: stores.rows, 
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// ------------------------------------------------------------------------------
// Inventory Endpoint
// ------------------------------------------------------------------------------
app.post('/inventory', async (req, res) => {
    const { storeID } = req.body;

    try {
        const queryInventory = `
        SELECT *
        FROM inventory 
        JOIN item ON inventory.sku = item.sku
        WHERE store_id=${storeID};
        `;
        const items = await supermarketPool.query(queryInventory);

        res.json({ 
            success: true, 
            items: items.rows, 
        });
    } catch(error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// ------------------------------------------------------------------------------
// Start DB
// ------------------------------------------------------------------------------
app.listen(3000, () => console.log(`Supermarket API running on http://localhost:3000`));
