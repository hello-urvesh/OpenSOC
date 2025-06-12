# OpenSOC Case Management

This repository provides a minimal incident response case management tool built
with **FastAPI** and **SQLModel**. It offers a simple web interface for creating
cases and tracking tasks. Static assets such as stylesheets are served from the
`opensoc/static` directory.

## Features
- Create and list incident response cases
- Add tasks to a case
- Basic Bootstrap based UI

## Running
Install dependencies and start the development server:

```bash
pip install -r requirements.txt
python -m opensoc
```

The application will be available at [http://localhost:8000](http://localhost:8000) by default.
Set the `PORT` environment variable to use a different port if required:

```bash
PORT=8080 python -m opensoc
```

## Tests
Run unit tests with:

```bash
pytest
```
