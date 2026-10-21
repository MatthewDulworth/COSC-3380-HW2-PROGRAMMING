------------ Tax ------------
CREATE TABLE tax (
    state_code char(2) PRIMARY KEY,
    tax_rate NUMERIC(5,4) NOT NULL,

    CONSTRAINT tax_rate_0_to_1 CHECK (tax_rate BETWEEN 0 and 1)
);

------------ Department ------------
CREATE TABLE department (
    department_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    name VARCHAR(60) NOT NULL
);

------------ Store ------------
CREATE TABLE store (
    store_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    city VARCHAR(60) NOT NULL,
    street VARCHAR(60) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,

    state_code CHAR(2) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    aisles INT NOT NULL,

    FOREIGN KEY (state_code) REFERENCES tax(state_code)
);

------------ Item ------------
CREATE TABLE item (
    sku VARCHAR(15) PRIMARY KEY,

    name VARCHAR(60) NOT NULL,
    department_id INT NOT NULL,
    tax_exempt BOOLEAN NOT NULL,
    priced_by_weight BOOLEAN NOT NULL,

    FOREIGN KEY(department_id) REFERENCES department(department_id)
);

------------ Store Transaction ------------ 
CREATE TABLE store_transaction (
    transaction_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    store_id INT NOT NULL,
    account_id INT,

    date_and_time TIMESTAMPTZ NOT NULL 
        DEFAULT now(),
    total_amount NUMERIC(10,2) NOT NULL,
    payment_method VARCHAR(4) NOT NULL,

    CONSTRAINT payment_is_card_or_cash CHECK (payment_method IN ('card', 'cash')),
    CONSTRAINT card_must_have_account CHECK((payment_method = 'card') = (account_id IS NOT NULL)),
    CONSTRAINT nonnegative_total_amount CHECK(total_amount >= 0),

    FOREIGN KEY(store_id) REFERENCES store(store_id)
);

------------ Item Sale ------------
CREATE TABLE item_sale (
    transaction_id INT,
    sku VARCHAR(15),

    sold_weight NUMERIC(8,3),
    sold_count INT,
    sold_price NUMERIC(10,2) NOT NULL,

    CONSTRAINT positive_sold_count CHECK(sold_count > 0),
    CONSTRAINT nonnegative_sold_price CHECK(sold_price >= 0),
    CONSTRAINT weight_xor_count CHECK ((sold_weight IS NULL) <> (sold_count IS NULL)),
    CONSTRAINT positive_sold_weight CHECK (sold_weight > 0),

    PRIMARY KEY (transaction_id, sku),
    FOREIGN KEY (transaction_id) REFERENCES store_transaction(transaction_id),
    FOREIGN KEY (sku) REFERENCES item(sku)
);

------------ Inventory ------------
CREATE TABLE inventory (
    sku VARCHAR(15),
    store_id INT,

    price NUMERIC(10,2) NOT NULL,
    num_in_stock INT NOT NULL,
    aisle_no INT NOT NULL,

    CONSTRAINT positive_aisle_no CHECK (aisle_no >= 1),
    CONSTRAINT nonnegative_price CHECK (price >= 0),
    CONSTRAINT nonnegative_stock CHECK (num_in_stock >= 0),

    PRIMARY KEY(sku, store_id),
    FOREIGN KEY (sku) REFERENCES item(sku),
    FOREIGN KEY (store_id) REFERENCES store(store_id)
);
