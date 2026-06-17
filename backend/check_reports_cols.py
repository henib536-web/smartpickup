import psycopg2
conn = psycopg2.connect(user='postgres', password='root', host='localhost', database='smartpickup')
cur = conn.cursor()
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='incident_reports'")
columns = [row[0] for row in cur.fetchall()]
print(columns)
