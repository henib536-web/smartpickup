from app.database.connection import engine
from sqlalchemy import text

def migrate():
    print("Starting PostgreSQL migration...")
    with engine.connect() as conn:
        # Check existing columns in recurring_schedules
        res = conn.execute(text("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'recurring_schedules'
        """))
        columns = [row[0] for row in res.fetchall()]
        print(f"Current columns in recurring_schedules: {columns}")

        new_columns = [
            ("pickup_lat", "DECIMAL(10, 8)"),
            ("pickup_lng", "DECIMAL(11, 8)"),
            ("dropoff_lat", "DECIMAL(10, 8)"),
            ("dropoff_lng", "DECIMAL(11, 8)")
        ]

        for col_name, col_type in new_columns:
            if col_name not in columns:
                print(f"Adding column {col_name} to recurring_schedules...")
                try:
                    conn.execute(text(f"ALTER TABLE recurring_schedules ADD COLUMN {col_name} {col_type}"))
                    conn.commit()
                    print(f"Column {col_name} added.")
                except Exception as e:
                    # In some SQLAlchemy versions/configs, commit might not be needed or handled differently
                    print(f"Error adding column {col_name}: {e}")
                    try:
                        conn.rollback()
                    except:
                        pass
            else:
                print(f"Column {col_name} already exists.")

        # Add priority_price to recurring_schedules if missing
        if "priority_price" not in columns:
            print("Adding priority_price to recurring_schedules...")
            conn.execute(text("ALTER TABLE recurring_schedules ADD COLUMN priority_price FLOAT DEFAULT 2.0"))
            conn.commit()

        # Add priority_price to ride_requests if missing
        res = conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name = 'ride_requests'"))
        req_columns = [row[0] for row in res.fetchall()]
        if "priority_price" not in req_columns:
            print("Adding priority_price to ride_requests...")
            conn.execute(text("ALTER TABLE ride_requests ADD COLUMN priority_price FLOAT DEFAULT 2.0"))
            conn.commit()

        # Add distance_km to ride_requests if missing
        if "distance_km" not in req_columns:
            print("Adding distance_km to ride_requests...")
            conn.execute(text("ALTER TABLE ride_requests ADD COLUMN distance_km DECIMAL(10, 2)"))
            conn.commit()
            print("Column distance_km added.")

        # Add estimated_price to ride_requests if missing
        if "estimated_price" not in req_columns:
            print("Adding estimated_price to ride_requests...")
            conn.execute(text("ALTER TABLE ride_requests ADD COLUMN estimated_price INTEGER"))
            conn.commit()
            print("Column estimated_price added.")

        # Add distance_km to recurring_schedules if missing
        if "distance_km" not in columns:
            print("Adding distance_km to recurring_schedules...")
            conn.execute(text("ALTER TABLE recurring_schedules ADD COLUMN distance_km DECIMAL(10, 2)"))
            conn.commit()
            print("Column distance_km added to recurring_schedules.")

        # Add estimated_price to recurring_schedules if missing
        if "estimated_price" not in columns:
            print("Adding estimated_price to recurring_schedules...")
            conn.execute(text("ALTER TABLE recurring_schedules ADD COLUMN estimated_price INTEGER"))
            conn.commit()
            print("Column estimated_price added to recurring_schedules.")

    print("Migration finished.")

if __name__ == "__main__":
    migrate()
