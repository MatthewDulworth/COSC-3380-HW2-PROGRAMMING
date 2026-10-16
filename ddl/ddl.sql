-- My section 

-- Your section
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




    
