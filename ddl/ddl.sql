-- drop tables to allow clean re-runs
-- (children before parents so FKs don't block the drops)
DROP TABLE IF EXISTS item_sale;
DROP TABLE IF EXISTS inventory;
DROP TABLE IF EXISTS store_transaction;
DROP TABLE IF EXISTS item;
DROP TABLE IF EXISTS store;
DROP TABLE IF EXISTS department;
DROP TABLE IF EXISTS tax;

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

    FOREIGN KEY (state_code) REFERENCES tax(state_code),
    CONSTRAINT aisle_count CHECK (aisles BETWEEN 20 AND 40)
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

    quantity_sold NUMERIC(8,3) NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,

    CONSTRAINT positive_quantity_sold CHECK(quantity_sold > 0),
    CONSTRAINT nonnegative_unit_price CHECK(unit_price >= 0),

    PRIMARY KEY (transaction_id, sku),
    FOREIGN KEY (transaction_id) REFERENCES store_transaction(transaction_id),
    FOREIGN KEY (sku) REFERENCES item(sku)
);

------------ Inventory ------------
CREATE TABLE inventory (
    sku VARCHAR(15),
    store_id INT,

    price NUMERIC(10,2) NOT NULL,
    quantity_in_stock NUMERIC(10,3) NOT NULL,

    aisle_no INT NOT NULL,

    CONSTRAINT positive_aisle_no CHECK (aisle_no >= 1),
    CONSTRAINT nonnegative_price CHECK (price >= 0),
    CONSTRAINT nonnegative_stock CHECK (quantity_in_stock >= 0),

    PRIMARY KEY(sku, store_id),
    FOREIGN KEY (sku) REFERENCES item(sku),
    FOREIGN KEY (store_id) REFERENCES store(store_id)
);

------------------------------------------------------------
------------ Random test data ------------
------------------------------------------------------------
-- fixed seed so re-runs produce the same "random" data
SELECT setseed(0.42);

------------ Tax ------------
INSERT INTO tax (state_code, tax_rate) VALUES
    ('TX', 0.0625),
    ('CA', 0.0725),
    ('NY', 0.0400),
    ('FL', 0.0600),
    ('LA', 0.0445),
    ('OK', 0.0450),
    ('AZ', 0.0560),
    ('GA', 0.0400),
    ('IL', 0.0625),
    ('AR', 0.0650),
    ('CO', 0.0290),
    ('NC', 0.0475),
    ('TN', 0.0700);

------------ Department ------------
INSERT INTO department (name) VALUES
    ('Produce'),
    ('Meat & Seafood'),
    ('Dairy'),
    ('Bakery'),
    ('Frozen'),
    ('Pantry'),
    ('Beverages'),
    ('Household'),
    ('Health & Beauty'),
    ('Deli'),
    ('Snacks'),
    ('Baby'),
    ('Pet Supplies');

------------ Store ------------
-- 100 stores with random addresses, cycling through cities in every taxed state
INSERT INTO store (city, street, zip_code, state_code, phone_number, aisles)
SELECT
    c.city,
    (100 + floor(random() * 9900))::int || ' ' ||
        (ARRAY['Main St','Oak Ave','Elm St','Park Blvd','Market St',
               'Cedar Ln','Lakeview Dr','Washington Ave'])[1 + floor(random() * 8)::int],
    lpad((10000 + floor(random() * 89999))::int::text, 5, '0'),
    c.state_code,
    '(' || (200 + floor(random() * 800))::int || ') '
        || (200 + floor(random() * 800))::int || '-'
        || lpad(floor(random() * 10000)::int::text, 4, '0'),
    20 + floor(random() * 21)::int
FROM generate_series(1, 100) AS n
JOIN (
    SELECT row_number() OVER () AS city_no, v.*
    FROM (VALUES
        ('Houston','TX'), ('Austin','TX'), ('Dallas','TX'), ('San Antonio','TX'),
        ('Fort Worth','TX'), ('El Paso','TX'),
        ('Los Angeles','CA'), ('San Diego','CA'), ('Fresno','CA'), ('Sacramento','CA'),
        ('Albany','NY'), ('Buffalo','NY'), ('Rochester','NY'),
        ('Miami','FL'), ('Tampa','FL'), ('Orlando','FL'), ('Jacksonville','FL'),
        ('Baton Rouge','LA'), ('New Orleans','LA'),
        ('Tulsa','OK'), ('Oklahoma City','OK'),
        ('Phoenix','AZ'), ('Tucson','AZ'),
        ('Atlanta','GA'), ('Savannah','GA'),
        ('Chicago','IL'), ('Springfield','IL'),
        ('Little Rock','AR'),
        ('Denver','CO'),
        ('Charlotte','NC'), ('Raleigh','NC'),
        ('Nashville','TN'), ('Memphis','TN')
    ) AS v(city, state_code)
) c ON c.city_no = 1 + (n - 1) % 33;

------------ Item ------------
-- realistic item names; SKUs are generated from the row number
INSERT INTO item (sku, name, department_id, tax_exempt, priced_by_weight)
SELECT
    'SKU' || lpad(row_number() OVER ()::text, 6, '0'),
    v.name,
    d.department_id,
    v.tax_exempt,
    v.by_weight
FROM (VALUES
    ('Bananas',               'Produce',         true,  true),
    ('Gala Apples',           'Produce',         true,  true),
    ('Roma Tomatoes',         'Produce',         true,  true),
    ('Yellow Onions',         'Produce',         true,  true),
    ('Russet Potatoes 5lb',   'Produce',         true,  false),
    ('Baby Spinach 10oz',     'Produce',         true,  false),
    ('Avocado',               'Produce',         true,  false),
    ('Ground Beef 80/20',     'Meat & Seafood',  true,  true),
    ('Chicken Breast',        'Meat & Seafood',  true,  true),
    ('Atlantic Salmon Fillet','Meat & Seafood',  true,  true),
    ('Pork Chops',            'Meat & Seafood',  true,  true),
    ('Thick Cut Bacon',       'Meat & Seafood',  true,  false),
    ('Whole Milk 1gal',       'Dairy',           true,  false),
    ('Large Eggs 12ct',       'Dairy',           true,  false),
    ('Cheddar Cheese 8oz',    'Dairy',           true,  false),
    ('Greek Yogurt',          'Dairy',           true,  false),
    ('Salted Butter',         'Dairy',           true,  false),
    ('Sourdough Loaf',        'Bakery',          true,  false),
    ('Blueberry Muffins 4ct', 'Bakery',          true,  false),
    ('Flour Tortillas',       'Bakery',          true,  false),
    ('Frozen Pizza',          'Frozen',          true,  false),
    ('Vanilla Ice Cream',     'Frozen',          true,  false),
    ('Frozen Peas',           'Frozen',          true,  false),
    ('Spaghetti 16oz',        'Pantry',          true,  false),
    ('Marinara Sauce',        'Pantry',          true,  false),
    ('Long Grain Rice 2lb',   'Pantry',          true,  false),
    ('Black Beans 15oz',      'Pantry',          true,  false),
    ('Peanut Butter',         'Pantry',          true,  false),
    ('Cheerios',              'Pantry',          true,  false),
    ('Ground Coffee',         'Beverages',       true,  false),
    ('Orange Juice',          'Beverages',       true,  false),
    ('Cola 12pk',             'Beverages',       false, false),
    ('Sparkling Water 8pk',   'Beverages',       false, false),
    ('Paper Towels 6pk',      'Household',       false, false),
    ('Dish Soap',             'Household',       false, false),
    ('Laundry Detergent',     'Household',       false, false),
    ('Trash Bags 30ct',       'Household',       false, false),
    ('Toothpaste',            'Health & Beauty', false, false),
    ('Shampoo',               'Health & Beauty', false, false),
    ('Ibuprofen 100ct',       'Health & Beauty', false, false),
    ('Sliced Turkey Breast',  'Deli',            true,  true),
    ('Swiss Cheese Sliced',   'Deli',            true,  true),
    ('Rotisserie Chicken',    'Deli',            true,  false),
    ('Potato Chips',          'Snacks',          true,  false),
    ('Tortilla Chips',        'Snacks',          true,  false),
    ('Chocolate Bar',         'Snacks',          false, false),
    ('Diapers 32ct',          'Baby',            false, false),
    ('Baby Wipes 72ct',       'Baby',            false, false),
    ('Infant Formula',        'Baby',            true,  false),
    ('Dry Dog Food 15lb',     'Pet Supplies',    false, false),
    ('Cat Litter 20lb',       'Pet Supplies',    false, false)
) AS v(name, dept, tax_exempt, by_weight)
JOIN department d ON d.name = v.dept;

------------ Inventory ------------
-- each store carries ~85% of items, with a store-specific price, stock and aisle
INSERT INTO inventory (sku, store_id, price, quantity_in_stock, aisle_no)
SELECT
    i.sku,
    s.store_id,
    round((0.99 + random() * 14)::numeric, 2),
    CASE WHEN i.priced_by_weight
         THEN round((random() * 200)::numeric, 3)
         ELSE floor(random() * 150) END,
    1 + floor(random() * s.aisles)::int
FROM store s
CROSS JOIN item i
WHERE random() < 0.85;

------------ Store Transaction ------------
-- 600 transactions over the past 90 days; total_amount is filled in below
INSERT INTO store_transaction (store_id, account_id, date_and_time, total_amount, payment_method)
SELECT
    t.store_id,
    CASE WHEN t.pay = 'card' THEN 1000 + floor(random() * 300)::int END,
    now() - random() * interval '90 days',
    0,
    t.pay
FROM (
    SELECT
        1 + floor(random() * (SELECT count(*) FROM store))::int AS store_id,
        CASE WHEN random() < 0.7 THEN 'card' ELSE 'cash' END AS pay
    FROM generate_series(1, 600)
) t;

------------ Item Sale ------------
-- 1-10 distinct items per transaction, drawn from that store's inventory
-- at that store's price
INSERT INTO item_sale (transaction_id, sku, quantity_sold, unit_price)
SELECT
    t.transaction_id,
    pick.sku,
    CASE WHEN pick.priced_by_weight
         THEN round((0.25 + random() * 4.75)::numeric, 3)
         ELSE 1 + floor(random() * 4) END,
    pick.price
FROM store_transaction t
CROSS JOIN LATERAL (
    SELECT inv.sku, inv.price, i.priced_by_weight
    FROM inventory inv
    JOIN item i ON i.sku = inv.sku
    WHERE inv.store_id = t.store_id
    ORDER BY random()
    LIMIT 1 + floor(random() * 10)::int + (t.transaction_id * 0)  -- correlate so it re-runs per row
) pick;

------------ Transaction totals ------------
-- total = sum of line items, plus the store's state tax on non-exempt items
UPDATE store_transaction t
SET total_amount = totals.total
FROM (
    SELECT
        s.transaction_id,
        round(sum(s.quantity_sold * s.unit_price
                  * CASE WHEN i.tax_exempt THEN 1 ELSE 1 + tx.tax_rate END), 2) AS total
    FROM item_sale s
    JOIN item i ON i.sku = s.sku
    JOIN store_transaction st ON st.transaction_id = s.transaction_id
    JOIN store st2 ON st2.store_id = st.store_id
    JOIN tax tx ON tx.state_code = st2.state_code
    GROUP BY s.transaction_id
) totals
WHERE t.transaction_id = totals.transaction_id;
