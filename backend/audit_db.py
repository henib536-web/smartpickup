import psycopg2

conn = psycopg2.connect(user='postgres', password='root', host='localhost', database='smartpickup')
cur = conn.cursor()

cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name")
tables = [r[0] for r in cur.fetchall()]
print("=== TABLES ===")
print(tables)

print("\n=== ROW COUNTS ===")
for t in tables:
    cur.execute(f"SELECT COUNT(*) FROM {t}")
    count = cur.fetchone()[0]
    print(f"  {t}: {count} rows")

cur.close()
conn.close()
