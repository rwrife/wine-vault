#!/usr/bin/env python3
"""Seed an EMPTY, dedicated screenshot simulator database with fictional wines.
Quit Wine Vault before running. Pass its vault.sqlite path as the only argument.
"""
import datetime as dt
import json
import sqlite3
import sys
import uuid

connection = sqlite3.connect(sys.argv[1])
assert connection.execute('SELECT COUNT(*) FROM bottles').fetchone()[0] == 0, 'Refusing to modify an existing collection'
now = dt.datetime.now(dt.timezone.utc)
wines = [
    ('Cabernet Sauvignon', 'Oak & Ember', 2021, 'Napa Valley', 'Cabernet Sauvignon', 6, 'Rack A · Shelf 1', ['Dinner party', 'Cellar favorite'], 365, 'Black cherry, cedar, and a long finish. Save a bottle for our anniversary.', '48'),
    ('Chardonnay', 'Golden Ridge', 2023, 'Sonoma Coast', 'Chardonnay', 4, 'Rack B · Shelf 2', ['Weekend favorites'], 20, 'Fresh pear and citrus with a soft, rounded finish.', '28'),
    ('Pinot Noir', 'Willow Creek', 2022, 'Willamette Valley', 'Pinot Noir', 5, 'Rack A · Shelf 2', ['Dinner party'], 60, 'Red cherry, forest floor, and a delicate finish.', '36'),
    ('Rosé', 'Domaine des Oliviers', 2025, 'Provence', 'Grenache', 3, 'Wine fridge', ['Summer evenings'], 10, 'Strawberry and citrus. Serve lightly chilled.', '22'),
    ('Sangiovese', 'Tenuta del Sole', 2020, 'Tuscany', 'Sangiovese', 6, 'Rack C · Shelf 1', ['For sharing'], 730, 'Sour cherry and dried herbs. A favorite for pasta night.', '42'),
    ('Sauvignon Blanc', 'Harbor Estate', 2024, 'Marlborough', 'Sauvignon Blanc', 4, 'Wine fridge', ['Weekend favorites'], 45, 'Bright lime, passion fruit, and a crisp finish.', '24'),
]
with connection:
    for name, producer, vintage, region, grape, quantity, location, tags, days, notes, price in wines:
        bottle_id = str(uuid.uuid4()).upper()
        connection.execute('INSERT INTO bottles (id,name,producer,vintage,region,grape,quantity,storageLocation,tags,drinkBy,photos,notes) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
            (bottle_id,name,producer,vintage,region,grape,quantity,location,json.dumps(tags),(now+dt.timedelta(days=days)).timestamp(),'[]',notes))
        quote_date=(now-dt.timedelta(days=7)).timestamp()
        connection.execute('INSERT INTO valuationQuotes (id,bottleID,quoteDate,amount,currency,source,retrievedAt,query) VALUES (?,?,?,?,?,?,?,?)',
            (str(uuid.uuid4()).upper(),bottle_id,quote_date,price,'USD','Manual entry',quote_date,f'{producer} {name} {vintage}'))
print('Created 6 fictional wines, 28 bottles, and manual sample prices.')
