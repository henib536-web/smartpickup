from sqlalchemy import create_engine, inspect

SQLALCHEMY_DATABASE_URL = "postgresql://postgres:user@localhost/smartpickup"
engine = create_engine(SQLALCHEMY_DATABASE_URL)

def inspect_table():
    inspector = inspect(engine)
    columns = inspector.get_columns("incident_reports")
    print("Columns in incident_reports:")
    for col in columns:
        print(f"  Name: {col['name']}, Type: {col['type']}, Nullable: {col['nullable']}")
        
    fks = inspector.get_foreign_keys("incident_reports")
    print("\nForeign keys in incident_reports:")
    for fk in fks:
        print(f"  Constrained Columns: {fk['constrained_columns']}, Referred Table: {fk['referred_table']}, Referred Columns: {fk['referred_columns']}")

if __name__ == "__main__":
    inspect_table()
