-- Tax
CREATE TABLE tax (
  state_code char(2) PRIMARY KEY,
  tax_rate NUMERIC(5,4) NOT NULL
);

-- Department
CREATE TABLE department (
  department_id INT PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  price_by_weight BOOLEAN NOT NULL
);

-- Store
CREATE TABLE store (
  store_id INT PRIMARY KEY,
  address VARCHAR(255) NOT NULL,
  state_code CHAR(2) NOT NULL,
  phone_number VARCHAR(20) NOT NULL,
  FOREIGN KEY (state_code) REFERENCES tax(state_code)
);

CREATE TABLE item (
    sku CHAR(15) PRIMARY KEY,

    name VARCHAR(60) NOT NULL,
    department_id INT NOT NULL,
    FOREIGN KEY(department_id) REFERENCES department(department_id),
    tax_exempt BOOLEAN NOT NULL
);

CREATE TABLE store_transaction (
    transaction_id INT PRIMARY KEY,

    store_id INT NOT NULL,
    FOREIGN KEY(store_id) REFERENCES store(store_id),

    account_id INT,
    date_and_time TIMESTAMP NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,

    payment_method VARCHAR(4) NOT NULL
        CHECK (payment_method IN ('card', 'cash'))
);

CREATE TABLE item_sale (

    transaction_id INT,
    sku CHAR(15),

    sold_weight NUMERIC(8,3) NOT NULL,
    sold_count INT NOT NULL,
    sold_price NUMERIC(10,2) NOT NULL,

    PRIMARY KEY (transaction_id, sku),
    FOREIGN KEY (transaction_id) REFERENCES store_transaction(transaction_id),
    FOREIGN KEY (sku) REFERENCES item(sku)
);

-- Inventory_and_price
CREATE TABLE inventory_and_price (
  --double check sku and references
  sku CHAR(15),
  store_id INT,
  price NUMERIC(10,2) NOT NULL,
  num_in_stock INT NOT NULL,
  PRIMARY KEY(sku, store_id),
  FOREIGN KEY (sku) REFERENCES item(sku),
  FOREIGN KEY (store_id) REFERENCES store(store_id)
);
