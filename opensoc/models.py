from datetime import datetime
from typing import Optional, List
from sqlmodel import SQLModel, Field, Relationship


class Case(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str
    description: str = ""
    status: str = "open"
    created_at: datetime = Field(default_factory=datetime.utcnow)

    tasks: List["Task"] = Relationship(back_populates="case")


class Task(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    case_id: int = Field(foreign_key="case.id")
    title: str
    description: str = ""
    status: str = "pending"
    created_at: datetime = Field(default_factory=datetime.utcnow)

    case: Optional[Case] = Relationship(back_populates="tasks")
