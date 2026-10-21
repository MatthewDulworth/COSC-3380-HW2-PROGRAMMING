
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const pool = new Pool({
    user: USER,
    host: HOST,
    database: DATABASE,
    password: PASSWORD, 
    port: PORT,
});

app.listen(PORT, () => console.log('Supermarket API running on http://localhost:3000'));