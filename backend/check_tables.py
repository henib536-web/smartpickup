import psycopg2
conn = psycopg2.connect(user='postgres', password='root', host='localhost', database='smartpickup')
cur = conn.cursor()
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
print(cur.fetchall())
cur.close()
conn.close()
