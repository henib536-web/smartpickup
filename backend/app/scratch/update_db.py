from sqlalchemy import create_engine, text

SQLALCHEMY_DATABASE_URL = "postgresql://postgres:user@localhost/smartpickup"
engine = create_engine(SQLALCHEMY_DATABASE_URL)

def update_db():
    queries = [
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS current_lat FLOAT;",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS current_lng FLOAT;",
        "ALTER TABLE recurring_schedules ADD COLUMN IF NOT EXISTS pickup_lat DECIMAL(10, 8);",
        "ALTER TABLE recurring_schedules ADD COLUMN IF NOT EXISTS pickup_lng DECIMAL(11, 8);"
    ]
    
    with engine.connect() as conn:
        for query in queries:
            try:
                conn.execute(text(query))
                conn.commit()
                print(f"Executed: {query}")
            except Exception as e:
                print(f"Error executing {query}: {e}")

if __name__ == "__main__":
    update_db()
