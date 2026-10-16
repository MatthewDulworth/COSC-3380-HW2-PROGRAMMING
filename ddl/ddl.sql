-- My section 

CREATE TABLE item_sale (

    transaction_id INT,
    sku CHAR(15),

    sold_weight FLOAT NOT NULL, 
    sold_count INT NOT NULL,
    sold_price FLOAT NOT NULL,

    PRIMARY KEY (transaction_id, sku)
);

CREATE TABLE store_transaction (
    transaction_id INT PRIMARY KEY,

    store_id INT NOT NULL REFERENCES store(store_id),

    account_id INT,
    date_and_time DATETIME NOT NULL,
    total_amount FLOAT NOT NULL,

    payment_method VARCHAR(4) NOT NULL
        CHECK (payment_method IN ('card', 'cash'))
);

CREATE TABLE item (
    sku CHAR(15) PRIMARY KEY,

    name VARCHAR(60) NOT NULL,
    department_id INT NOT NULL REFERENCES department(department_id),
    tax_exempt BOOLEAN NOT NULL
);

-- Your section