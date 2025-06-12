from sqlmodel import create_engine, Session

engine = create_engine('sqlite:///opensoc.db', echo=False)


def get_session():
    return Session(engine)
