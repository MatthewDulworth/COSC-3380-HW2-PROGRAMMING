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
// Endpoint to test a transaction with more than 1 item
app.post('/test-transaction', async (req, res) => {
    const { storeId, items, paymentMethod, accountId } = req.body;

    // Validate storeId
    if (!Number.isInteger(storeId) || storeId <= 0) {
        return res.status(400).json({ error: 'Invalid store ID' });
    }

    // Validate Items
    if (!Array.isArray(items) || items.length === 0){
        return res.status(400).json({ error: 'Invalid item array' });
    }


    // Sku into array
    const combinedItems = new Map();

    for (const purchasedItem of items) {
        if (!purchasedItem || 
            typeof purchasedItem.sku !== 'string' ||
            !purchasedItem.sku.trim()) {
            return res.status(400).json({ error: 'Invalid SKU' });
        }


        const quantity = purchasedItem.quantity;

        if (typeof quantity !== 'number' ||
            !Number.isFinite(quantity) ||
            quantity <= 0 ||
            Math.abs(quantity * 1000 - Math.round(quantity * 1000)) > 1e-7) {
            return res.status(400).json({ error: 'Invalid quantity'  });
        }

        const sku = purchasedItem.sku.trim()

        const quantityUnits = Math.round(quantity * 1000);

        if (!Number.isSafeInteger(quantityUnits) ||
            quantityUnits <= 0) {
            return res.status(400).json({ error: 'Invalid quantity' });
            
        }
        
        const previousUnits = combinedItems.get(sku) || 0;
        const newUnits = previousUnits + quantityUnits;
        
        if(!Number.isSafeInteger(newUnits)){
            return res.status(400).json({ error: 'Quantity too large' })
        }

        combinedItems.set(sku, newUnits);
    } 

    // Validate payment method
    if (paymentMethod !== 'card' && paymentMethod !== 'cash') {
        return res.status(400).json({ error: 'Invalid payment method' });
    }

    if (paymentMethod === 'card' &&
        (!Number.isInteger(accountId) || accountId <= 0)) {
        return res.status(400).json({ error: 'Invalid account ID' });
    }

    const cart = Array.from(combinedItems, ([sku, units]) => ({
        sku,
        quantity: units / 1000
    })).sort((a,b) => a.sku < b.sku ? -1 : a.sku > b.sku ? 1 : 0);

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


        const validatedItems = [];
        const lineTotals = [];


       for (const purchasedItem of cart) {
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
        `, [storeId, purchasedItem.sku]);

            if (storeResult.rows.length === 0) {
                throw new Error(
                    `Item ${purchasedItem.sku} not found in this store`);
            }

            const item = storeResult.rows[0];

            // Check weight based items
            if (!item.priced_by_weight &&
                !Number.isInteger(purchasedItem.quantity)) {
                throw new Error(
                    `Invalid quantity for ${purchasedItem.sku}`);
            }

            // Prevent purchases exceeding available stock
            if (Number(item.quantity_in_stock) < purchasedItem.quantity) {
                throw new Error(
                    `Not enough stock for ${purchasedItem.sku}`);
            }

            // Calculate total price including applicable sales tax
            const lineResult = await client.query(`
            SELECT ROUND(
                $1::NUMERIC * $2::NUMERIC *
                (1 + CASE WHEN $3::BOOLEAN THEN 0 ELSE $4::NUMERIC END),
                2
            ) AS line_total
        `, [item.price, purchasedItem.quantity, item.tax_exempt, item.tax_rate]);

            // Save calculated total
            lineTotals.push(lineResult.rows[0].line_total);

            //
            validatedItems.push({
                sku: purchasedItem.sku,
                quantity: purchasedItem.quantity,
                price: item.price
            });
        }

        // Add lines totals
        const totalResult = await client.query(`
            SELECT COALESCE(
                SUM(amount),
                0
            ) AS total
            FROM UNNEST($1::NUMERIC[]) AS amounts(amount)
            `, [lineTotals]);
        
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

        for (const purchasedItem of validatedItems) {
            // Record the specific item purchased
            await client.query(`
                INSERT INTO item_sale
                    (transaction_id, sku, quantity_sold, unit_price)
                VALUES ($1, $2, $3, $4)
            `, [transactionId, purchasedItem.sku, purchasedItem.quantity, purchasedItem.price]);
            
            // Subtract purchased quantity from store inventory
            await client.query(`
                UPDATE inventory
                SET quantity_in_stock = quantity_in_stock - $1
                WHERE store_id = $2 AND sku = $3
            `, [purchasedItem.quantity, storeId, purchasedItem.sku]);
        }

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

        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// ------------------------------------------------------------------------------
// Stores Endpoint
// ------------------------------------------------------------------------------
app.post('/stores', async (req, res) => {
    try {
        // Get the stores table
        const queryStores = `SELECT * FROM store ORDER BY store_id;`;
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
// Bank Reset Endpoint
// ------------------------------------------------------------------------------
app.post('/reset-bank', async (req, res) => {
    try {
        // Reset the bank database
        const ddl = fs.readFileSync(path.join(__dirname, '..', 'ddl', 'bankddl.sql'), 'utf8');
        await bankPool.query(ddl);
        console.log('Ran bankddl.sql');

        const queryAccounts = `SELECT count(*)::int AS count FROM account;`;
        const accounts = await bankPool.query(queryAccounts);

        res.json({
            success: true,
            accountCount: accounts.rows[0].count,
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
