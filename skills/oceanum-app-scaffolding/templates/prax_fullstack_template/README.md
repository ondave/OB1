# {{APP_NAME}}

{{APP_DESCRIPTION}}

A full-stack application built with React (TypeScript) frontend and FastAPI (Python) backend, designed for deployment on the Oceanum PRAX platform.

## Architecture

```
├── frontend/          # React + TypeScript + Vite
│   ├── src/          # React components and logic
│   ├── Dockerfile    # Frontend container
│   └── nginx.conf    # Production web server config
├── backend/          # FastAPI + Python
│   ├── app/          # Application code
│   │   ├── api/      # API endpoints
│   │   ├── core/     # Core configuration
│   │   └── models/   # Data models
│   ├── Dockerfile    # Backend container
│   └── requirements.txt
├── docker-compose.yml           # Production deployment
├── docker-compose.dev.yml       # Development environment
├── .oceanum-prax.yml           # PRAX deployment config
└── app-spec.yml                # Application specification
```

## Template Variables

Replace these placeholders throughout the codebase:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{APP_NAME}}` | Application name | `my-ocean-app` |
| `{{APP_DESCRIPTION}}` | Brief description | `Ocean data management system` |
| `{{USER_REF}}` | User namespace | `h2ocean` |
| `{{MEMBER_EMAIL}}` | Developer email | `dev@oceanum.science` |

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Node.js 20+ (for local development)
- Python 3.11+ (for local development)

### Development Mode

Run both frontend and backend with hot reload:

```bash
docker-compose -f docker-compose.dev.yml up
```

- Frontend: http://localhost:3000
- Backend API: http://localhost:8000
- API Docs: http://localhost:8000/docs

### Local Development (without Docker)

**Backend:**
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```

### Production Build

```bash
docker-compose up
```

Frontend will be available at http://localhost:80

## API Endpoints

Base URL: `/api/v1`

- `GET /api/v1/items` - Get all items
- `POST /api/v1/items` - Create new item
- `GET /api/v1/items/{id}` - Get specific item
- `DELETE /api/v1/items/{id}` - Delete item
- `GET /health` - Health check

## Application Specification

The `app-spec.yml` file contains a detailed specification of the application that can be used by Claude Code to build or extend features. It defines:

- Data models
- API endpoints
- Frontend components
- Backend features
- Testing requirements

Use this file when asking Claude Code to:
- Add new features
- Understand the application structure
- Generate new endpoints or components

## PRAX Deployment

### Deployment Stages

**Test Environment:**
- Triggers on commits to `main` branch
- Automatic deployment

**Production Environment:**
- Triggers on version tags matching `v\d+.\d+.\d+`
- Example: `v1.0.0`, `v2.3.1`

### Creating a Release

```bash
# Commit your changes
git add .
git commit -m "Release v1.0.0"

# Create and push tag
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

PRAX will automatically:
1. Build Docker images for frontend and backend
2. Deploy both services
3. Configure routing and health checks
4. Make the app publicly accessible

## Development Workflow

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Develop Locally**
   - Use `docker-compose.dev.yml` for hot reload
   - Backend changes reflect immediately
   - Frontend has HMR (Hot Module Replacement)

3. **Test Changes**
   - Test backend: http://localhost:8000/docs
   - Test frontend: http://localhost:3000

4. **Commit and Push**
   ```bash
   git add .
   git commit -m "Add my feature"
   git push origin feature/my-feature
   ```

5. **Merge to Main**
   - Creates automatic deployment to test environment

6. **Release to Production**
   - Create version tag for production deployment

## Extending the Application

### Adding Backend Endpoints

1. Add route handler to `backend/app/api/endpoints.py`
2. Define data model in `backend/app/models/schemas.py`
3. Update `app-spec.yml` with new endpoint details

### Adding Frontend Features

1. Create component in `frontend/src/`
2. Add API calls using axios
3. Import and use in `App.tsx`
4. Update `app-spec.yml` with new features

### Adding Database

Currently uses in-memory storage. To add a database:

1. Add database client to `backend/requirements.txt`
2. Create database configuration in `backend/app/core/config.py`
3. Add database models
4. Update docker-compose to include database service
5. Update `.oceanum-prax.yml` to include database service

## Environment Variables

**Backend (.env):**
- `PROJECT_NAME` - Application name
- `PROJECT_DESCRIPTION` - Application description
- `CORS_ORIGINS` - Allowed CORS origins

**Frontend (.env):**
- `VITE_APP_TITLE` - Application title
- `VITE_API_URL` - Backend API URL

## Troubleshooting

**CORS errors in development:**
- Ensure backend CORS_ORIGINS includes frontend URL
- Check Vite proxy configuration in `vite.config.ts`

**Docker build fails:**
- Clear Docker cache: `docker-compose down -v`
- Rebuild: `docker-compose build --no-cache`

**Hot reload not working:**
- Use `docker-compose.dev.yml` for development
- Ensure volumes are mounted correctly

## Technology Stack

- **Frontend:** React 18, TypeScript, Vite, Axios
- **Backend:** FastAPI, Python 3.11, Pydantic, Uvicorn
- **Web Server:** Nginx (production)
- **Containerization:** Docker, Docker Compose
- **Deployment:** PRAX (Oceanum platform)

## Project Structure

**Frontend:**
- `src/App.tsx` - Main application component
- `src/main.tsx` - Application entry point
- `src/*.css` - Styling
- `vite.config.ts` - Build configuration

**Backend:**
- `app/main.py` - FastAPI application
- `app/api/` - API route handlers
- `app/core/config.py` - Configuration
- `app/models/schemas.py` - Pydantic models

## License

[Your License Here]

## Support

For issues or questions, contact {{MEMBER_EMAIL}}
