diff --git a//dev/null b/README.md
index 0000000000000000000000000000000000000000..6c38b2ed7897f6e2f73b43c3c54a7f9f24a44b5a 100644
--- a//dev/null
+++ b/README.md
@@ -0,0 +1,33 @@
+# OpenSOC Case Management
+
+This repository provides a minimal incident response case management tool built
+with **FastAPI** and **SQLModel**. It offers a simple web interface for creating
+cases and tracking tasks. Static assets such as stylesheets are served from the
+`opensoc/static` directory.
+
+## Features
+- Create and list incident response cases
+- Add tasks to a case
+- Basic Bootstrap based UI
+
+## Running
+Install dependencies and start the development server:
+
+```bash
+pip install -r requirements.txt
+python -m opensoc
+```
+
+The application will be available at [http://localhost:8000](http://localhost:8000) by default.
+Set the `PORT` environment variable to use a different port if required:
+
+```bash
+PORT=8080 python -m opensoc
+```
+
+## Tests
+Run unit tests with:
+
+```bash
+pytest
+```
