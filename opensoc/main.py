from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlmodel import SQLModel, select

from .database import engine, get_session
from .models import Case, Task

app = FastAPI(title="OpenSOC Case Management")
app.mount("/static", StaticFiles(directory="opensoc/static"), name="static")
templates = Jinja2Templates(directory="opensoc/templates")


@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)


@app.get("/", response_class=HTMLResponse)
def index(request: Request, session=Depends(get_session)):
    cases = session.exec(select(Case)).all()
    return templates.TemplateResponse("case_list.html", {"request": request, "cases": cases})


@app.get("/cases/new", response_class=HTMLResponse)
def new_case_form(request: Request):
    return templates.TemplateResponse("case_form.html", {"request": request})


@app.post("/cases/new")
def create_case(title: str = Form(...), description: str = Form(""), session=Depends(get_session)):
    case = Case(title=title, description=description)
    session.add(case)
    session.commit()
    return RedirectResponse(url="/", status_code=303)


@app.get("/cases/{case_id}", response_class=HTMLResponse)
def case_detail(request: Request, case_id: int, session=Depends(get_session)):
    case = session.get(Case, case_id)
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    tasks = session.exec(select(Task).where(Task.case_id == case_id)).all()
    return templates.TemplateResponse("case_detail.html", {"request": request, "case": case, "tasks": tasks})


@app.post("/cases/{case_id}/tasks")
def add_task(case_id: int, title: str = Form(...), description: str = Form(""), session=Depends(get_session)):
    case = session.get(Case, case_id)
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    task = Task(case_id=case_id, title=title, description=description)
    session.add(task)
    session.commit()
    return RedirectResponse(url=f"/cases/{case_id}", status_code=303)
