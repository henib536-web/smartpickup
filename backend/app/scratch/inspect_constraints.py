from sqlalchemy import create_engine, inspect

SQLALCHEMY_DATABASE_URL = "postgresql://postgres:user@localhost/smartpickup"
engine = create_engine(SQLALCHEMY_DATABASE_URL)

def inspect_constraints():
    inspector = inspect(engine)
    fks = inspector.get_foreign_keys("incident_reports")
    for fk in fks:
        print(f"Name: {fk.get('name')}")
        print(f"Constrained: {fk.get('constrained_columns')}")
        print(f"Referred: {fk.get('referred_table')} -> {fk.get('referred_columns')}")

if __name__ == "__main__":
    inspect_constraints()
