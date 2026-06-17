from sqlalchemy import create_engine, text

SQLALCHEMY_DATABASE_URL = "postgresql://postgres:user@localhost/smartpickup"
engine = create_engine(SQLALCHEMY_DATABASE_URL)

def update_table():
    queries = [
        # 1. Drop old constraint
        "ALTER TABLE incident_reports DROP CONSTRAINT IF EXISTS incident_reports_ride_id_fkey;",
        # 2. Add new constraint referencing ride_requests
        "ALTER TABLE incident_reports ADD CONSTRAINT incident_reports_ride_id_fkey FOREIGN KEY (ride_id) REFERENCES ride_requests(request_id);",
        # 3. Add description column
        "ALTER TABLE incident_reports ADD COLUMN IF NOT EXISTS description VARCHAR;"
    ]
    
    with engine.connect() as conn:
        for q in queries:
            try:
                conn.execute(text(q))
                conn.commit()
                print(f"Successfully executed: {q}")
            except Exception as e:
                print(f"Error executing: {q} -> {e}")

if __name__ == "__main__":
    update_table()
