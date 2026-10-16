------------ Tax ------------
CREATE TABLE tax (
    state_code char(2) PRIMARY KEY,
    tax_rate NUMERIC(5,4) NOT NULL
        CHECK (tax_rate BETWEEN 0 and 1)
);

------------ Department ------------
CREATE TABLE department (
    department_id INT PRIMARY KEY,

    name VARCHAR(60) NOT NULL
);

------------ Store ------------
CREATE TABLE store (
    store_id INT PRIMARY KEY,

    city VARCHAR(60) NOT NULL,
    street VARCHAR(60) NOT NULL,
    zip_code VARCHAR(60) NOT NULL,

    state_code CHAR(2) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    aisles INT NOT NULL,

    FOREIGN KEY (state_code) REFERENCES tax(state_code)
);

------------ Item ------------
CREATE TABLE item (
    sku CHAR(15) PRIMARY KEY,

    name VARCHAR(60) NOT NULL,
    department_id INT NOT NULL,
    tax_exempt BOOLEAN NOT NULL,
    priced_by_weight BOOLEAN NOT NULL,

    FOREIGN KEY(department_id) REFERENCES department(department_id)
);

------------ Store Transaction ------------ 
CREATE TABLE store_transaction (
    transaction_id SERIAL PRIMARY KEY,

    store_id INT NOT NULL,
    account_id INT
        CHECK((payment_method = 'card') = (account_id IS NOT NULL)),

    date_and_time TIMESTAMP NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,

    payment_method VARCHAR(4) NOT NULL
        CHECK (payment_method IN ('card', 'cash')),

    FOREIGN KEY(store_id) REFERENCES store(store_id)
);

------------ Item Sale ------------
CREATE TABLE item_sale (
    transaction_id INT,
    sku CHAR(15),

    sold_weight NUMERIC(8,3),
    sold_count INT
        CHECK(sold_count > 0),
    sold_price NUMERIC(10,2) NOT NULL,

    PRIMARY KEY (transaction_id, sku),
    FOREIGN KEY (transaction_id) REFERENCES store_transaction(transaction_id),
    FOREIGN KEY (sku) REFERENCES item(sku)
);

------------ Inventory ------------
CREATE TABLE inventory (
    sku CHAR(15),
    store_id INT,

    price NUMERIC(10,2) NOT NULL
        CHECK (price >= 0),
    num_in_stock INT NOT NULL 
        CHECK (num_in_stock >= 0),
    aisle_no INT NOT NULL,

    PRIMARY KEY(sku, store_id),
    FOREIGN KEY (sku) REFERENCES item(sku),
    FOREIGN KEY (store_id) REFERENCES store(store_id)
);
