import os
import time
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Integer, String, create_engine, func, text
from sqlalchemy.orm import Session, declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://sports:sports@db:5432/sportsdb",
)
INSTANCE_NAME = os.getenv("INSTANCE_NAME", "app-unknown")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    sport = Column(String(50), nullable=False)
    home_team = Column(String(100), nullable=False)
    away_team = Column(String(100), nullable=False)
    home_score = Column(Integer, nullable=False, default=0)
    away_score = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class EventCreate(BaseModel):
    sport: Annotated[str, Field(min_length=2, max_length=50, examples=["Futebol"])]
    home_team: Annotated[str, Field(min_length=2, max_length=100, examples=["Brasil"])]
    away_team: Annotated[str, Field(min_length=2, max_length=100, examples=["Argentina"])]
    home_score: Annotated[int, Field(ge=0, examples=[2])] = 0
    away_score: Annotated[int, Field(ge=0, examples=[1])] = 0


class EventResponse(BaseModel):
    id: int
    sport: str
    home_team: str
    away_team: str
    home_score: int
    away_score: int
    instance: str

    model_config = {"from_attributes": True}


def wait_for_database(max_attempts: int = 30, delay_seconds: float = 2.0) -> None:
    for attempt in range(1, max_attempts + 1):
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            return
        except Exception:
            if attempt == max_attempts:
                raise
            time.sleep(delay_seconds)


@asynccontextmanager
async def lifespan(_: FastAPI):
    wait_for_database()
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="Sports Score API",
    description="API simples para registrar e consultar placares esportivos.",
    version="1.0.0",
    lifespan=lifespan,
)

Instrumentator().instrument(app).expose(app, include_in_schema=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/health")
def health():
    return {"status": "ok", "instance": INSTANCE_NAME}


@app.get("/events", response_model=list[EventResponse])
def list_events(db: Session = Depends(get_db)):
    events = db.query(Event).order_by(Event.id.desc()).all()
    return [
        EventResponse(
            id=event.id,
            sport=event.sport,
            home_team=event.home_team,
            away_team=event.away_team,
            home_score=event.home_score,
            away_score=event.away_score,
            instance=INSTANCE_NAME,
        )
        for event in events
    ]


@app.post("/events", response_model=EventResponse, status_code=201)
def create_event(payload: EventCreate, db: Session = Depends(get_db)):
    event = Event(
        sport=payload.sport,
        home_team=payload.home_team,
        away_team=payload.away_team,
        home_score=payload.home_score,
        away_score=payload.away_score,
    )
    db.add(event)
    db.commit()
    db.refresh(event)

    return EventResponse(
        id=event.id,
        sport=event.sport,
        home_team=event.home_team,
        away_team=event.away_team,
        home_score=event.home_score,
        away_score=event.away_score,
        instance=INSTANCE_NAME,
    )


@app.get("/events/{event_id}", response_model=EventResponse)
def get_event(event_id: int, db: Session = Depends(get_db)):
    event = db.query(Event).filter(Event.id == event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Evento não encontrado")

    return EventResponse(
        id=event.id,
        sport=event.sport,
        home_team=event.home_team,
        away_team=event.away_team,
        home_score=event.home_score,
        away_score=event.away_score,
        instance=INSTANCE_NAME,
    )
